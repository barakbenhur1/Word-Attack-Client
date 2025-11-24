//
//  LeaderboardView.swift
//  WordZap
//
//  Created by Barak Ben Hur on 15/10/2024.
//

import SwiftUI

// MARK: - Layout & Style
private enum LB {
    static let hSpacing: CGFloat = 10
    static let corner: CGFloat  = 12
    static let headerCorner: CGFloat = 12
    static let maxCardWidth: CGFloat = 900
    static let rowHeight: CGFloat = 56
    
    struct Columns {
        let place: CGFloat
        let name: CGFloat
        let score: CGFloat
        let guessed: CGFloat
        let total: CGFloat
    }
    
    /// Compute column widths that sum to the available width.
    /// On iPad we reserve fixed widths for numeric columns and give the rest to NAME.
    static func columns(for width: CGFloat, isPadLike: Bool) -> Columns {
        // Header/row use .padding(.horizontal, 12) + 4 gaps between 5 columns
        let horizontalInsets: CGFloat = 24 + (hSpacing * 4)
        let available = max(0, width - horizontalInsets)
        
        if isPadLike {
            // Proportions as a starting point
            let placeP: CGFloat = 0.10
            let scoreP: CGFloat = 0.62
            let guessP: CGFloat = 0.12
            let totalP: CGFloat = 0.12
            
            var place = available * placeP
            var score = available * scoreP
            var guess = available * guessP
            var total = available * totalP
            
            // Minimums to keep numerics readable
            place = max(place, 64)
            score = max(score, 120)
            guess = max(guess, 72)
            total = max(total, 72)
            
            // Whatever remains goes to NAME (with a sensible floor)
            let minName: CGFloat = 160
            let used = place + score + guess + total
            let remaining = max(available - used, minName)
            
            return .init(place: place, name: remaining, score: score, guessed: guess, total: total)
        } else {
            // Phone – compact numerics, name flexes
            return .init(place: 44, name: .infinity, score: 94, guessed: 66, total: 66)
        }
    }
}

// MARK: - Shared Glass / Strokes
extension View {
    func glassCard(corner: CGFloat = LB.corner) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return self
            .background(.thinMaterial, in: shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, y: 6)
    }
    
    func subtleInnerSeparator(corner: CGFloat = LB.corner) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - Width measurement (replaces GeometryReader inside ScrollView)
private struct WidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct WidthReporter: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { g in
                Color.clear.preference(key: WidthKey.self, value: g.size.width)
            }
        )
    }
}

// MARK: - View
struct LeaderboardView<VM: LeaderboardViewModel>: View {
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    @Environment(\.horizontalSizeClass) private var hSize
    
    // Keep VM stable
    @StateObject private var vm: VM
    @State private var current: Int = 0
    @State private var selectedDifficultyIndex: Int = 0
    @State private var interstitialAdManager: InterstitialAdsManager?
    @State private var cardWidth: CGFloat = 0
    
    init() { _vm = StateObject(wrappedValue: VM()) }
    
    private var language: String? { local.locale.identifier.components(separatedBy: "_").first }
    private var uniqe: String? { loginHandeler.model?.uniqe }
    private var isRTL: Bool { language == "he" }
    private var myuniqeLower: String { (loginHandeler.model?.uniqe ?? "").lowercased() }
    
