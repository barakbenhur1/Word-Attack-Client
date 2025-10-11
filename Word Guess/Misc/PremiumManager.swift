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
    
    private enum AutoRenewableID: String {
        case monthly = "WordZap.Premium.Monthly", yearly = "WordZap.Premium.Yearly"
    }
    
    private let premiumAutoRenewableIDs: Set<AutoRenewableID> = [
        .monthly,
        .yearly
    ]

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
            let stringIDs = premiumAutoRenewableIDs.map { $0.rawValue }
            let ids: Set<String> = Set(stringIDs)
            let products = try await Product.products(for: Array(ids))
            
            // map
            for p in products {
                guard let id = AutoRenewableID(rawValue: p.id) else { continue }
                switch id {
                case .monthly: monthlyProduct = p
                case .yearly: yearlyProduct  = p
                }
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
                    yearlyBadgeText = pct >= 5 ? "\("Save".localized) \(pct)%" : nil
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
        case .freeTrial: return "\(periodText(offer.period)) \("free trial".localized)"
        case .payAsYouGo, .payUpFront:
            if offer.price == 0 { return "\(periodText(offer.period)) \("free trial".localized)" }
            return nil
        default: return nil
        }
    }

    private func periodText(_ period: Product.SubscriptionPeriod) -> String {
        let v = period.value
        switch period.unit {
        case .day:   return v == 1 ? "1-\("day".localized)"   : "\(v)-\("day".localized)"
        case .week:  return v == 1 ? "1-\("week".localized)"  : "\(v)-\("week".localized)"
        case .month: return v == 1 ? "1-\("month".localized)" : "\(v)-\("month".localized)"
        case .year:  return v == 1 ? "1-\("year".localized)"  : "\(v)-\("year".localized)"
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
    
    private func none() {
        return
    }
    
    private func handleTrasaction(_ t: StoreKit.Transaction) {
        switch t.productType {
        case .autoRenewable: handleAutoRenewable(t)
        case .nonRenewable:  handleNonRenewable(t)
        case .consumable:    handleConsumable(t)
        case .nonConsumable: handleANonConsumable(t)
        default:             none()
        }
    }
    
    private func updateEntitlement() async {
        clear()
        for await result in StoreKit.Transaction.currentEntitlements {
            if let t: StoreKit.Transaction = verify(result) {
                handleTrasaction(t)
            }
        }
    }
}

@MainActor
extension PremiumManager {
    private func handleAutoRenewable(_ t: StoreKit.Transaction) {
        if let id = AutoRenewableID(rawValue: t.productID), premiumAutoRenewableIDs.contains(id) {
            isPremium = true
        }
    }
    
    private func handleNonRenewable(_ t: StoreKit.Transaction) {
        return
    }
    
    private func handleConsumable(_ t: StoreKit.Transaction) {
        return
    }
    
    private func handleANonConsumable(_ t: StoreKit.Transaction) {
        return
    }
    
    private func clear() {
        isPremium = false
    }
}
