//
//  WordView.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI

struct CharColor: Comparable {
    static func == (lhs: CharColor, rhs: CharColor) -> Bool {
        return lhs.id == rhs.id
    }
    
    static func < (lhs: CharColor, rhs: CharColor) -> Bool {
        return lhs.id > rhs.id
    }
    
    let id: Int
    let color: LinearGradient
    
    static let noGuess: CharColor = .init(id: 0,
                                          color: .linearGradient(colors: [.white.opacity(0.6), .white],
                                                                 startPoint: .leading,
                                                                 endPoint: .trailing))
    static let noMatch: CharColor = .init(id: 1,
                                          color: .linearGradient(colors: [.gray.opacity(0.6), .gray],
                                                                 startPoint: .leading,
                                                                 endPoint: .trailing))
    static let partialMatch: CharColor = .init(id: 2,
                                               color: .linearGradient(colors: [.yellow.opacity(0.6), .yellow],
                                                                      startPoint: .leading,
                                                                      endPoint: .trailing))
    static let exactMatch: CharColor = .init(id: 3,
                                             color: .linearGradient(colors: [.green.opacity(0.6), .green],
                                                                    startPoint: .leading,
                                                                    endPoint: .trailing))
    
    func getColor() -> String {
        switch self {
        case let i where i.id == CharColor.partialMatch.id : return "🟨"
        case let i where i.id == CharColor.exactMatch.id : return "🟩"
        default: return "⬜"
        }
    }
    
    func toColor() -> Color {
        switch self {
        case let i where i == .exactMatch: return .green
        case let i where i == .partialMatch: return .yellow
        case let i where i == .noMatch: return .gray
        case let i where i == .noGuess: return .white
        default: return .clear
        }
    }
}

struct WordView<VM: ViewModel>: View {
    @EnvironmentObject private var vm: VM
    @EnvironmentObject private var local: LanguageSetting
    
    private let length: Int
    private let placeHolderData: [[Guess]]?
    private let done: () -> ()
    
    private var placeHolderForCell: (_ i: Int) -> [Guess] {
        return { i in
            guard let placeHolderData else { return [] }
            var td = [Guess]()
            for k in 0..<placeHolderData.count {
                let g = placeHolderData[k][i]
                guard !td.contains(where: { char, color in char == g.char && color == g.color }) else { continue }
                td.append(g)
            }
            
            return td
        }
    }
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    @Binding private var gainFocus: Bool
    @Binding private var word: [String]
    @State private var wordBakup: [String]
    @Binding private var colors: [CharColor]
    @FocusState private var fieldFocus: FieldFocus?
    
    private let isAI: Bool
    private let isCurrentRow: Bool
    
    init(isAI: Bool = false, length: Int, placeHolderData: [[Guess]]? = nil, isCurrentRow: Bool = false, word: Binding<[String]>, gainFocus: Binding<Bool>, colors: Binding<[CharColor]>, done: @escaping () -> ()) {
        self.isAI = isAI
        self.length = length
        self.isCurrentRow = isCurrentRow
        self.placeHolderData = placeHolderData
        self.done = done
        self.wordBakup = [String](repeating: "", count: word.wrappedValue.count)
        _gainFocus = gainFocus
        _colors = colors
        _word = word
    }
    