    var body: some View {
        let isPadLike = (hSize == .regular) || UIDevice.current.userInterfaceIdiom == .pad
        
        ZStack {
            GameViewBackground().ignoresSafeArea()
            
            VStack(spacing: 18) {
                // Title bar
                ZStack(alignment: .leading) {
                    BackButton(action: closeView)
                    HStack {
                        Spacer()
                        Text("SCOREBOARD")
                            .font(.system(size: isPadLike ? 31 : 26, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
                        Spacer()
                    }
                }
                .padding(.horizontal, isPadLike ? 10 : 2)
                .padding(.top, isPadLike ? 8 : 4)
                .padding(.bottom, 2)
                
                // Thin accent bar
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.4),
                        Color.accentColor.opacity(0.1)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 2)
                .opacity(0.6)
                .cornerRadius(1)
                .padding(.horizontal, 12)
                .blendMode(.plusLighter)
                
                Group {
                    if let items = vm.data {
                        if items.isEmpty {
                            EmptyStateCard()
                                .padding(.horizontal, isPadLike ? 16 : 14)
                                .frame(maxWidth: LB.maxCardWidth)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        } else if current < items.count, items.indices.contains(current) {
                            let day = items[current]
                            let sortedDiffs = day.difficulties.sorted {
                                DifficultyType(stripedRawValue: $0.value)!.getLength()
                                < DifficultyType(stripedRawValue: $1.value)!.getLength()
                            }
                            let diffTitles = sortedDiffs.map { $0.value }
                            let rowsPerDifficulty: [[LeaderboardRowModel]] = sortedDiffs.map { diff in
                                let totalWords = diff.words.count
                                let members = diff.members.sorted { $0.totalScore > $1.totalScore }
                                return members.enumerated().map { idx, m in
                                    LeaderboardRowModel(
                                        rank: idx + 1,
                                        name: m.name,
                                        uniqe: m.uniqe,
                                        score: m.totalScore,
                                        guessed: max(m.words.count - 1, 0),
                                        total: max(totalWords - 2, 0),
                                        isMe: m.uniqe.lowercased() == myuniqeLower
                                    )
                                }
                            }
                            
                            // ---- Fixed controls + Table (shared proxy) ----
                            ScrollViewReader { proxy in
                                VStack(spacing: isPadLike ? 18 : 14) {
                                    DatePager(
                                        title: day.value,
                                        isRTL: isRTL,
                                        canGoPrevious: isRTL ? (current < items.count - 1) : (current > 0),
                                        canGoNext: isRTL ? (current > 0) : (current < items.count - 1),
                                        onPrevious: {
                                            if isRTL {
                                                if current < items.count - 1 { current += 1 }
                                            } else if current > 0 {
                                                current -= 1
                                            }
                                            selectedDifficultyIndex = 0
                                        },
                                        onNext: {
                                            if isRTL {
                                                if current > 0 { current -= 1 }
                                            } else if current < items.count - 1 {
                                                current += 1
                                            }
                                            selectedDifficultyIndex = 0
                                        }
                                    )
                                    .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                                    .padding(.horizontal, isPadLike ? 4 : 0)
                                    
                                    let currentRows = rowsPerDifficulty[safe: selectedDifficultyIndex] ?? []
                                    if !myuniqeLower.isEmpty, currentRows.contains(where: { $0.isMe }) {
                                        Button {
                                            scrollToMe(proxy: proxy, rowsPerDifficulty: rowsPerDifficulty)
                                        } label: {
                                            Label("Jump to my rank", systemImage: "person.crop.circle.badge.checkmark")
                                                .font(.footnote.weight(.semibold))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.accentColor.opacity(0.88))
                                        .controlSize(.small)
                                        .accessibilityHint("Scroll to your position in the list")
                                    }
                                    
                                    if !diffTitles.isEmpty {
                                        DifficultyPicker(
                                            titles: diffTitles.map { prettyDifficulty($0) },
                                            selectedIndex: $selectedDifficultyIndex
                                        )
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 8)
                                        .transition(.opacity)
                                    }
                                }
                                
                                VStack(spacing: 2) {
                                    // Header row
                                    let cols = LB.columns(for: cardWidth, isPadLike: isPadLike)
                                    
                                    HStack(spacing: LB.hSpacing) {
                                        header("Place", isPadLike: isPadLike).frame(width: cols.place)
                                        
                                        if isPadLike {
                                            header("Name", isPadLike: isPadLike)
                                                .frame(width: cols.name, alignment: .leading)
                                        } else {
                                            header("Name", isPadLike: isPadLike)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        
                                        header("Score", isPadLike: isPadLike).frame(width: cols.score)
                                        header("Guessed", isPadLike: isPadLike).frame(width: cols.guessed)
                                        header("Total", isPadLike: isPadLike).frame(width: cols.total)
                                    }
                                    .padding(10)
                                    .padding(.vertical, 8)
                                    .onTapGesture { proxy.scrollTo("top-anchor", anchor: .top) }
                                    .glassCard(corner: LB.headerCorner)
                                    
                                    // ---- TABLE AREA — the ONLY scrollable region ----
                                    ScrollView(.vertical, showsIndicators: false) {
                                        Color.clear.frame(height: 1).id("top-anchor")
                                        
                                        LeaderboardCard(
                                            rows: rowsPerDifficulty[safe: selectedDifficultyIndex] ?? [],
                                            isRTL: isRTL,
                                            cols: cols,
                                            isPadLike: isPadLike
                                        )
                                        .modifier(WidthReporter())
                                        .onPreferenceChange(WidthKey.self) { cardWidth = $0 }
                                        .onAppear { cardWidth = UIScreen.main.bounds.width - 20 }
                                        .padding(.bottom, 8)
                                    }
                                    .contentMargins(.bottom, 40)
                                    .onAppear { scrollToMe(proxy: proxy, rowsPerDifficulty: rowsPerDifficulty) }
                                    .onChange(of: selectedDifficultyIndex) {
                                        withAnimation(.easeInOut) {
                                            scrollToMe(proxy: proxy, rowsPerDifficulty: rowsPerDifficulty)
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(maxWidth: LB.maxCardWidth)
                                .frame(maxHeight: .infinity, alignment: .top)
                            }
                        }
                    } else {
                        skeletonList
                            .padding(.horizontal, 10)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .bottom) {
            AdProvider.adView(id: "ScoreBanner")
                .frame(height: 40)
                .background(.clear)
        }
        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        .refreshable {
            guard let uniqe else { return }
            await vm.items(uniqe: uniqe)
        }
        .task {
            guard let uniqe else { return }
            await vm.items(uniqe: uniqe)
        }
        .onAppear {
            guard interstitialAdManager == nil || !(interstitialAdManager?.initialInterstitialAdLoaded ?? false) else { return }
            interstitialAdManager = AdProvider.interstitialAdsManager(id: "GameInterstitial")
            interstitialAdManager?.displayInitialInterstitialAd()
        }
        .onChange(of: vm.data) {
            guard let items = vm.data else { return }
            current = max(items.count - 1, 0)
            selectedDifficultyIndex = 0
        }
    }
    
    @ViewBuilder
    private func header(_ text: LocalizedStringKey, isPadLike: Bool) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .font(isPadLike ? .subheadline : .footnote)
            .fontWeight(.semibold)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .accessibilityAddTraits(.isHeader)
    }
    
    private var skeletonList: some View {
        // If you have your own SkeletonRow, this keeps using it.
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { i in
                    SkeletonRow(isTop3: i < 3)
                        .glassCard()
                        .redacted(reason: .placeholder)
                        .shimmer()
                }
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Scroll helpers
extension LeaderboardView {
    fileprivate func scrollToMe(proxy: ScrollViewProxy, rowsPerDifficulty: [[LeaderboardRowModel]]) {
        let myKey = "row-\(myuniqeLower)"
        let rows = rowsPerDifficulty[safe: selectedDifficultyIndex] ?? []
        guard rows.contains(where: { $0.key == myKey }) else { return }
        withAnimation(.easeInOut) {
            proxy.scrollTo(myKey, anchor: .center)
        }
    }
    fileprivate func closeView() { router.navigateBack() }
}

// MARK: - Components

private struct DatePager: View {
    let title: String
    let isRTL: Bool
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrevious) {
                Image(systemName: isRTL ? "chevron.right" : "chevron.left")
                    .font(.title2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canGoPrevious ? .primary : .secondary)
            .disabled(!canGoPrevious)
            
            Text(title)
                .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 22 : 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(Text("Day: \(title)"))
                .transition(.opacity.combined(with: .scale))
            
            Button(action: onNext) {
                Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                    .font(.title2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canGoNext ? .primary : .secondary)
            .disabled(!canGoNext)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, UIDevice.current.userInterfaceIdiom == .pad ? 12 : 10)
        .glassCard(corner: 18)
    }
}

private struct DifficultyPicker: View {
    let titles: [String]
    @Binding var selectedIndex: Int
    
    var body: some View {
        Picker("", selection: $selectedIndex) {
            ForEach(Array(titles.enumerated()), id: \.offset) { idx, title in
                Text(title.localized).tag(idx)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 2)
        .accessibilityLabel("Difficulty")
    }
}

private struct LeaderboardCard: View {
    let rows: [LeaderboardRowModel]
    let isRTL: Bool
    let cols: LB.Columns
    let isPadLike: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                VStack(spacing: 10) {
                    Text("No results yet")
                        .font(.callout).fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 18)
                }
                .frame(maxWidth: .infinity)
                .glassCard()
            } else {
                // Enumerate to style even/odd and podium
                ForEach(Array(rows.enumerated()), id: \.1.id) { index, row in
                    LeaderboardRow(index: index, row: row, isRTL: isRTL, cols: cols, isPadLike: isPadLike)
                    Divider().opacity(0.08)
                }
            }
        }
        .glassCard()
    }
}

private struct LeaderboardRow: View {
    let index: Int
    let row: LeaderboardRowModel
    let isRTL: Bool
    let cols: LB.Columns
    let isPadLike: Bool
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: LB.hSpacing) {
            RankBadge(rank: row.rank)
                .frame(width: cols.place, alignment: .center)
                .accessibilityLabel(Text("Rank \(row.rank)"))
            
            // Name (FIX: respect finite name width)
            VStack(alignment: isRTL ? .trailing : .leading, spacing: 2) {
                Text(row.name)
                    .font(isPadLike ? .title3 : .body)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .multilineTextAlignment(.leading)
            }
            .frame(
                maxWidth: cols.name.isFinite ? nil : .infinity,
                alignment: isRTL ? .trailing : .leading
            )
            .layoutPriority(2)
            
            MetricPill(text: "\(row.score)")
                .frame(width: cols.score)
            MetricPill(text: "\(row.guessed)")
                .frame(width: cols.guessed)
            MetricPill(text: "\(row.total)")
                .frame(width: cols.total)
        }
        .frame(height: LB.rowHeight)
        .padding(.horizontal, 12)
        .padding(.vertical, isPadLike ? 12 : 10)
        .contentShape(Rectangle())
        .id(row.key)
        .background(rowBackground(index: index, isMe: row.isMe))
        .overlay(row.isMe ? myRowStroke : nil)
        .onHover { hovering in
#if os(iOS)
            // iPad pointer hover supported on iPadOS with a pointing device
#endif
            withAnimation(.easeInOut(duration: 0.18)) { isHovering = hovering }
        }
        .hoverEffect(.highlight) // iPadOS / iOS effect when applicable
        .animation(.easeInOut(duration: 0.18), value: isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityHint(row.isMe ? "This is you" : "")
    }
    
    // Subviews / styling
    
    private var myRowStroke: some View {
        RoundedRectangle(cornerRadius: LB.corner, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.95),
                        Color.accentColor.opacity(0.35)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )
            .blendMode(.plusLighter)
            .padding(.vertical, 3)
            .padding(.horizontal, 3)
    }
    
    @ViewBuilder
    private func rowBackground(index: Int, isMe: Bool) -> some View {
        if row.rank <= 3 {
            RoundedRectangle(cornerRadius: LB.corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: podiumColors(rank: row.rank),
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ).opacity(0.14)
                )
                .padding(.vertical, 3)
                .padding(.horizontal, 3)
        } else {
            (index % 2 == 0 ? Color.primary.opacity(0.03) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: LB.corner, style: .continuous))
        }
    }
    
    private func podiumColors(rank: Int) -> [Color] {
        switch rank {
        case 1: return [Color.yellow, .orange]
        case 2: return [Color.gray.opacity(0.9), .gray.opacity(0.6)]
        case 3: return [Color.brown.opacity(0.9), .orange.opacity(0.7)]
        default: return [.clear, .clear]
        }
    }
}

