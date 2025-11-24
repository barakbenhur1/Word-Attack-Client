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
                    .stroke(isFocused ? Color.yellow.opacity(0.25) : .clear, lineWidth: 1.0)
                    .shadow(color: isFocused ? Color.blue.opacity(0.10) : .clear, radius: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? Color.blue.opacity(0.3) : .clear, lineWidth: 6)
                    .blur(radius: 2)
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

struct WordView<VM: GameViewModel>: View {
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
    @Binding private var isSolved: Bool
    @FocusState private var fieldFocus: FieldFocus?
    
    @State private var waveTrigger = false
    
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
        isSolved: Binding<Bool>,
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
        _isSolved = isSolved
        _current = current
        _cleanCells = cleanCells
        _gainFocus = gainFocus
        _colors = colors
        _word = word
    }
    
    // Kick the wave when the row is marked solved (with an initial delay)
    private func startWave(after delay: Double = 0) {
        guard !waveTrigger else { return }
        let start = delay

        DispatchQueue.main.asyncAfter(deadline: .now() + start) {
            // If the row was reset or unsolved during the delay, don't fire.
            guard isSolved else { return }

            waveTrigger = true

            // Match your per-cell delay calc: (waveIndex + 1) * 0.16
            // Longest cell starts at ~length*0.16. Add a bit to let the spring settle.
            let longestStagger = Double(length) * 0.16
            let settle: Double = 0.80
            let total = longestStagger + settle

            DispatchQueue.main.asyncAfter(deadline: .now() + total) {
                waveTrigger = false
            }
        }
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
            if gainFocus { fieldFocus = .one } else { fieldFocus = nil }
        }
        .onChange(of: gainFocus) {
            if gainFocus { fieldFocus = .one } else { fieldFocus = nil }
        }
        .onChange(of: isSolved) { _,solved in
            if solved { startWave(after: 0.35) }
        }
        .onAppear {
            guard !isAI else { return }
            fieldFocus = gainFocus ? .one : nil
        }
        .environment(\.layoutDirection, language == "he" ? .rightToLeft : .leftToRight)
    }
    
    // MARK: - Placeholders
    @ViewBuilder
    private func placeHoldersView(placeHolderForCell: [Guess], i: Int) -> some View {
        HStack(alignment: .center, spacing: -4) {
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
        
        let rtl = (language == "he")
        let waveIndex = rtl ? (length - 1 - i) : i
        let perCellDelay = Double(waveIndex + 1) * 0.16
        
        ZStack {
            CharView(
                text: cleanCells ? .constant("") : $word[i],
                usePlaceHolder: usePlaceHolderText,
                didType: { text in onDidType(text: text, index: i) }
            )
            .frame(maxHeight: .infinity)
            .textInputAutocapitalization(i == 0 ? .sentences : .never)
            .autocorrectionDisabled()
            .textSelection(.disabled)
            .contextMenu { }
            .focused($fieldFocus, equals: FieldFocus(rawValue: i))
            .realisticCell(color: cleanCells ? .white.opacity(0.8) : colors[i].baseColor.opacity(0.8), cornerRadius: 4)
            .elevated(cornerRadius: 4)
            .premiumTile(cornerRadius: 4)
            .focusGlow(fieldFocus == .init(rawValue: i), cornerRadius: 4)
            .focusGlow(fieldFocus == .init(rawValue: i), cornerRadius: 4)
            .waveBounce(trigger: waveTrigger, delay: perCellDelay, lift: 0, tilt: 6, scale: 0.88)
            .onSubmit {
                let next = min(i + 1, length - 1)
                fieldFocus = FieldFocus(rawValue: next)
            }
            .onTapGesture {
                fieldFocus = FieldFocus(rawValue: i)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .animation(.easeOut(duration: 0.8), value: cleanCells)
            
            Rectangle().opacity(0.001)
                .onTapGesture {
                    let current = min(i , length - 1)
                    fieldFocus = FieldFocus(rawValue: current)
                }
                .allowsHitTesting(true)
        }
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
                    guess.color.color.opacity(0.46)
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
    
    // MARK: - Logic
    private func handleWordWriting(value: String, current: Int) {
        guard wordBakup[current] != word[current] else { return }
        if value.isEmpty {
            if current > 0 && fieldFocus != .one {
                fieldFocus = FieldFocus(rawValue: current - 1)
            }
        } else if current < length && fieldFocus != FieldFocus(rawValue: length) {
            var value = value
            let last = value.popLast()
            let lastChar = last != nil ? String(last!) : ""
            var fixedValue = wordBakup[current] == lastChar ? lastChar + value : value + lastChar
            guard let first = fixedValue.first else  { return }
            if wordBakup[current] == String(first) { fixedValue.remove(at: fixedValue.startIndex) }
            if current == 0 { fixedValue = fixedValue.capitalizedFirst }
            var next: Int = current
            for v in fixedValue {
                guard next < word.count else { return }
                let char = String(v).returnChar(isFinal: false)
                guard allowed == nil || allowed!.set.contains(char.lowercased()) else { word[next] = ""; allowed?.onInvalid(); continue }
                word[next] = char.returnChar(isFinal: next == length - 1)
                next += 1
            }
            
            guard next < length else { return }
            //            word[next] = .invisible
            fieldFocus = FieldFocus(rawValue: next)
        }
    }
}

// MARK: - Wave Effect (iOS 16+)
private struct WaveBounce: ViewModifier {
    let trigger: Bool
    let delay: Double
    let lift: CGFloat
    let tilt: Double
    let scale: CGFloat
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(trigger ? scale : 1.0)
            .offset(y: trigger ? -lift : 0)
            .rotationEffect(.degrees(trigger ? -tilt : 0))
            .animation(
                .interpolatingSpring(stiffness: 220, damping: 16)
                    .delay(delay),
                value: trigger
            )
    }
}

private extension View {
    /// Applies a per-cell delayed "wave bounce".
    func waveBounce(trigger: Bool, delay: Double,
                    lift: CGFloat = 10, tilt: Double = 3, scale: CGFloat = 1.06) -> some View {
        modifier(WaveBounce(trigger: trigger, delay: delay, lift: lift, tilt: tilt, scale: scale))
    }
}

extension String {
    static let invisible = "\u{200B}"
    var strippingInvisible: String { filter { String($0) != .invisible } }
}
