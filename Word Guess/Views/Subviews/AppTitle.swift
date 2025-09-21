//
//  AppTitle.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 21/10/2024.
//

import SwiftUI

struct AppTitle: View {
    private let title = "Word Guess".localized
    var size: CGFloat = 40
    var isWidget: Bool = false
    
    let wordZapColors: [CharColor] = [
        .exactMatch,
        .partialMatch,
        .noMatch,
    ]
    
    var body: some View {
        let start = String(title[0..<4])
        let end = String(title[4..<title.count])
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                let array = start.toArray()
                ForEach(.constant(array), id: \.self) { c in
                    if let i = array.firstIndex(of: c.wrappedValue) {
                        ZStack {
                            wordZapColors[i % wordZapColors.count].color
                            Text(c.wrappedValue)
                                .font(.largeTitle)
                                .accessibilityHidden(true)
                        }
                        .frame(width: size)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.black,
                                        lineWidth: 1)
                        )
                    }
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            
            HStack(spacing: 0) {
                let array = end.toArray()
                ForEach(.constant(array), id: \.self) { c in
                    if let i = array.firstIndex(of: c.wrappedValue) {
                        ZStack {
                            wordZapColors[i % wordZapColors.count].color
                            Text(c.wrappedValue)
                                .font(.largeTitle)
                                .accessibilityHidden(true)
                        }
                        .frame(width: size)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.black,
                                        lineWidth: 1)
                        )
                    }
                }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .fixedSize()
        .scaleEffect(.init(width: !isWidget && UIDevice.isPad ? 1.6 : 1, height: !isWidget && UIDevice.isPad ? 1.6 : 1))
        // Provide a single concise accessibility label
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Word Guess".localized))
        .accessibilityAddTraits(.isHeader)
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
    
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
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
    
    func toArray() -> [String] {
        return map { String($0) }
    }
    
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
        return components(separatedBy: " ").map { !$0.isEmpty ? $0[0] : "" }.joined()
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
        return map { String.suffixs[String($0)] ?? String($0) }.joined()
    }
    
    func correctSuffix() -> String {
        return map { $0 == last ? String.suffixs[String($0)] ?? String($0) : String($0) }.joined()
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
    static func == (lhs: CharColor, rhs: CharColor) -> Bool { return lhs.id == rhs.id}
    static func < (lhs: CharColor, rhs: CharColor) -> Bool { return lhs.id > rhs.id }
    
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
        case let i where i.id == CharColor.partialMatch.id : return "🟨"
        case let i where i.id == CharColor.exactMatch.id : return "🟩"
        default: return "⬜"
        }
    }
}

extension UIDevice {
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
}

