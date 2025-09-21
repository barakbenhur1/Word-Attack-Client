//
//  WordView.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI

// MARK: - Micro Styles

private struct HairlineStroke: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct InnerShadow: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(.black.opacity(0.12), lineWidth: 1)
                .blur(radius: 1.5)
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(LinearGradient(stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .clear, location: 0.55),
                            .init(color: .black.opacity(0.6), location: 1.0),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
        )
    }
}

private struct SoftGloss: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.20), .white.opacity(0.06), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.overlay)
                .allowsHitTesting(false)
        )
    }
}

private struct FocusGlow: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? Color.white.opacity(0.70) : .clear, lineWidth: 1.0)
                    .shadow(color: isFocused ? .white.opacity(0.55) : .clear, radius: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? Color.white.opacity(0.10) : .clear, lineWidth: 6)
                    .blur(radius: 6)
            )
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

private extension View {
    func premiumTile(cornerRadius: CGFloat = 4) -> some View {
        self
            .modifier(HairlineStroke(cornerRadius: cornerRadius))
            .modifier(InnerShadow(cornerRadius: cornerRadius))
            .modifier(SoftGloss(cornerRadius: cornerRadius))
    }
    func focusGlow(_ on: Bool, cornerRadius: CGFloat = 4) -> some View {
        self.modifier(FocusGlow(isFocused: on, cornerRadius: cornerRadius))
    }
}

// MARK: - Existing types

enum FieldFocus: Int {
    case one
    case two
    case trhee
    case four
    case five
    case six
}

struct WordView<VM: ViewModel>: View {
    @EnvironmentObject private var local: LanguageSetting
    
    private let length: Int
    private let placeHolderData: [BestGuess]?
    private let done: () -> ()
    
    private var placeHolderForCell: (_ index: Int) -> [Guess] { { i in
        placeHolderData?.first { $0.index == i }?.colordLetters ?? []
    } }
    
    private var language: String? { local.locale.identifier.components(separatedBy: "_").first }
    
    @Binding private var gainFocus: Bool
    @Binding private var word: [String]
    @State private var wordBakup: [String]
    @Binding private var current: Int
    @Binding private var colors: [CharColor]
    @FocusState private var fieldFocus: FieldFocus?
    
    private let allowed: (set: Set<Character>, onInvalid: () -> Void)?
    private let isAI: Bool
    private let isCurrentRow: Bool
    
    @Binding private var cleanCells: Bool
    
    init(
        cleanCells: Binding<Bool>,
        isAI: Bool = false,
        allowed: (set: Set<Character>, onInvalid: () -> Void)? = nil,
        current: Binding<Int>,
        length: Int,
        placeHolderData: [BestGuess]? = nil,
        isCurrentRow: Bool = false,
        word: Binding<[String]>,
        gainFocus: Binding<Bool>,
        colors: Binding<[CharColor]>,
        done: @escaping () -> ()
    ) {
        self.isAI = isAI
        self.allowed = allowed
        self.length = length
        self.isCurrentRow = isCurrentRow
        self.placeHolderData = placeHolderData
        self.done = done
        self.wordBakup = [String](repeating: "", count: word.wrappedValue.count)
        _current = current
        _cleanCells = cleanCells
        _gainFocus = gainFocus
        _colors = colors
        _word = word
    }
    
