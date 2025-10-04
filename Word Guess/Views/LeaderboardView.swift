//
//  Scoreboard.swift
//  WordZap
//
//  Created by Barak Ben Hur on 15/10/2024.

import SwiftUI

// MARK: - Layout constants
private enum LBLayout {
    static let hSpacing: CGFloat = 10
    
    struct Columns {
        let place: CGFloat
        let name: CGFloat
        let score: CGFloat
        let guessed: CGFloat
        let total: CGFloat
    }
    
    /// Compute column widths that sum to the available width.
    /// On iPad we use proportions so NAME never eats the table.
    static func columns(for width: CGFloat, isPadLike: Bool) -> Columns {
        // header/row use .padding(.horizontal, 12) + 4 gaps between 5 columns
        let horizontalInsets: CGFloat = 24 + (hSpacing * 4)
        let available = max(0, width - horizontalInsets)
        
        if isPadLike {
            // Percentages of `available`
            let placeP:  CGFloat = 0.10
            let scoreP:  CGFloat = 0.15
            let guessP:  CGFloat = 0.15
            let totalP:  CGFloat = 0.15
            let nameP:   CGFloat = 1.0 - (placeP + scoreP + guessP + totalP) // = 0.45
            
            var place  = available * placeP
            var score  = available * scoreP
            var guess  = available * guessP
            var total  = available * totalP
            var name   = available * nameP
            
            // Minimums / maximums
            place = max(place, 60)
            score = max(score, 90)
            guess = max(guess, 90)
            total = max(total, 90)
            name  = max(min(name, 420), 260) // cap name (<=420) and keep readable (>=260)
            
            // If rounding/clamping pushed us over, nudge name down
            let sum = place + score + guess + total + name
            if sum > available {
                name -= (sum - available)
            }
            
            return .init(place: place, name: name, score: score, guessed: guess, total: total)
        } else {
            // Phone – keep compact widths; name flexes
            return .init(place: 44, name: .zero, score: 66, guessed: 62, total: 66)
        }
    }
}

// MARK: - Width measurement (replaces GeometryReader inside ScrollView)
private struct WidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct WidthReporter: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in
                Color.clear.preference(key: WidthKey.self, value: g.size.width)
            })
    }
}

// MARK: - Scoreboard
struct LeaderboardView<VM: ScoreboardViewModel>: View {
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    
    @Environment(\.horizontalSizeClass) private var hSize
    
    @State private var vm = VM()
    @State private var current: Int = 0
    @State private var selectedDifficultyIndex: Int = 0
    @State private var interstitialAdManager: InterstitialAdsManager?
    
    @State private var cardWidth: CGFloat = 0
    
    private var language: String? { local.locale.identifier.components(separatedBy: "_").first }
    private var isRTL: Bool { language == "he" }
    private var myEmailLower: String { (loginHandeler.model?.email ?? "").lowercased() }
    