private struct MetricPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .monospacedDigit()
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.75)
            )
            .contentTransition(.numericText())
            .minimumScaleFactor(0.8)
    }
}

private struct RankBadge: View {
    let rank: Int
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: badgeColors(rank),
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                        .blendMode(.plusLighter)
                )
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            
            HStack(spacing: 4) {
                if rank == 1 { Image(systemName: "crown.fill").font(.footnote) }
                Text("\(rank)")
                    .minimumScaleFactor(0.3)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(foregroundStyle(rank))
        }
        .frame(height: 28)
    }
    
    private func foregroundStyle(_ r: Int) -> Color {
        switch r {
        case 1, 2, 3: return .white
        default: return .secondary
        }
    }
    private func badgeColors(_ r: Int) -> [Color] {
        switch r {
        case 1: return [Color.yellow.opacity(0.95), Color.orange.opacity(0.90)]
        case 2: return [Color.gray.opacity(0.90), Color.gray.opacity(0.65)]
        case 3: return [Color.brown.opacity(0.90), Color.orange.opacity(0.80)]
        default: return [Color.clear, Color.clear]
        }
    }
}

private struct EmptyStateCard: View {
    var body: some View {
        ScrollViewReader { _ in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No data yet").font(.headline)
                    Text("Play a game to see your daily leaderboard.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .glassCard(corner: 16)
            }
        }
    }
}

// MARK: - Models / helpers
private struct LeaderboardRowModel: Identifiable, Equatable {
    // Stable ID keeps ScrollViewReader targets valid across refreshes
    var id: String { key }
    let rank: Int
    let name: String
    let uniqe: String
    let score: Int
    let guessed: Int
    let total: Int
    let isMe: Bool
    
    var key: String { "row-\(uniqe.lowercased())" }
}

extension Collection {
    fileprivate subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

@MainActor
private func prettyDifficulty(_ raw: String) -> String {
    let lower = raw.lowercased()
    if lower.contains("easy")   { return "😀 Easy".localized }
    if lower.contains("medium") { return "😳 Medium".localized }
    if lower.contains("hard")   { return "🥵 Hard".localized }
    return raw.capitalized
}

// MARK: - Lightweight shimmer for placeholders (no deps)
private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -0.6
    func body(content: Content) -> some View {
        content
            .overlay(LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .white.opacity(0.0), location: 0.0),
                    .init(color: .white.opacity(0.35), location: 0.45),
                    .init(color: .white.opacity(0.0), location: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .blendMode(.plusLighter)
                .mask(content)
                .offset(x: phase * 240, y: phase * 140))
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}