    private func onDidType(text: String, index: Int) {
        let process = wordBakup.contains(where: { c in c.isEmpty })
        guard process else { return }
        handleWordWriting(value: text, current: index)
        wordBakup[index] = word[index]
        let isCompleteWord = !wordBakup.contains(where: { c in c.count != 1 })
        guard isCompleteWord && wordBakup == word else { return }
        done()
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<length, id: \.self) { i in
                let view = charView(i: i)
                
                if isAI {
                    if isCurrentRow {
                        let waiting = {
                            GuessingGlyphView(index: i,
                                              outOf: length,
                                              language: language == "he" ? .he : .en)
                        }
                        view.placeHolder(when: word[i].isEmpty, placeholder: waiting)
                    } else { view }
                } else  {
                    let placeHolderData: [BestGuess] = placeHolderData ?? []
                    let placeHolderForCell = placeHolderForCell(i)
                    let usePlaceHolderData = word[i].isEmpty &&
                    !placeHolderData.isEmpty &&
                    !placeHolderForCell.filter { _, color in color != .noGuess && color != .noMatch }.isEmpty
                    
                    let placeholder = { placeHoldersView(placeHolderForCell: placeHolderForCell, i: i) }
                    view.placeHolder(when: usePlaceHolderData, placeholder: placeholder)
                }
            }
        }
        .onChange(of: current) {
            wordBakup = [String](repeating: "", count: $word.wrappedValue.count)
            fieldFocus = .one
        }
        .onChange(of: gainFocus) {
            if gainFocus { fieldFocus = .one } else { fieldFocus = nil }
        }
        .onAppear {
            guard !isAI && gainFocus else { return }
            fieldFocus = .one
        }
        .environment(\.layoutDirection, language == "he" ? .rightToLeft : .leftToRight)
    }
    
    // MARK: - Placeholders
    
    @ViewBuilder
    private func placeHoldersView(placeHolderForCell: [Guess], i: Int) -> some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(0..<placeHolderForCell.count, id: \.self) { j in
                let char = placeHolderForCell[j]
                if char.color != .noGuess && char.color != .noMatch {
                    charViewPlaceHolder(guess: char, isFirst: i == 0)
                }
            }
        }
    }
    
    // MARK: - Cells
    
    @ViewBuilder
    private func charView(i: Int) -> some View {
        let placeHolderForCell = placeHolderForCell(i)
        let aiPlaceHolder = isAI && !isCurrentRow
        let playerPlaceHolder = !isAI && (placeHolderData == nil || placeHolderForCell.filter { _, color in color != .noGuess && color != .noMatch }.isEmpty)
        let usePlaceHolderText = cleanCells || aiPlaceHolder || playerPlaceHolder
        
        CharView(
            text: cleanCells ? .constant("") : $word[i],
            usePlaceHolder: usePlaceHolderText,
            didType: { text in onDidType(text: text, index: i) }
        )
        .frame(maxHeight: .infinity)
        .textInputAutocapitalization(i == 0 ? .sentences : .never)
        .autocorrectionDisabled()
        .focused($fieldFocus, equals: FieldFocus(rawValue: i))
        .onSubmit {
            let next = min(i + 1, length - 1)
            fieldFocus = FieldFocus(rawValue: next)
        }
        .onTapGesture {
            fieldFocus = FieldFocus(rawValue: i)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .animation(.easeOut(duration: 0.8), value: cleanCells)
        .realisticCell(color: cleanCells ? .white.opacity(0.8) : colors[i].baseColor.opacity(0.8))
        .elevated(cornerRadius: 4)
//        .realStone(cornerRadius: 4,
//                   crackCount: Int.random(in: 3...6),
//                   seed: UInt64.random(in: 1337...2337))
        .premiumTile(cornerRadius: 4)
        .focusGlow(fieldFocus?.rawValue == i, cornerRadius: 4)
        .accessibilityLabel(Text("Letter cell \(i+1)"))
        .accessibilityHint(Text("Double tap to edit"))
    }
    
    @ViewBuilder
    private func charViewPlaceHolder(guess: Guess, isFirst: Bool) -> some View {
        TextField("", text: .constant(isFirst ? guess.char.capitalized : guess.char))
            .accentColor(.black.opacity(0.2))
            .frame(maxHeight: .infinity)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(isFirst ? .sentences : .never)
            .autocorrectionDisabled()
            .keyboardType(.default)
            .disabled(true)
            .background(
                ZStack {
                    guess.color.color.opacity(0.38)
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .hideSystemInputAssistant()
            .opacity(0.28)
            .premiumTile(cornerRadius: 4)
    }
    
    // MARK: - Logic (unchanged)
    
    private func handleWordWriting(value: String, current: Int) {
        guard wordBakup[current] != word[current] else { return }
        
        if current == 0 {
            let c = value.returnChar(isFinal: false)
            if allowed == nil || allowed!.set.contains(c.lowercased()) {
                word[current] = c.returnChar(isFinal: current == length - 1)
            } else {
                word[current] = ""
                if value.count == 1 {
                    allowed?.onInvalid()
                }
            }
        }
        
        if !value.isEmpty {
            if current < length - 1 && fieldFocus != FieldFocus(rawValue: length - 1) && wordBakup[current].count == 1 || value.count > 1 {
                var next: Int = current
                if !value.isEmpty {
                    let c = value[0].returnChar(isFinal: false)
                    if allowed == nil || allowed!.set.contains(c.lowercased()) {
                        word[next] = c.returnChar(isFinal: current == length - 1)
                        next += 1
                    } else {
                        word[next] = ""
                        allowed?.onInvalid()
                    }
                    
                    guard next < wordBakup.count && wordBakup[next].isEmpty else { return }
                    
                    if value.count > 1 {
                        let string = String(value.suffix(value.count - 1))
                        for i in 0..<string.count {
                            guard next < word.count else { continue }
                            let c = string[i].returnChar(isFinal: false)
                            guard allowed == nil || allowed!.set.contains(c.lowercased()) else { word[next] = ""; allowed?.onInvalid(); continue }
                            word[next] = c.returnChar(isFinal: next == length - 1)
                            next += 1
                        }
                    }
                }
                
                fieldFocus = FieldFocus(rawValue: next - 1)
            }
        } else {
            if current > 0 && fieldFocus != .one && !word[current - 1].isEmpty {
                fieldFocus = FieldFocus(rawValue: current - 1)
            }
        }
    }
}
