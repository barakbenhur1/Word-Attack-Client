//
//  PremiumManager.swift
//  WordZap
//
//  Created by Barak Ben Hur on 11/09/2025.
//

import SwiftUI
import StoreKit

// Match your view
enum PremiumPlan: String, CaseIterable { case monthly, yearly }

@MainActor
protocol PremiumManagerProtocol: ObservableObject {
    var monthlyPriceText: String { get }
    var yearlyPriceText:  String { get }
    var yearlyBadgeText:  String? { get }
    var trialText:        String? { get }
    var isPurchasing:     Bool { get set }
    var isPremium:        Bool { get }
    func loadProducts() async
    func purchase(_ plan: PremiumPlan) async
    func restore() async
}

@MainActor
final class PremiumManager: PremiumManagerProtocol {
    // MARK: - Observed
    @Published var monthlyPriceText: String = "—"
    @Published var yearlyPriceText:  String = "—"
    @Published var yearlyBadgeText:  String? = nil
    @Published var trialText:        String? = nil
    @Published var isPurchasing:     Bool = false
    @Published var isPremium:        Bool = false
    @Published var justDone:         Bool = false

    // MARK: - Config (your product IDs)
    private let monthlyID = "WordZap.Premium.Monthly"
    private let yearlyID  = "WordZap.Premium.Yearly"      // OK if missing in ASC; view will still work

    // MARK: - Cache
    private var monthlyProduct: Product?
    private var yearlyProduct:  Product?
    private var updatesTask: Task<Void, Never>?
    
    static let shared = PremiumManager()

    private init() {
        updatesTask = listenForTransactions()
    }
    deinit { updatesTask?.cancel() }

    // MARK: - API

    func loadProducts() async {
        do {
            let ids: Set<String> = [monthlyID, yearlyID]
            let products = try await Product.products(for: Array(ids))

            // map
            for p in products {
                if p.id == monthlyID { monthlyProduct = p }
                if p.id == yearlyID  { yearlyProduct  = p }
            }

            // localized prices
            monthlyPriceText = monthlyProduct?.displayPrice ?? "—"
            yearlyPriceText  = yearlyProduct?.displayPrice  ?? "—"

            // trial text (prefer yearly's intro, fallback to monthly)
            trialText = introOfferText(from: yearlyProduct) ?? introOfferText(from: monthlyProduct)

            // savings badge (if both exist)
            if let y = yearlyProduct?.price, let m = monthlyProduct?.price, m > 0 {
                // cost of 12 months monthly vs one yearly
                let monthlyYearCost: Decimal = m * 12
                let savings: Decimal = max(monthlyYearCost - y, 0)
                if monthlyYearCost > 0 {
                    let pct = Int((NSDecimalNumber(decimal: savings).doubleValue /
                                   NSDecimalNumber(decimal: monthlyYearCost).doubleValue) * 100.0 + 0.5)
                    yearlyBadgeText = pct >= 5 ? "Save \(pct)%" : nil
                } else {
                    yearlyBadgeText = nil
                }
            } else {
                yearlyBadgeText = nil
            }

            await updateEntitlement()
        } catch {
            print("⚠️ StoreKit products error:", error)
        }
    }

    func purchase(_ plan: PremiumPlan) async {
        guard let product = product(for: plan) else { return }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if let transaction: StoreKit.Transaction = verify(verification) {
                    await transaction.finish()
                    await updateEntitlement()
                    self.justDone = true
                }
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            print("⚠️ Purchase failed:", error)
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await updateEntitlement()
        } catch {
            print("⚠️ Restore failed:", error)
        }
    }

    // MARK: - Internals

    private func product(for plan: PremiumPlan) -> Product? {
        switch plan {
        case .monthly: return monthlyProduct
        case .yearly:  return yearlyProduct
        }
    }

    private func introOfferText(from product: Product?) -> String? {
        guard let offer = product?.subscription?.introductoryOffer else { return nil }
        switch offer.paymentMode {
        case .freeTrial: return "\(periodText(offer.period)) free trial"
        case .payAsYouGo, .payUpFront:
            if offer.price == 0 { return "\(periodText(offer.period)) free trial" }
            return nil
        default: return nil
        }
    }

    private func periodText(_ period: Product.SubscriptionPeriod) -> String {
        let v = period.value
        switch period.unit {
        case .day:   return v == 1 ? "1-day"   : "\(v)-day"
        case .week:  return v == 1 ? "1-week"  : "\(v)-week"
        case .month: return v == 1 ? "1-month" : "\(v)-month"
        case .year:  return v == 1 ? "1-year"  : "\(v)-year"
        @unknown default: return "\(v)"
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard let self else { continue }
                if let t: StoreKit.Transaction = await self.verify(update) {
                    await t.finish()
                    await self.updateEntitlement()
                }
            }
        }
    }

    private func verify<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .unverified: return nil
        case .verified(let safe): return safe
        }
    }

    /// Treat ANY active auto-renewable sub as premium (keeps it simple & robust).
    private func updateEntitlement() async {
        var active = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if let t: StoreKit.Transaction = verify(result) {
                if t.productType == .autoRenewable { active = true }
            }
        }
        await MainActor.run {
            self.isPremium = true
        }
    }
}
