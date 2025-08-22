//
//  CharView.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI
import Combine

struct CharView: View {
    @EnvironmentObject private var local: LanguageSetting
    var isAI = false
    @Binding var text: String
    let usePlaceHolder: Bool
    var didType: ((String) -> ())? = nil
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    var body: some View {
        TextField(usePlaceHolder ? "?" : "",
                  text: $text)
        .accentColor(.black.opacity(0.2))
        .frame(maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .onReceive(Just(text)) { _ in
            text.limitToAllowedCharacters(language: language)
            didType?(text)
        }
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
        
        // Unicode values for Hebrew letters Aleph (א) to Tav (ת)
        let hebrewRange = 0x05D0...0x05EA
        
        // Add each Unicode scalar to the CharacterSet
        for unicodeValue in hebrewRange {
            if let scalar = UnicodeScalar(unicodeValue) {
                characterSet.insert(scalar)
            }
        }
        
        return characterSet
    }()
    
    static let englishLetters: CharacterSet = {
        var characterSet = CharacterSet()
        
        // Add uppercase English letters (A-Z)
        let upperCaseRange = 0x41...0x5A  // Unicode for 'A' to 'Z'
        for unicodeValue in upperCaseRange {
            if let scalar = UnicodeScalar(unicodeValue) {
                characterSet.insert(scalar)
            }
        }
        
        // Add lowercase English letters (a-z)
        let lowerCaseRange = 0x61...0x7A  // Unicode for 'a' to 'z'
        for unicodeValue in lowerCaseRange {
            if let scalar = UnicodeScalar(unicodeValue) {
                characterSet.insert(scalar)
            }
        }
        
        return characterSet
    }()
}

public extension UITextField
{
    override var textInputMode: UITextInputMode?
    {
        let locale = Locale.current
        
        return
            UITextInputMode.activeInputModes.first(where: { $0.primaryLanguage == locale.identifier })
            ??
            super.textInputMode
    }
}

enum PlaceHolderLocation {
    case under, onTop
}

struct PlaceholderModifier<Placeholder: View>: ViewModifier {
    let isEmpty: Bool
    let location: PlaceHolderLocation
    let placeholder: () -> Placeholder
    
    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            switch location {
            case .under:
                if isEmpty {
                    placeholder()
                }
                content
            case .onTop:
                content
                if isEmpty {
                    placeholder()
                }
            }
        }
    }
}

extension View {
    func placeHolder<Placeholder: View>(
        when isEmpty: Bool,
        location: PlaceHolderLocation = .onTop,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) -> some View {
        modifier(PlaceholderModifier(isEmpty: isEmpty,
                                     location: location,
                                     placeholder: placeholder))
    }
}
