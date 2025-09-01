//
//  WordZapWidget.swift
//  WordZapWidgetExtension
//
//  Created by Barak Ben Hur on 30/08/2025.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Entry
struct WordZapEntry: TimelineEntry {
    let date: Date
    let difficulty: Difficulty
    let answers: Int?         // from per-difficulty stats
    let score: Int?           // from per-difficulty stats
    let place: Int?           // from LeaderboaredPlaceData (NOT from stats)
    let aiName: String?
    let aiImageName: String?
    let aiTooltip: String?
}

// MARK: - Provider (time-driven cycle: easy → medium → hard → …)
struct WordZapProvider: TimelineProvider {
    
#if DEBUG
    private let cycleSeconds: TimeInterval = 20           // fast in simulator
#else
    private let cycleSeconds: TimeInterval = 60 * 4      // 4 minutes on device
#endif
    
    private let order: [Difficulty] = [.easy, .medium, .hard]
    
    func placeholder(in context: Context) -> WordZapEntry {
        entry(at: Date())
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WordZapEntry) -> Void) {
        completion(entry(at: Date()))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WordZapEntry>) -> Void) {
        let now = Date()
        let start = alignedBoundary(after: now, interval: cycleSeconds, includeNow: true)
        
        // Provide several future entries so the system flips without asking again.
        let steps = 6
        var entries: [WordZapEntry] = []
        for i in 0..<steps {
            let ts = start.addingTimeInterval(Double(i) * cycleSeconds)
            entries.append(entry(at: ts))
        }
        
        let policy: TimelineReloadPolicy = .after(entries.last!.date.addingTimeInterval(cycleSeconds))
        completion(Timeline(entries: entries, policy: policy))
    }
    
    // Build one entry for a specific time slot.
    private func entry(at date: Date) -> WordZapEntry {
        let diff = difficulty(for: date)
        
        let stats   = SharedStore.readDifficultyStats(for: diff)         // answers/score only
        let place   = SharedStore.readPlacesData()?.place(for: diff)     // place remains separate
        let ai      = SharedStore.readAIStats()
        let tooltip = SharedStore.readAITooltip()
        
        return WordZapEntry(
            date: date,
            difficulty: diff,
            answers: stats?.answers,
            score:   stats?.score,
            place:   place,
            aiName:  ai?.name ?? "Chad GPT",
            aiImageName: ai?.imageName ?? "easyAI",
            aiTooltip: tooltip ?? "Destroyer of words"
        )
    }
    
    private func difficulty(for date: Date) -> Difficulty {
        let slot = Int(date.timeIntervalSince1970 / cycleSeconds) % order.count
        return order[slot]
    }
    
    private func alignedBoundary(after date: Date, interval: TimeInterval, includeNow: Bool) -> Date {
        let t = date.timeIntervalSince1970
        let remainder = t.truncatingRemainder(dividingBy: interval)
        if includeNow && remainder == 0 { return date }
        return Date(timeIntervalSince1970: t - remainder + interval)
    }
}

