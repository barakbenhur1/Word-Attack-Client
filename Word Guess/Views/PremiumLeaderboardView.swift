//
//  PremiumLeaderboardView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 13/09/2025.
//

import SwiftUI
import Observation

// MARK: - Leaderboard

struct PremiumLeaderboardView<VM: PremiumScoreboardViewModel>: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var loginHandeler: LoginHandeler
    
    @Environment(\.horizontalSizeClass) private var hSize
    
    private var email: String? { loginHandeler.model?.email }
    
    @State private var vm = VM()
    
    var body: some View {
        ZStack(alignment: .top) {
            // PremiumHub background
            LinearGradient(colors: [Color.black, Color(hue: 0.64, saturation: 0.25, brightness: 0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 16) {
                header
                
                Group {
                    if vm.data == nil {
                        skeletonList
                    } else if let items = vm.data, items.isEmpty {
                        emptyState
                    } else if let items = vm.data {
                        listBody(items: items)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .task {
            guard let email else { return }
            await vm.items(email: email)
        }
        .refreshable {
            guard let email else { return }
            await vm.items(email: email)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: Header
    
    private var header: some View {
        ZStack(alignment: .leading) {
            let isPadLike = (hSize == .regular) || UIDevice.current.userInterfaceIdiom == .pad
            
            BackButton(action: router.navigateBack)
                .environment(\.colorScheme, .dark)
            
            HStack(spacing: 4) {
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.system(size: isPadLike ? 23 : 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)
                    .shadow(color: .yellow.opacity(0.5), radius: 8, y: 2)
                Text("Premium Leaderboard".localized)
                    .font(.system(size: isPadLike ? 23 : 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
            }
        }
    }
    
    // MARK: Body
    
    private func listBody(items: [PremiumScoreData]) -> some View {
        // Only non-negative scores; highest first
        let sorted = items.filter { $0.value >= 0 }.sorted { $0.value > $1.value }
        
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, entry in
                    if let email {
                        LeaderboardRow(
                            rank: idx + 1,
                            entry: entry,
                            isCurrentUser: entry.email.caseInsensitiveCompare(email) == .orderedSame
                        )
                    }
                }
            }
            .padding(.bottom, 24)
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
        VStack(spacing: 8) {
            Text("No scores yet".localized)
                .font(.headline)
                .foregroundStyle(.white)
            Text("Play premium rounds to climb the board.".localized)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
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
                
                Avatar(email: entry.email)
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                    Text(entry.email)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                
                Spacer()
                
                ScorePill(score: entry.value, highlighted: rank <= 3 || isCurrentUser)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .overlay(
            Group {
                if rank <= 3 || isCurrentUser {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(glowColor.opacity(0.35), lineWidth: 1)
                        .shadow(color: glowColor.opacity(0.4), radius: 8, y: 3)
                }
            }
        )
        .accessibilityLabel("\(rank). \(entry.email), \(entry.value) points")
    }
    
    private var glowColor: Color {
        if isCurrentUser { return PremiumPaletteSafe.accent2 }
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .clear
        }
    }
}

// MARK: - Bits

private struct RankBadge: View {
    let rank: Int
    var body: some View {
        ZStack {
            Circle().fill(badgeBackground)
            Text("\(rank)")
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
    let email: String
    var body: some View {
        let initials = String(email.prefix(1)).uppercased()
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

private struct SkeletonRow: View {
    let isTop3: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(PremiumPaletteSafe.card)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(PremiumPaletteSafe.stroke, lineWidth: 1))
            HStack(spacing: 12) {
                Circle().fill(.white.opacity(0.25)).frame(width: 28, height: 28)
                Circle().fill(.white.opacity(0.18)).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.22)).frame(width: 140, height: 10)
                    RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.16)).frame(width: 100, height: 8)
                }
                Spacer()
                RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.18)).frame(width: 66, height: 24)
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

private func displayName(_ email: String) -> String {
    let local = email.split(separator: "@").first.map(String.init) ?? email
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
                    .init(color: .white.opacity(0.22), location: phase + 0.15),
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
