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
    @Binding var text: String
    let usePlaceHolder: Bool
    var didType: ((String) -> ())? = nil
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    var body: some View {
        TextField(usePlaceHolder ? "?" : "",
                  text: $text)
        .accentColor(.yellow.opacity(0.08))
        .frame(maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .onKeyPress(.delete) {
            didType?("")
            return .handled
        }
        .onReceive(Just(text)) { _ in
            text.limitToAllowedCharacters(language: language)
            didType?(text)
        }
    }
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