    var body: some View {
        let isPadLike = (hSize == .regular) || UIDevice.current.userInterfaceIdiom == .pad
        
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: isPadLike ? 16 : 12) {
                // Title bar
                ZStack(alignment: .leading) {
                    BackButton(action: closeView)
                    HStack {
                        Spacer()
                        Text("SCOREBOARD")
                            .font(.system(size: isPadLike ? 31 : 26, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                }
                .padding(.horizontal, isPadLike ? 18 : 10)
                .padding(.top, isPadLike ? 8 : 4)
                
                // Build once so both fixed controls and table can use them
                if current < vm.data.count, vm.data.indices.contains(current) {
                    let day = vm.data[current]
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
                                email: m.email,
                                score: m.totalScore,
                                guessed: max(m.words.count - 1, 0),
                                total: max(totalWords - 2, 0),
                                isMe: m.email.lowercased() == myEmailLower
                            )
                        }
                    }
                    
                    // One reader for BOTH controls and table so the button can use `proxy`
                    ScrollViewReader { proxy in
                        // ---- Fixed controls (NOT scrollable) ----
                        VStack(spacing: isPadLike ? 20 : 16) {
                            DatePager(
                                title: day.value,
                                isRTL: isRTL,
                                canGoPrevious: isRTL ? (current < vm.data.count - 1) : (current > 0),
                                canGoNext:     isRTL ? (current > 0)                 : (current < vm.data.count - 1),
                                onPrevious: {
                                    if isRTL { if current < vm.data.count - 1 { current += 1 } }
                                    else if current > 0 { current -= 1 }
                                    selectedDifficultyIndex = 0
                                },
                                onNext: {
                                    if isRTL { if current > 0 { current -= 1 } }
                                    else if current < vm.data.count - 1 { current += 1 }
                                    selectedDifficultyIndex = 0
                                }
                            )
                            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                            .padding(.horizontal, isPadLike ? 4 : 0)
                            
                            if !myEmailLower.isEmpty {
                                Button {
                                    scrollToMe(proxy: proxy, rowsPerDifficulty: rowsPerDifficulty)
                                } label: {
                                    Label("Jump to my rank", systemImage: "person.crop.circle.badge.checkmark")
                                        .font(.footnote.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .tint(.accentColor)
                            }
                            
                            if !diffTitles.isEmpty {
                                DifficultyPicker(
                                    titles: diffTitles.map { prettyDifficulty($0) },
                                    selectedIndex: $selectedDifficultyIndex
                                )
                                .frame(maxWidth: isPadLike ? 520 : .infinity)
                                .transition(.opacity)
                            }
                        }
                        
                        // ---- TABLE AREA — the ONLY scrollable region ----
                        ScrollView(.vertical) {
                            let cols = LBLayout.columns(for: cardWidth, isPadLike: isPadLike)
                            LeaderboardCard(
                                rows: rowsPerDifficulty[safe: selectedDifficultyIndex] ?? [],
                                isRTL: isRTL,
                                cols: cols,
                                isPadLike: isPadLike
                            )
                            .frame(maxWidth: .infinity, alignment: .center)
                            .modifier(WidthReporter())
                            .onPreferenceChange(WidthKey.self) { cardWidth = $0 }
                            .padding(.bottom, 8)
                        }
                        .scrollIndicators(.visible)
                        .contentMargins(.bottom, 56)
                        .onAppear { scrollToMe(proxy: proxy, rowsPerDifficulty: rowsPerDifficulty) }
                        .onChange(of: selectedDifficultyIndex) {
                            scrollToMe(proxy: proxy, rowsPerDifficulty: rowsPerDifficulty)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // take leftover height so inner scroll works
                    .padding(.horizontal, isPadLike ? 22 : 16)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                } else {
                    EmptyStateCard()
                        .padding(.horizontal, isPadLike ? 22 : 16)
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .bottom) {
            AdProvider.adView(id: "ScoreBanner")
                .frame(height: 40)
                .background(.clear)
        }
        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        // Move banner to safe-area inset so it doesn't consume layout height or block scroll
        .task {
            guard let email = loginHandeler.model?.email else { return }
            await vm.items(email: email)
        }
        .onAppear {
            guard interstitialAdManager == nil || !interstitialAdManager!.initialInterstitialAdLoaded else { return }
            interstitialAdManager = AdProvider.interstitialAdsManager(id: "GameInterstitial")
            interstitialAdManager?.displayInitialInterstitialAd()
        }
        .onChange(of: vm.data) {
            current = max(vm.data.count - 1, 0)
            selectedDifficultyIndex = 0
        }
    }
}

// MARK: - Scroll helpers inside LeaderboardView
private extension LeaderboardView {
    /// Compute rows for current day & selection and return the target key for the signed-in email.
    func rowsForCurrentSelection() -> (rows: [LeaderboardRowModel], targetKey: String)? {
        guard current < vm.data.count, vm.data.indices.contains(current) else { return nil }
        let day = vm.data[current]
        let sortedDiffs = day.difficulties.sorted {
            DifficultyType(stripedRawValue: $0.value)!.getLength()
            < DifficultyType(stripedRawValue: $1.value)!.getLength()
        }
        let rowsPerDifficulty: [[LeaderboardRowModel]] = sortedDiffs.map { diff in
            let totalWords = diff.words.count
            let members = diff.members.sorted { $0.totalScore > $1.totalScore }
            return members.enumerated().map { idx, m in
                LeaderboardRowModel(
                    rank: idx + 1,
                    name: m.name,
                    email: m.email,
                    score: m.totalScore,
                    guessed: max(m.words.count - 1, 0),
                    total: max(totalWords - 2, 0),
                    isMe: m.email.lowercased() == myEmailLower // NEW
                )
            }
        }
        let rows = rowsPerDifficulty[safe: selectedDifficultyIndex] ?? []
        let myKey = "row-\(myEmailLower)"
        guard rows.contains(where: { $0.key == myKey }) else { return nil }
        return (rows, myKey)
    }
    
    func scrollToMe(proxy: ScrollViewProxy, rowsPerDifficulty: [[LeaderboardRowModel]]) {
        let myKey = "row-\(myEmailLower)"
        let rows = rowsPerDifficulty[safe: selectedDifficultyIndex] ?? []
        guard rows.contains(where: { $0.key == myKey }) else { return }
        withAnimation(.easeInOut) {
            proxy.scrollTo(myKey, anchor: .center)
        }
    }
    
    func closeView() {
        router.navigateBack()
    }
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
                .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 28 : 26,
                              weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
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
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
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
    }
}

private struct LeaderboardCard: View {
    let rows: [LeaderboardRowModel]
    let isRTL: Bool
    let cols: LBLayout.Columns
    let isPadLike: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: LBLayout.hSpacing) {
                header("Place").frame(width: cols.place)
                if isPadLike { header("Name").frame(width: cols.name, alignment: .leading) }
                else { header("Name").frame(maxWidth: .infinity, alignment: .leading) }
                header("Score").frame(width: cols.score)
                header("Guessed").frame(width: cols.guessed)
                header("Total").frame(width: cols.total)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isPadLike ? 11 : 9)
            .background(Color.primary.opacity(0.06))
            
            if rows.isEmpty {
                VStack(spacing: 10) {
                    Text("No results yet")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 18)
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(rows) { row in
                    LeaderboardRow(row: row, isRTL: isRTL, cols: cols, isPadLike: isPadLike)
                    Divider().opacity(0.15)
                }
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 12, y: 6)
    }
    
    private func header(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(isPadLike ? .subheadline : .footnote)
            .fontWeight(.semibold)
            .multilineTextAlignment(.center)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

private struct LeaderboardRow: View {
    let row: LeaderboardRowModel
    let isRTL: Bool
    let cols: LBLayout.Columns
    let isPadLike: Bool
    
    var body: some View {
        HStack(spacing: LBLayout.hSpacing) {
            RankBadge(rank: row.rank)
                .frame(width: cols.place, alignment: .center)
            
            // Name + email (name single-line, email wraps)
            VStack(alignment: isRTL ? .trailing : .leading, spacing: 2) {
                Text(row.name)
                    .multilineTextAlignment(.leading)
                    .font(isPadLike ? .title3 : .body)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                
//                if !row.email.isEmpty {
//                    Text(row.email)
//                        .font(isPadLike ? .footnote : .caption2)
//                        .foregroundStyle(.secondary)
//                        .lineLimit(2)
//                        .fixedSize(horizontal: false, vertical: true)
//                }
            }
            .frame(maxWidth: (isPadLike ? cols.name : .infinity), alignment: isRTL ? .trailing : .leading)
            .layoutPriority(2)
            
            Text("\(row.score)")
                .font(isPadLike ? .title3 : .body)
                .fontWeight(.medium)
                .monospacedDigit()
                .frame(width: cols.score)
            
            Text("\(row.guessed)")
                .font(isPadLike ? .title3 : .body)
                .fontWeight(.medium)
                .monospacedDigit()
                .frame(width: cols.guessed)
            
            Text("\(row.total)")
                .font(isPadLike ? .title3 : .body)
                .fontWeight(.medium)
                .monospacedDigit()
                .frame(width: cols.total)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isPadLike ? 14 : 12)
        .contentShape(Rectangle())
        .id(row.key) // ← make each row scroll-addressable
        // NEW: thin border to signify current user
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(row.isMe ? Color.accentColor.opacity(0.95) : .clear, lineWidth: 1)
        )
        .accessibilityHint(row.isMe ? Text("This is you") : Text(""))
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
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            
            HStack(spacing: 2) {
                if rank == 1 { Image(systemName: "crown.fill") }
                Text("\(rank)")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .foregroundStyle(foregroundStyle(rank))
        }
        .frame(height: 28) // smaller badge
    }
    
    private func foregroundStyle(_ r: Int) -> Color {
        switch r {
        case 1, 2, 3: return .white
        default: return .secondary
        }
    }
    
    private func badgeColors(_ r: Int) -> [Color] {
        switch r {
        case 1: return [Color.yellow.opacity(0.9), Color.orange.opacity(0.9)]
        case 2: return [Color.gray.opacity(0.85), Color.gray.opacity(0.65)]
        case 3: return [Color.brown.opacity(0.9), Color.orange.opacity(0.8)]
        default: return [Color.clear, Color.clear]
        }
    }
}

private struct EmptyStateCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No data yet")
                .font(.headline)
            Text("Play a game to see your daily leaderboard.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.top, 12)
    }
}

// MARK: - Models / helpers
private struct LeaderboardRowModel: Identifiable, Equatable {
    let id = UUID()
    let rank: Int
    let name: String
    let email: String
    let score: Int
    let guessed: Int
    let total: Int
    let isMe: Bool // NEW: identify current user row
    
    // Stable key for ScrollViewReader
    var key: String { "row-\(email.lowercased())" }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func prettyDifficulty(_ raw: String) -> String {
    let lower = raw.lowercased()
    if lower.contains("easy") { return "😀 Easy".localized }
    if lower.contains("medium") { return "😳 Medium".localized }
    if lower.contains("hard") { return "🥵 Hard".localized }
    return raw.capitalized
}
