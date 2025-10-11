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
    private let cycleSeconds: TimeInterval = 60 * 4       // 4 minutes on device
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
                .containerBackground(.fill.tertiary, for: .widget) // system-safe bg
        }
        .configurationDisplayName("WordZap")
        .description("Daily stats and AI at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - View
struct WordZapWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: WordZapEntry
    
    private var hasStats: Bool {
        entry.answers != nil && entry.score != nil && entry.place != nil
    }
    
    var body: some View {
        ZStack {
            backgroundView
            switch family {
            case .systemSmall:      smallLayout
            case .systemMedium:     mediumLayout
            case .systemLarge:      largeLayout
            case .systemExtraLarge: extraLargeLayout
            default:                mediumLayout
            }
        }
    }
    
    // Dynamic background that respects Dark/Light
    private var backgroundView: some View {
        // Light: original lime → soft yellow
        let light = [
            Color(red: 173/255, green: 233/255, blue: 181/255),
            Color(red: 255/255, green: 249/255, blue: 177/255)
        ]
        // Dark: deep teal → warm olive (low brightness)
        let dark = [
            Color(hue: 0.47, saturation: 0.28, brightness: 0.18),
            Color(hue: 0.14, saturation: 0.32, brightness: 0.12)
        ]
        return LinearGradient(colors: colorScheme == .dark ? dark : light,
                              startPoint: .top, endPoint: .bottom)
    }
    
    // Generic placeholder block (no chip)
    @ViewBuilder
    private func statsPlaceholderBlock() -> some View {
        let isLarge = (family == .systemLarge || family == .systemExtraLarge)
        let baseFont: Font = isLarge ? .footnote : .caption
        
        // Dynamic fills/strokes for dark/light
        let fill   = colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
        let stroke = colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.35)
        
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hourglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("No stats yet")
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                if isLarge {
                    Text("Play a round\nto see Place,\nScore & Answers")
                        .font(family == .systemLarge ? .subheadline : .headline)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.leading)
        }
        .font(baseFont)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical ,10)
        .padding(.horizontal ,5)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(stroke)
        )
    }
    
    // MARK: Unified chip
    @ViewBuilder
    private func chip(
        _ text: String,
        icon: String? = nil,
        expand: Bool = true,
        color: Color = .primary // <- default to dynamic text
    ) -> some View {
        let isExtraLarge = family == .systemExtraLarge
        let chipFont: Font = isExtraLarge ? .footnote.weight(.semibold) : .caption2.weight(.semibold)
        
        // Dynamic glass surface
        let chipFill   = colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
        let chipStroke = colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
        
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
            }
            Text(text.localized)
                .font(chipFont)
                .monospacedDigit()
                .foregroundStyle(color) // dynamic or custom (e.g., difficulty color)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(1.0)   // keep all rows same size
                .allowsTightening(false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, isExtraLarge ? 7 : 6)
        .frame(maxWidth: expand ? .infinity : nil, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(chipFill))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(chipStroke, lineWidth: 1))
    }
    
    // MARK: Small
    private var smallLayout: some View {
        let shortDate = entry.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale.current))
        return VStack(spacing: 8) {
            AppTitle(isWidget: true)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            chip(shortDate, icon: "calendar", expand: true, color: .primary)
                .padding(4)
                .softGlass()
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
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            tapTarget("wordzap://play?difficulty=\(d.rawValue)") {
                Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                    HStack {
                        chip(diff,              icon: "flag.checkered", expand: true,    color: d.color)
                        chip(shortDate,         icon: "calendar",       expand: true,    color: .primary)
                    }
                    if hasStats {
                        GridRow {
                            chip(place,          icon: "trophy",                         color: .primary)
                            chip(score,          icon: "sum",                            color: .primary)
                            chip(answers,        icon: "text.cursor",                    color: .primary)
                        }
                    } else {
                        GridRow {
                            chip("No stats yet", icon: "hourglass",     expand: true,    color: .secondary)
                                .gridCellColumns(3)
                        }
                    }
                }
                .padding(4)
                .softGlass()
            }
        }
        .padding(12)
    }
    
    // MARK: Large
    private var largeLayout: some View {
        let shortDate = entry.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale.current))
        let d         = entry.difficulty
        
        return VStack(spacing: 6) {
            AppTitle(isWidget: true)
                .font(.title3).bold()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            GeometryReader { proxy in
                Grid(horizontalSpacing: 4, verticalSpacing: 0) {
                    GridRow {
                        tapTarget("wordzap://play?difficulty=\(d.rawValue)") {
                            VStack(alignment: .leading, spacing: 12) {
                                chip("\("Diff".localized): \(d.rawValue.localized.capitalized)", icon: "flag.checkered", color: d.color)
                                chip("\("Today".localized): \(shortDate)", icon: "calendar", color: .primary)
                                
                                if hasStats {
                                    chip("\("Place".localized): \(entry.place.map { "#\($0)" } ?? "—")", icon: "trophy", color: .primary)
                                    chip("\("Score".localized): \(entry.score != nil ? "\(entry.score!)" : "—")", icon: "sum", color: .primary)
                                    chip("\("Answers".localized): \(entry.answers != nil ? "\(entry.answers!)" : "—")", icon: "text.cursor", color: .primary)
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
                            .frame(maxWidth: 134)
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
        let shortDate = entry.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale.current))
        let d         = entry.difficulty
        
        return VStack(spacing: 16) {
            AppTitle(isWidget: true)
                .font(.title2).bold()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            Grid(horizontalSpacing: 10, verticalSpacing: 0) {
                GridRow {
                    VStack(alignment: .center, spacing: 0) {
                        Spacer()
                        tapTarget("wordzap://settings") {
                            Image(systemName: "gearshape.fill")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        tapTarget("wordzap://scoreboard") {
                            Image(systemName: "trophy.fill")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                    }
                    .padding(5)
                    .softGlass()
                    
                    // Middle column: Play card (same content structure as Large)
                    tapTarget("wordzap://play?difficulty=\(d.rawValue)") {
                        VStack(alignment: .leading, spacing: 12) {
                            chip("\("Diff".localized): \(d.rawValue.localized.capitalized)", icon: "flag.checkered", color: d.color)
                            chip("\("Today".localized): \(shortDate)", icon: "calendar", color: .primary)
                            
                            if hasStats {
                                chip("\("Place".localized): \(entry.place.map { "#\($0)" } ?? "—")", icon: "trophy", color: .primary)
                                chip("\("Score".localized): \(entry.score.map(String.init) ?? "—")", icon: "sum", color: .primary)
                                chip("\("Answers".localized): \(entry.answers.map(String.init) ?? "—")", icon: "text.cursor", color: .primary)
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
        let imageH: CGFloat = isExtraLarge ? 124 : 108
        let bubbleMaxW: CGFloat = isExtraLarge ? 180 : 140
        let bubbleLift: CGFloat =  isExtraLarge ? 0  : 0
        let imageTopPadding: CGFloat = isExtraLarge ? 0 : 0
        let textTopPadding: CGFloat = isExtraLarge ? 0 : 0
        let textBottomPadding: CGFloat = isExtraLarge ? 2 : 4
        let brainSize: CGFloat = isExtraLarge ? 124 : 108
        
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
                        .foregroundStyle(.primary.opacity(0.6))
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
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, textTopPadding)
                .padding(.bottom, textBottomPadding)
        }
        .padding(14)
        .padding(.top, 42.5)
    }
}

private struct TooltipBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let isExtraLarge: Bool
    
    var body: some View {
        let font: Font = isExtraLarge ? .footnote.weight(.semibold) : .caption2.weight(.semibold)
        let maxWidth: CGFloat = isExtraLarge ? 200 : 140
        
        let bubbleFill   = colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
        let bubbleStroke = colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
        
        VStack(spacing: 0) {
            Text(text.localized)
                .font(font)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(bubbleFill))
                .overlay(Capsule().stroke(bubbleStroke, lineWidth: 1))
                .frame(maxWidth: maxWidth)
            Triangle()
                .fill(bubbleFill)
                .frame(width: 10, height: 10)
                .overlay(Triangle().stroke(bubbleStroke, lineWidth: 1))
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
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        let fill   = colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        let stroke = colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
        
        content
            .background(RoundedRectangle(cornerRadius: 14).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(stroke, lineWidth: 1))
    }
}
private extension View { func softGlass() -> some View { modifier(SoftGlass()) } }

// MARK: - Link helper
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
