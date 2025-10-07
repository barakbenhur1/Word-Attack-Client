//
//  AppTitle.swift
//  WordZap
//
//  Created by Barak Ben Hur on 21/10/2024.
//

import SwiftUI

struct AppTitle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private let title = "Word Guess".localized
    private let size: CGFloat
    private let isWidget: Bool
    private let animated: Bool
    
    private let wordZapColors: [CharColor] = [
        .exactMatch,
        .partialMatch,
        .noMatch,
    ]
    
    @State private var wordZapColorsForAnimation: [[CharColor]] = []
    @State private var comp: [String]
    
    init(size: CGFloat = 40, animated: Bool = false, isWidget: Bool = false) {
        self.size = size
        self.isWidget = isWidget
        self.animated = animated
        _comp = State(initialValue: title.split(whereSeparator: { $0.isWhitespace }).map(String.init))
    }
    
    var body: some View {
        LazyVStack(alignment: .center, spacing: 0) {
            ForEach(comp.indices, id: \.self) { i in
                word(i: i, item: comp[i])
                    .frame(maxWidth: .infinity, alignment: .center)
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .environment(\.layoutDirection, .leftToRight)
        .task {
            if animated {
                wordZapColorsForAnimation = comp.map { Array(repeating: .noGuess, count: $0.count) }
                
                for i in 0..<wordZapColorsForAnimation.count {
                    if !reduceMotion {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                    for j in 0..<wordZapColorsForAnimation[i].count {
                        if !reduceMotion {
                            try? await Task.sleep(nanoseconds: 150_000_000)
                        }
                        wordZapColorsForAnimation[i][j] = wordZapColors[j % wordZapColors.count]
                    }
                }
            }
        }
    }

    @ViewBuilder private func word(i: Int, item: String) -> some View {
        LazyHStack(spacing: 0) {
            let chars = item.toArray()
            ForEach(Array(chars.enumerated()), id: \.offset) { j, ch in
                ZStack {
                    if animated && !wordZapColorsForAnimation.isEmpty {
                        let r = i % wordZapColorsForAnimation.count
                        let c = j % wordZapColorsForAnimation[r].count
                        wordZapColorsForAnimation[r][c].color
                    } else {
                        let idx = j % wordZapColors.count
                        wordZapColors[idx].color
                    }
                    Text(ch)
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                }
                .frame(width: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center) // FIX: make each HStack occupy a full line
    }
}

extension String {
    subscript(offset: Int) -> String { String(self[index(startIndex, offsetBy: offset)]) }
    subscript(range: Range<Int>) -> SubSequence {
        let startIndex = index(self.startIndex, offsetBy: range.lowerBound)
        return self[startIndex..<index(startIndex, offsetBy: range.count)]
    }
    subscript(range: ClosedRange<Int>) -> SubSequence {
        let startIndex = index(self.startIndex, offsetBy: range.lowerBound)
        return self[startIndex..<index(startIndex, offsetBy: range.count)]
    }
    subscript(range: PartialRangeFrom<Int>) -> SubSequence { self[index(startIndex, offsetBy: range.lowerBound)...] }
    subscript(range: PartialRangeThrough<Int>) -> SubSequence { self[...index(startIndex, offsetBy: range.upperBound)] }
    subscript(range: PartialRangeUpTo<Int>) -> SubSequence { self[..<index(startIndex, offsetBy: range.upperBound)] }
    
    var localized: String { NSLocalizedString(self, comment: "") }
}

extension String {
    static private let suffixs = [
        "צ" : "ץ",
        "מ" : "ם",
        "נ" : "ן",
        "כ" : "ך",
        "פ" : "ף"
    ]
    
    func toKey() -> String {
        return Bundle.main.infoDictionary?[self] as? String ?? self
    }
    
    func asClassName() -> String {
        return replacingOccurrences(of: "Word_Guess.", with: "")
    }
    
    func toArray() -> [String] { map { String($0) } }
    
    mutating func limitText(_ upper: Int) {
        guard count > upper else { return }
        self = String(prefix(upper))
    }
    
    mutating func limitToAllowedCharacters(language: String?) {
        guard let language else { return }
        let characterSet: CharacterSet = language == "he" ? .hebrewLetters : .englishLetters
        self = filter {
            guard let scalar = $0.unicodeScalars.first else { return false }
            return characterSet.contains(scalar)
        }
    }
    
    func initals() -> String {
        components(separatedBy: " ").map { !$0.isEmpty ? $0[0] : "" }.joined()
    }
    
    func returnChar(isFinal: Bool) -> String {
        if isFinal { return String.suffixs[self] ?? self }
        else { return String.suffixs.first(where: { _, value in value == self})?.key ?? self }
    }
    
    func isEquel(_ key: String) -> Bool {
        guard let selfValue = String.suffixs[self], let keyValue = String.suffixs[key], self == keyValue || key == selfValue else { return self == key }
        return true
    }
    
    func toSuffixChars() -> String {
        map { String.suffixs[String($0)] ?? String($0) }.joined()
    }
    
    func correctSuffix() -> String {
        map { $0 == last ? String.suffixs[String($0)] ?? String($0) : String($0) }.joined()
    }
}

extension CharacterSet {
    static let hebrewLetters: CharacterSet = {
        var characterSet = CharacterSet()
        let hebrewRange = 0x05D0...0x05EA
        for unicodeValue in hebrewRange {
            if let scalar = UnicodeScalar(unicodeValue) {
                characterSet.insert(scalar)
            }
        }
        return characterSet
    }()
    
    static let englishLetters: CharacterSet = {
        var characterSet = CharacterSet()
        let upperCaseRange = 0x41...0x5A
        for unicodeValue in upperCaseRange {
            if let scalar = UnicodeScalar(unicodeValue) {
                characterSet.insert(scalar)
            }
        }
        let lowerCaseRange = 0x61...0x7A
        for unicodeValue in lowerCaseRange {
            if let scalar = UnicodeScalar(unicodeValue) {
                characterSet.insert(scalar)
            }
        }
        return characterSet
    }()
}

struct CharColor: Comparable {
    static func == (lhs: CharColor, rhs: CharColor) -> Bool { lhs.id == rhs.id }
    static func < (lhs: CharColor, rhs: CharColor) -> Bool { lhs.id > rhs.id }
    
    let id: Int
    let color: LinearGradient
    
    static let noGuess: CharColor = .init(id: 0,
                                          color: .linearGradient(colors: [.white.opacity(0.6), .white],
                                                                 startPoint: .leading,
                                                                 endPoint: .trailing))
    static let noMatch: CharColor = .init(id: 1,
                                          color: .linearGradient(colors: [Color(red: 99/255, green: 110/255, blue: 114/255).opacity(0.6),
                                                                          Color(red: 99/255, green: 110/255, blue: 114/255)],
                                                                 startPoint: .leading,
                                                                 endPoint: .trailing))
    static let partialMatch: CharColor = .init(id: 2,
                                               color: .linearGradient(colors: [Color(red: 255/255, green: 193/255, blue: 7/255).opacity(0.6),
                                                                               Color(red: 255/255, green: 193/255, blue: 7/255)],
                                                                      startPoint: .leading,
                                                                      endPoint: .trailing))
    static let exactMatch: CharColor = .init(id: 3,
                                             color: .linearGradient(colors: [Color(red: 46/255, green: 204/255, blue: 113/255).opacity(0.6),
                                                                             Color(red: 46/255, green: 204/255, blue: 113/255)],
                                                                    startPoint: .leading,
                                                                    endPoint: .trailing))
    
    var baseColor: Color {
        switch self {
        case let i where i == .exactMatch: return .green
        case let i where i == .partialMatch: return .yellow
        case let i where i == .noMatch: return .gray
        case let i where i == .noGuess: return .white
        default: return .clear
        }
    }
    
    func getColor() -> String {
        switch self {
        case let i where i.id == CharColor.partialMatch.id: return "🟨"
        case let i where i.id == CharColor.exactMatch.id :  return "🟩"
        default:                                            return "⬜"
        }
    }
}

extension UIDevice {
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
}
