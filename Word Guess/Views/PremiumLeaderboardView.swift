//
//  PremiumLeaderboardView.swift
//  WordZap
//
//  Created by Barak Ben Hur on 13/09/2025.
//

import SwiftUI
import Observation

// MARK: - Leaderboard

struct PremiumLeaderboardView<VM: PremiumLeaderboardViewModel>: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @Environment(\.horizontalSizeClass) private var hSize
    
    private var uniqe: String? { loginHandeler.model?.uniqe }
    private var myuniqeLower: String { (uniqe ?? "").lowercased() }
    
    @State private var vm = VM()
    
    var body: some View {
        ZStack(alignment: .top) {
            PremiumBackground()
                .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 26) {
                header
                
                Group {
                    if vm.data == nil {
                        skeletonList
                            .padding(.horizontal, 10)
                    } else if let items = vm.data, items.isEmpty {
                        emptyState
                    } else if let items = vm.data {
                        // Wrap the list in a ScrollViewReader so we can programmatically scroll
                        ScrollViewReader { proxy in
                            listBody(items: items, proxy: proxy)
                                .onAppear {
                                    // Auto-scroll on first appear after data arrives
                                    scrollToMe(proxy: proxy, items: items)
                                }
                                .onChange(of: vm.data) {
                                    // Auto-scroll when data refreshes
                                    scrollToMe(proxy: proxy, items: vm.data ?? [])
                                }
                                // === Go To Top Button ===
                                .overlay(alignment: .bottomTrailing) {
                                    Button {
                                        withAnimation(.easeInOut) {
                                            proxy.scrollTo("top-anchor", anchor: .top)
                                        }
                                    } label: {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .font(.system(size: 32, weight: .bold))
                                            .symbolRenderingMode(.hierarchical)
                                            .foregroundStyle(.white)
                                            .padding(12)
                                            .background(.ultraThinMaterial, in: Circle())
                                            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 16)
                                    .padding(.bottom, 16)
                                    .accessibilityLabel("Scroll to top")
                                    .zIndex(50)
                                }
                                // === End Go To Top Button ===
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 4)
        }
        .task {
            guard let uniqe else { return }
            await vm.items(uniqe: uniqe)
        }
        .refreshable {
            guard let uniqe else { return }
            await vm.items(uniqe: uniqe)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: Header
    
    private var header: some View {
        ZStack(alignment: .leading) {
            let isPadLike = (hSize == .regular) || UIDevice.current.userInterfaceIdiom == .pad
            
            BackButton(action: router.navigateBack)
                .padding(.top, -20)
            
            HStack(spacing: 4) {
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.system(size: isPadLike ? 27 : 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.yellow)
                    .shadow(color: .yellow.opacity(0.5), radius: 8, y: 2)
                Text("Premium Leaderboard")
                    .font(.system(size: isPadLike ? 27 : 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.dynamicBlack.opacity(0.92))
                Spacer()
            }
        }
    }
    
    // MARK: Body
    private func listBody(items: [PremiumScoreData], proxy: ScrollViewProxy) -> some View {
        // Only non-negative scores; highest first
        let sorted = items.filter { $0.value >= 0 }.sorted { $0.rank < $1.rank }
        let hasMe  = sorted.contains(where: { $0.uniqe.lowercased() == myuniqeLower })
        
        return VStack(spacing: 12) {
            // Optional jump-to-me helper
            if hasMe && !myuniqeLower.isEmpty {
                Button {
                    scrollToMe(proxy: proxy, items: sorted)
                } label: {
                    Label("Jump to my rank", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            ScrollView(showsIndicators: false) {
                // TOP ANCHOR (target for "go to top")
                Color.clear
                    .frame(height: 1)
                    .id("top-anchor")
                
                VStack(spacing: 10) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, entry in
                        if let uniqe {
                            LeaderboardRow(
                                rank: entry.rank,
                                entry: entry,
                                isCurrentUser: entry.uniqe.caseInsensitiveCompare(uniqe) == .orderedSame
                            )
                            .id(rowKey(for: entry.uniqe)) // ← make each row scroll-addressable
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.horizontal, 1)
                .padding(.bottom, 24)
            }
            .contentMargins(.top, 0)      // remove top edge gap
            .contentMargins(.bottom, 50)  // keep bottom breathing room
        }
    }
    
    private var skeletonList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { i in
                    SkeletonRow(isTop3: i < 3)
                }
            }
            .padding(.bottom, 24)
        }
    }
    
    private var emptyState: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                Text("No scores yet")
                    .font(.headline)
                    .foregroundStyle(Color.dynamicBlack)
                Text("Play premium rounds to climb the board.")
                    .font(.subheadline)
                    .foregroundStyle(Color.dynamicBlack.opacity(0.7))
            }
            .padding(24)
            .background(.thinMaterial.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Scroll helpers

private extension PremiumLeaderboardView {
    func rowKey(for uniqe: String) -> String { "row-\(uniqe.lowercased())" }
    
    func scrollToMe(proxy: ScrollViewProxy, items: [PremiumScoreData]) {
        guard !myuniqeLower.isEmpty else { return }
        guard items.contains(where: { $0.uniqe.lowercased() == myuniqeLower }) else { return }
        withAnimation(.easeInOut) {
            proxy.scrollTo(rowKey(for: myuniqeLower), anchor: .center)
        }
    }
}

// MARK: - Row

private struct LeaderboardRow: View {
    let rank: Int
    let entry: PremiumScoreData
    let isCurrentUser: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PremiumPaletteSafe.card)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(PremiumPaletteSafe.stroke, lineWidth: 1))
            
            HStack(spacing: 12) {
                RankBadge(rank: rank)
                
                Avatar(uniqe: entry.uniqe)
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.dynamicBlack.opacity(0.95))
                        .lineLimit(2)
                }
                
                Spacer()
                
                ScorePill(score: entry.value, highlighted: rank <= 3 || isCurrentUser)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .overlay(
            Group {
                if isCurrentUser {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(PremiumPaletteSafe.accent2.opacity(0.35), lineWidth: 1)
                        .shadow(color: PremiumPaletteSafe.accent2.opacity(0.4), radius: 8, y: 3)
                }
            }
        )
        .accessibilityLabel("\(rank). \(entry.uniqe), \(entry.value) points")
    }
}

// MARK: - Bits

private struct RankBadge: View {
    let rank: Int
    var body: some View {
        ZStack {
            Circle().fill(badgeBackground)
            Text("\(rank)")
                .minimumScaleFactor(0.3)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 2)
        }
        .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
        .frame(width: 28, height: 28)
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
    
    private var badgeBackground: LinearGradient {
        switch rank {
        case 1:
            return LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
        case 2:
            return LinearGradient(colors: [.gray.opacity(0.9), .gray.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        case 3:
            return LinearGradient(colors: [Color(hue: 0.08, saturation: 0.8, brightness: 0.95),
                                           Color(hue: 0.07, saturation: 0.6, brightness: 0.8)],
                                  startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct Avatar: View {
    let uniqe: String
    var body: some View {
        let initials = String(uniqe.prefix(1)).uppercased()
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [PremiumPaletteSafe.accent.opacity(0.55),
                                              PremiumPaletteSafe.accent2.opacity(0.55)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials)
                .font(.system(.subheadline, design: .rounded).weight(.black))
                .foregroundStyle(.black.opacity(0.85))
        }
        .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

private struct ScorePill: View {
    let score: Int
    let highlighted: Bool
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill").font(.system(size: 11, weight: .heavy))
            Text("\(score)")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .foregroundStyle(highlighted ? .black : .white)
        .background(Capsule().fill(highlighted ? PremiumPaletteSafe.accent : .white.opacity(0.12)))
        .overlay(Capsule().stroke(.white.opacity(highlighted ? 0.35 : 0.18), lineWidth: 1))
        .shadow(color: highlighted ? PremiumPaletteSafe.accent.opacity(0.4) : .clear, radius: 6, y: 2)
    }
}

struct SkeletonRow: View {
    let isTop3: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(PremiumPaletteSafe.card)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(PremiumPaletteSafe.stroke, lineWidth: 1))
            HStack(spacing: 12) {
                Circle().fill(Color.dynamicBlack.opacity(0.25)).frame(width: 28, height: 28)
                Circle().fill(Color.dynamicBlack.opacity(0.18)).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.dynamicBlack.opacity(0.22)).frame(width: 140, height: 10)
                    RoundedRectangle(cornerRadius: 4).fill(Color.dynamicBlack.opacity(0.16)).frame(width: 100, height: 8)
                }
                Spacer()
                RoundedRectangle(cornerRadius: 12).fill(Color.dynamicBlack.opacity(0.18)).frame(width: 66, height: 24)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .overlay(
            isTop3 ?
            RoundedRectangle(cornerRadius: 16)
                .stroke(.yellow.opacity(0.15), lineWidth: 1)
                .shadow(color: .yellow.opacity(0.25), radius: 6, y: 2)
            : nil
        )
        .redacted(reason: .placeholder)
        .shimmer()
    }
}

// MARK: - Helpers

private func displayName(_ uniqe: String) -> String {
    let local = uniqe.split(separator: "@").first.map(String.init) ?? uniqe
    guard local.count > 6 else { return local }
    let head = local.prefix(3)
    let tail = local.suffix(3)
    return "\(head)…\(tail)"
}

// Simple shimmer
private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -0.6
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(stops: [
                    .init(color: .clear, location: phase),
                    .init(color: Color.dynamicBlack.opacity(0.22), location: phase + 0.15),
                    .init(color: .clear, location: phase + 0.30),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                .blendMode(.plusLighter)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}
private extension View { func shimmer() -> some View { modifier(Shimmer()) } }

// MARK: - Premium Palette Fallback
private enum PremiumPaletteSafe {
    static var card: Color    { (try? _Card.get()) ?? Color.white.opacity(0.06) }
    static var stroke: Color  { (try? _Stroke.get()) ?? Color.white.opacity(0.09) }
    static var accent: Color  { (try? _Accent.get()) ?? Color.cyan }
    static var accent2: Color { (try? _Accent2.get()) ?? Color.mint }
    
    private enum _Card { static func get() throws -> Color { PremiumPalette.card } }
    private enum _Stroke { static func get() throws -> Color { PremiumPalette.stroke } }
    private enum _Accent { static func get() throws -> Color { PremiumPalette.accent } }
    private enum _Accent2 { static func get() throws -> Color { PremiumPalette.accent2 } }
}
