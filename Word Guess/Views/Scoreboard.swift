//
//  Scoreboard.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 15/10/2024.
//  Pro UI rev 2025-08-29 (responsive cols, chip difficulty, no-wrap name)
//

import SwiftUI

// MARK: - Layout constants
private enum LBLayout {
    static let placeW: CGFloat = 44
    static let scoreW: CGFloat = 66
    static let guessedW: CGFloat = 62
    static let totalW: CGFloat = 66
    static let hSpacing: CGFloat = 10
}

struct Scoreboard<VM: ScoreboardViewModel>: View {
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    
    @State private var vm = VM()
    @State private var current: Int = 0
    @State private var selectedDifficultyIndex: Int = 0
    
    private var language: String? { local.locale.identifier.components(separatedBy: "_").first }
    private var isRTL: Bool { language == "he" }
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 12) {
                
                // Title bar
                ZStack(alignment: .leading) {
                    BackButton(action: router.navigateBack)
                    HStack {
                        Spacer()
                        Text("SCOREBOARD")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                
                ScrollView(.vertical) {
                    VStack(spacing: 16) {
                        if current < vm.data.count, vm.data.indices.contains(current) {
                            let day = vm.data[current]
                            
                            // Sort difficulties by word length
                            let sortedDiffs = day.difficulties.sorted { DifficultyType(rawValue: $0.value)!.getLength() < DifficultyType(rawValue: $1.value)!.getLength() }
                            let diffTitles = sortedDiffs.map { $0.value }
                            
                            // Build rows per difficulty
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
                                        total: max(totalWords - 2, 0)
                                    )
                                }
                            }
                            
                            // Date pager
                            DatePager(
                                title: day.value,
                                isRTL: isRTL,
                                canGoPrevious: isRTL ? (current < vm.data.count - 1) : (current > 0),
                                canGoNext:     isRTL ? (current > 0)                 : (current < vm.data.count - 1),
                                onPrevious: {
                                    if isRTL {
                                        if current < vm.data.count - 1 { current += 1 }
                                    } else if current > 0 {
                                        current -= 1
                                    }
                                    selectedDifficultyIndex = 0
                                },
                                onNext: {
                                    if isRTL {
                                        if current > 0 { current -= 1 }
                                    } else if current < vm.data.count - 1 {
                                        current += 1
                                    }
                                    selectedDifficultyIndex = 0
                                }
                            )
                            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                            
                            // Difficulty picker (always segmented, even if only one option)
                            if !diffTitles.isEmpty {
                                DifficultyPicker(
                                    titles: diffTitles.map { prettyDifficulty($0) },
                                    selectedIndex: $selectedDifficultyIndex
                                )
                                .transition(.opacity)
                            }
                            
                            // Leaderboard card
                            LeaderboardCard(
                                rows: rowsPerDifficulty[safe: selectedDifficultyIndex] ?? [],
                                isRTL: isRTL
                            )
                        } else {
                            EmptyStateCard()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
                
                // Ad
                AdView(adUnitID: "ScoreBanner")
            }
        }
        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        .task { await vm.items(email: loginHandeler.model?.email ?? "") }
        .onChange(of: vm.data) {
            current = max(vm.data.count - 1, 0)
            selectedDifficultyIndex = 0
        }
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
                .font(.system(size: 26, weight: .bold, design: .rounded))
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
        .padding(.vertical, 10)
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

private struct DifficultyChip: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct LeaderboardCard: View {
    let rows: [LeaderboardRowModel]
    let isRTL: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: LBLayout.hSpacing) {
                header("Place").frame(width: LBLayout.placeW)
                header("Name").frame(maxWidth: .infinity)
                header("Score").frame(width: LBLayout.scoreW)
                header("Guessed").frame(width: LBLayout.guessedW)
                header("Total").frame(width: LBLayout.totalW)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.06))
            
            if rows.isEmpty {
                VStack(spacing: 10) {
                    Text("No results yet")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 18)
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(rows) { row in
                    LeaderboardRow(row: row, isRTL: isRTL)
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
            .font(.footnote.weight(.semibold))
            .multilineTextAlignment(.center)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

private struct LeaderboardRow: View {
    let row: LeaderboardRowModel
    let isRTL: Bool
    
    var body: some View {
        HStack(spacing: LBLayout.hSpacing) {
            RankBadge(rank: row.rank)
                .frame(width: LBLayout.placeW, alignment: .center)
            
            // Name + email (name single-line, email wraps)
            VStack(alignment: isRTL ? .trailing : .leading, spacing: 2) {
                Text(row.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                
                if !row.email.isEmpty {
                    Text(row.email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)                           // <- allow wrapping
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
            .layoutPriority(2) // give the name/email column priority over numbers
            
            Text("\(row.score)")
                .font(.body.monospacedDigit().weight(.medium))
                .frame(width: LBLayout.scoreW)
            
            Text("\(row.guessed)")
                .font(.body.monospacedDigit().weight(.medium))
                .frame(width: LBLayout.guessedW)
            
            Text("\(row.total)")
                .font(.body.monospacedDigit().weight(.medium))
                .frame(width: LBLayout.totalW)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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
                    .font(.callout.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(foregroundStyle(rank))
        }
        .frame(height: 28) // smaller badge
    }
    
    private func foregroundStyle(_ r: Int) -> Color {
        switch r {
        case 1, 2 ,3: return .white
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
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func prettyDifficulty(_ raw: String) -> String {
    let lower = raw.lowercased()
    if lower.contains("easy") { return "🙂 Easy" }
    if lower.contains("medium") { return "😳 Medium" }
    if lower.contains("hard") { return "🥵 Hard" }
    return raw.capitalized
}