// MARK: - Widget
struct WordZapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WordZapWidget", provider: WordZapProvider()) { entry in
            WordZapWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("WordZap")
        .description("Daily stats and AI at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - View
struct WordZapWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WordZapEntry
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 173/255, green: 233/255, blue: 181/255), // Lime Green
                    Color(red: 255/255, green: 249/255, blue: 177/255)  // Light Yellow
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            switch family {
            case .systemSmall:  smallLayout
            case .systemMedium: mediumLayout
            case .systemLarge:  largeLayout
            default:            mediumLayout
            }
        }
    }
    
    // MARK: Unified chip
    @ViewBuilder
    private func chip(_ text: String, icon: String? = nil, expand: Bool = true, color: Color = .primary) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.primary.opacity(0.9))
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: expand ? .infinity : nil, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.16), lineWidth: 1)
        )
    }
    
    // MARK: Small — centered date chip
    private var smallLayout: some View {
        let shortDate = entry.date.formatted(.dateTime.day().month(.abbreviated))
        return VStack(spacing: 8) {
            Spacer(minLength: 2)
            AppTitle()
                .font(.headline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            HStack {
                Spacer()
                chip(shortDate, icon: "calendar", expand: false)
                Spacer()
            }
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 6)
    }
    
    // MARK: Medium — compact chips
    private var mediumLayout: some View {
        let shortDate = entry.date.formatted(.dateTime.day().month(.abbreviated))
        let d         = entry.difficulty
        let answers   = entry.answers.map(String.init) ?? "—"
        let score     = entry.score.map { $0.formatted(.number.grouping(.automatic)) } ?? "—"
        let place     = entry.place.map { "#\($0)" } ?? "—"
        let diff      = d.rawValue.capitalized
        
        return VStack(spacing: 4) {
            AppTitle()
                .font(.headline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    chip(shortDate, icon: "calendar")
                    chip(diff,      icon: "flag.checkered", color: d.color)
                    chip(answers,   icon: "text.cursor")
                }
                GridRow {
                    chip(score,     icon: "sum")
                    chip(place,     icon: "trophy")
                    Color.clear
                }
            }
        }
        .padding(12)
    }
    
    // MARK: Large
    private var largeLayout: some View {
        let shortDate = entry.date.formatted(.dateTime.day().month(.abbreviated))
        let d         = entry.difficulty

        return VStack(spacing: 12) {
            AppTitle()
                .font(.title3).bold()
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .top, spacing: 12) {
                Link(destination: URL(string: "wordzap://play?difficulty=\(d.rawValue)")!) {
                    VStack(alignment: .leading, spacing: 10) {
                        chip("Today: \(shortDate)",                                          icon: "calendar")
                        chip("Difficulty: \(d.rawValue.capitalized)",                        icon: "flag.checkered", color: d.color)
                        chip("Place: \(entry.place.map { "#\($0)" } ?? "—")",                icon: "trophy")
                        chip("Score: \(entry.score != nil ? "\(entry.score!)" : "—")",       icon: "sum")
                        chip("Answers: \(entry.answers != nil ? "\(entry.answers!)" : "-")", icon: "text.cursor")
                    }
                    .padding(14)
                    .softGlass()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Link(destination: URL(string:  "wordzap://ai")!) {
                    AICardWithTooltip(
                        name: entry.aiName ?? "AI Opponent",
                        imageName: entry.aiImageName,
                        tooltip: entry.aiTooltip
                    )
                    .frame(width: 120)
                    .softGlass()
                }
            }
        }
        .padding(16)
    }
}

// MARK: - AI Card
private struct AICardWithTooltip: View {
    let name: String
    let imageName: String?
    let tooltip: String?
    
    var body: some View {
        VStack(spacing: 2) {
            Spacer()
            VStack(spacing: 2) {
                if let t = tooltip, !t.isEmpty { TooltipBubble(text: t).transition(.opacity) }
                Group {
                    if let img = imageName, UIImage(named: img) != nil {
                        Image(img).resizable().scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.15))
                            .overlay(
                                Image(systemName: "brain.head.profile")
                                    .resizable().scaledToFit()
                                    .frame(width: 36, height: 36)
                                    .foregroundColor(.primary.opacity(0.6))
                            )
                    }
                }
                .frame(height: 86)
                .shadow(radius: 3, y: 2)
            }

            
            Text(name)
                .font(.callout.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 8)
                .padding(.bottom, 12)
            Spacer()
        }
        .padding(14)
    }
}

private struct TooltipBubble: View {
    let text: String
    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.14)))
                .overlay(Capsule().stroke(Color.primary.opacity(0.16), lineWidth: 1))
                .frame(maxWidth: 140)
            Triangle()
                .fill(Color.primary.opacity(0.14))
                .frame(width: 10, height: 10)
                .overlay(Triangle().stroke(Color.primary.opacity(0.16), lineWidth: 1))
        }
        .shadow(radius: 1.5, y: 1)
    }
    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
            return p
        }
    }
}

// MARK: - Helpers / Modifiers
private extension View {
    @ViewBuilder
    func `if`<V: View>(_ condition: Bool, transform: (Self) -> V) -> some View {
        if condition { transform(self) } else { self }
    }
}

private struct SoftGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}
private extension View { func softGlass() -> some View { modifier(SoftGlass()) } }
