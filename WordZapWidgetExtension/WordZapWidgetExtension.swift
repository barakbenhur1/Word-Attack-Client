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
            aiName:  ai?.name,
            aiImageName: ai?.imageName,
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - View
struct WordZapWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WordZapEntry
    
    private var hasStats: Bool {
        entry.answers != nil && entry.score != nil && entry.place != nil
    }
    
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
            case .systemSmall:      smallLayout
            case .systemMedium:     mediumLayout
            case .systemLarge:      largeLayout
            case .systemExtraLarge: extraLargeLayout
            default:                mediumLayout
            }
        }
    }

    // Generic placeholder block (no chip)
    @ViewBuilder
    private func statsPlaceholderBlock() -> some View {
        // slightly larger text for large/XL
        let isLarge = (family == .systemLarge || family == .systemExtraLarge)
        let baseFont: Font = isLarge ? .footnote : .caption

        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hourglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("No stats yet").fontWeight(.semibold)
                if isLarge {
                    Text("Play a round\nto see Place,\nScore & Answers")
                        .font(family == .systemLarge ? .subheadline : .headline)
                        .minimumScaleFactor(0.7)
                }
            }
            .multilineTextAlignment(.leading)
        }
        .font(baseFont)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.06))     // faint fill
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])) // dashed = placeholdery
                .foregroundStyle(.secondary.opacity(0.35))
        )
    }
    
    // MARK: Unified chip
    @ViewBuilder
    private func chip(
        _ text: String,
        icon: String? = nil,
        expand: Bool = true,
        color: Color = .primary
    ) -> some View {
        // slightly smaller than before
        let isExtraLarge = family == .systemExtraLarge
        let chipFont: Font = isExtraLarge ? .footnote.weight(.semibold) : .caption2.weight(.semibold)
        
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.primary.opacity(0.9))
            }
            Text(text.localized)
                .font(chipFont)
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(1.0)   // keep all rows same size
                .allowsTightening(false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, isExtraLarge ? 7 : 6)
        .frame(maxWidth: expand ? .infinity : nil, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.16), lineWidth: 1))
    }
    
    // MARK: Small
    private var smallLayout: some View {
        let shortDate = entry.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale.current))
        return VStack(spacing: 8) {
            Spacer(minLength: 2)
            AppTitle(isWidget: true)
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
    
    // MARK: Medium
    private var mediumLayout: some View {
        let shortDate = entry.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale.current))
        let d         = entry.difficulty
        let answers   = entry.answers.map(String.init) ?? "—"
        let score     = entry.score.map { $0.formatted(.number.grouping(.automatic)) } ?? "—"
        let place     = entry.place.map { "#\($0)" } ?? "—"
        let diff      = d.rawValue.localized.capitalized
        
        return VStack(spacing: 4) {
            AppTitle(isWidget: true)
                .font(.headline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            tapTarget("wordzap://play?difficulty=\(d.rawValue)") {
                Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        chip(diff,              icon: "flag.checkered", color: d.color)
                        chip(shortDate,         icon: "calendar")
                        Color.clear
                    }
                    if hasStats {
                        GridRow {
                            chip(place,          icon: "trophy")
                            chip(score,          icon: "sum")
                            chip(answers,        icon: "text.cursor")
                        }
                    } else {
                        GridRow {
                            chip("No stats yet", icon: "hourglass")
                                .gridCellColumns(2)
                        }
                    }
                }
            }
        }
        .padding(12)
    }
    
    // MARK: Large
    private var largeLayout: some View {
        let shortDate = entry.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale.current))
        let d         = entry.difficulty
        
        return VStack(spacing: 12) {
            AppTitle(isWidget: true)
                .font(.title3).bold()
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            GeometryReader { proxy in
                Grid(horizontalSpacing: 4, verticalSpacing: 0) {
                    GridRow {
                        tapTarget("wordzap://play?difficulty=\(d.rawValue)") {
                            VStack(alignment: .leading, spacing: 12) {
                                chip("\("Diff".localized): \(d.rawValue.localized.capitalized)", icon: "flag.checkered", color: d.color)
                                chip("\("Today".localized): \(shortDate)", icon: "calendar")
                                
                                if hasStats {
                                    chip("\("Place".localized): \(entry.place.map { "#\($0)" } ?? "—")", icon: "trophy")
                                    chip("\("Score".localized): \(entry.score != nil ? "\(entry.score!)" : "—")", icon: "sum")
                                    chip("\("Answers".localized): \(entry.answers != nil ? "\(entry.answers!)" : "—")", icon: "text.cursor")
                                } else {
                                    statsPlaceholderBlock()
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: proxy.size.height)
                            .softGlass()
                        }
                        .gridCellAnchor(.center)
                        
                        tapTarget("wordzap://ai") {
                            AICardWithTooltip(
                                name: entry.aiName ?? "AI Opponent",
                                imageName: entry.aiImageName,
                                tooltip: entry.aiName == nil ? "start your ai journey" : entry.aiTooltip,
                                isExtraLarge: false
                            )
                            .frame(maxWidth: 114)
                            .frame(height: proxy.size.height)
                            .softGlass()
                        }
                        .gridCellAnchor(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }
    
    // MARK: Extra Large
    private var extraLargeLayout: some View {
        // Match Large date style for consistency
        let shortDate = entry.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale.current))
        let d         = entry.difficulty

        return VStack(spacing: 16) {
            AppTitle(isWidget: true)
                .font(.title2).bold()
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)

            Grid(horizontalSpacing: 22, verticalSpacing: 0) {
                GridRow {
                    VStack(alignment: .center, spacing: 0) {
                        Spacer()
                        tapTarget("wordzap://settings") {
                            Image(systemName: "gearshape.fill")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                        }
                        Spacer()
                        tapTarget("wordzap://scoreboard") {
                            Image(systemName: "trophy.fill")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                        }
                        Spacer()
                    }
                    .padding(5)
                    .softGlass()

                    // Middle column: Play card (same content structure as Large)
                    tapTarget("wordzap://play?difficulty=\(d.rawValue)") {
                        VStack(alignment: .leading, spacing: 12) {
                            chip("\("Diff".localized): \(d.rawValue.localized.capitalized)", icon: "flag.checkered", color: d.color)
                            chip("\("Today".localized): \(shortDate)", icon: "calendar")

                            if hasStats {
                                chip("\("Place".localized): \(entry.place.map { "#\($0)" } ?? "—")", icon: "trophy")
                                chip("\("Score".localized): \(entry.score.map(String.init) ?? "—")", icon: "sum")
                                chip("\("Answers".localized): \(entry.answers.map(String.init) ?? "—")", icon: "text.cursor")
                            } else {
                                statsPlaceholderBlock()
                            }
                        }
                        .padding(16)
                        .softGlass()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Right column: AI card
                    tapTarget("wordzap://ai") {
                        AICardWithTooltip(
                            name: entry.aiName ?? "AI Opponent",
                            imageName: entry.aiImageName,
                            tooltip: entry.aiName == nil ? "start your ai journey" : entry.aiTooltip,
                            isExtraLarge: true
                        )
                        .frame(width: 300)
                        .softGlass()
                    }
                }
            }
        }
        .padding(20)
        .environment(\.layoutDirection, Locale.current.identifier.components(separatedBy: "_").first == "he" ? .rightToLeft : .leftToRight)
    }
}

// MARK: - AI Card
private struct AICardWithTooltip: View {
    let name: String
    let imageName: String?
    let tooltip: String?
    let isExtraLarge: Bool
    
    var body: some View {
        let imageH: CGFloat = isExtraLarge ? 126 : 96
        let bubbleMaxW: CGFloat = isExtraLarge ? 180 : 140
        let bubbleLift: CGFloat =  isExtraLarge ? 4  : 6  // how much the bubble sits above the image
        let imageTopPadding: CGFloat = isExtraLarge ? 50 : 25
        let textTopPadding: CGFloat = isExtraLarge ? 2 : 8
        let textBottomPadding: CGFloat = isExtraLarge ? 2 : 4
        let brainSize: CGFloat = isExtraLarge ? 94 : 78
        
        VStack(spacing: 2) {
            // Fixed-height image area
            Group {
                if let img = imageName, UIImage(named: img) != nil {
                    Image(img)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "brain.head.profile")
                        .resizable()
                        .scaledToFit()
                        .frame(width: brainSize, height: brainSize)
                        .foregroundColor(.primary.opacity(0.6))
                }
            }
            .frame(height: imageH)  // <- constant image height (keeps overall size stable)
            .padding(.top, imageTopPadding)
            .overlay(alignment: .bottom) {
                if let t = tooltip, !t.isEmpty {
                    TooltipBubble(text: t, isExtraLarge: isExtraLarge)
                        .frame(maxWidth: bubbleMaxW)
                        .fixedSize(horizontal: false, vertical: true)  // wrap internally
                        .offset(y: -(imageH - bubbleLift))             // sit above the image
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .shadow(radius: 3, y: 2)
            
            Text(name.localized)
                .font(.callout.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, textTopPadding)
                .padding(.bottom, textBottomPadding)
        }
        .padding(.top, 8)
        .padding(14)
    }
}

private struct TooltipBubble: View {
    let text: String
    let isExtraLarge: Bool
    
    var body: some View {
        let font: Font = isExtraLarge ? .footnote.weight(.semibold) : .caption2.weight(.semibold)
        let maxWidth: CGFloat = isExtraLarge ? 200 : 140
        VStack(spacing: 0) {
            Text(text.localized)
                .font(font)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.14)))
                .overlay(Capsule().stroke(Color.primary.opacity(0.16), lineWidth: 1))
                .frame(maxWidth: maxWidth)
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

@ViewBuilder
private func tapTarget<Content: View>(
    _ urlString: String,
    @ViewBuilder _ content: () -> Content
) -> some View {
    if #available(iOS 17.0, *) {
        Link(destination: URL(string: urlString)!) {
            content()
                .contentShape(Rectangle())     // full-card hit area
        }
        .buttonStyle(.plain)                    // keep your own styles
        .labelStyle(.automatic)
    } else {
        content()
            .contentShape(Rectangle())
            .widgetURL(URL(string: urlString))  // fallback for iOS < 17 (single target only)
    }
}