    private func onDidType(text: String, i: Int) {
        guard wordBakup[i] != text else { return }
        if !isAI { guard fieldFocus?.rawValue == i else { return } }
        handleWordWriting(value: text,
                          current: i)
        wordBakup[i] = word[i]
        guard word.joined().count == length else { return }
        done()
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<length, id: \.self) { i in
                let view = charView(i: i)
                
                if isAI {
                    if isCurrentRow {
                        let waiting = { GuessingGlyphView(index: i,
                                                          outOf: length,
                                                          language: language == "he" ? .he : .en) }
                        
                        view
                            .placeHolder(when: word[i].isEmpty,
                                         placeholder: waiting)
                    } else { view }
                } else  {
                    let placeHolderData: [[Guess]] = placeHolderData ?? []
                    
                    let placeHolderForCell = placeHolderForCell(i)
                    
                    let usePlaceHolderData = word[i].isEmpty && !placeHolderData.isEmpty && !placeHolderForCell.filter { _, color in color != .noGuess && color != .noMatch }.isEmpty
                    
                    let placeholder = { placeHoldersView(placeHolderForCell: placeHolderForCell, i: i) }
                    
                    view
                        .placeHolder(when: usePlaceHolderData,
                                     placeholder: placeholder)
                }
            }
        }
        .onChange(of: vm.current) {
            wordBakup = [String](repeating: "", count: $word.wrappedValue.count)
            fieldFocus = .one
        }
        .onChange(of: gainFocus) {
            if gainFocus { fieldFocus = .one }
            else { fieldFocus = nil }
        }
        .onAppear {
            guard !isAI && gainFocus else { return }
            fieldFocus = .one
        }
        .environment(\.layoutDirection, language == "he" ? .rightToLeft : .leftToRight)
    }
    
    @ViewBuilder
    private func placeHoldersView(placeHolderForCell: [Guess], i: Int) -> some View {
        HStack(alignment: .center,
               spacing: 0) {
            ForEach(0..<placeHolderForCell.count, id: \.self) { j in
                let char = placeHolderForCell[j]
                if char.color != .noGuess && char.color != .noMatch {
                    charViewPlaceHolder(guess: char,
                                        isFirst: i == 0)
                }
            }
        }
    }
    
    @ViewBuilder
    private func getBackground(i: Int, usePlaceHolder: Bool) -> some View {
        if usePlaceHolder || !word[i].isEmpty { colors[i].color.blur(radius: 4) }
        else { Color.clear }
    }
    
    @ViewBuilder
    private func charView(i: Int) -> some View {
        let placeHolderForCell = placeHolderForCell(i)
        let usePlaceHolderText = (isAI && !isCurrentRow) || (!isAI && (placeHolderData == nil || placeHolderForCell.filter { _, color in color != .noGuess && color != .noMatch }.isEmpty))
        
        CharView(isAI: isAI,
                 text: $word[i],
                 usePlaceHolder: usePlaceHolderText,
                 didType: { text in onDidType(text: text, i: i) })
        .background(getBackground(i: i,
                                  usePlaceHolder: usePlaceHolderText))
        .frame(maxHeight: .infinity)
        .textInputAutocapitalization(i == 0 ? .sentences : .never)
        .autocorrectionDisabled()
        .focused($fieldFocus, equals: FieldFocus(rawValue: i)!)
        .onSubmit { fieldFocus = FieldFocus(rawValue: i)! }
        .onTapGesture { fieldFocus = FieldFocus(rawValue: i)! }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .realisticCell(color: colors[i].toColor())
        .elevated(cornerRadius: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.black,
                        lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func charViewPlaceHolder(guess: Guess, isFirst: Bool) -> some View {
        TextField("", text: .constant(isFirst ? guess.char.capitalized : guess.char))
            .accentColor(.black.opacity(0.2))
            .frame(maxHeight: .infinity)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(isFirst ? .sentences : .never)
            .autocorrectionDisabled()
            .background(guess.color.color.blur(radius: 4))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .disabled(true)
            .opacity(0.2)
    }
    
    private func handleWordWriting(value: String, current: Int) {
        guard wordBakup[current] != word[current] else { return }
        
        if current == 0 { word[current] = value.returnChar(isFinal: current == length - 1) }
        
        if !value.isEmpty {
            if current < length - 1 && fieldFocus != FieldFocus(rawValue: length - 1) && wordBakup[current].count == 1 || value.count > 1 {
                var next = current + 1
                if !value.isEmpty {
                    word[current] = value[0].returnChar(isFinal: current == length - 1)
                    
                    guard next < wordBakup.count && wordBakup[next].isEmpty else { return }
                    
                    if value.count > 1 {
                        let string = String(value.suffix(value.count - 1))
                        for i in 0..<string.count {
                            guard next < word.count else { continue }
                            word[next] = string[i].returnChar(isFinal: next == length - 1)
                            next += 1
                        }
                    }
                }
                fieldFocus = FieldFocus(rawValue: next - 1)!
            }
        } else {
            if  current > 0 && fieldFocus != .one && !word[current - 1].isEmpty {
                fieldFocus = FieldFocus(rawValue: current - 1)!
            }
        }
    }
}
