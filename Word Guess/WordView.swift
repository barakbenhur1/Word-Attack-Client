//
//  WordView.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI

struct CharColor {
    let color: Color
    
    static let noGuess: CharColor = .init(color: .white)
    static let noMatch: CharColor = .init(color: .gray)
    static let partialMatch: CharColor = .init(color: .yellow)
    static let extectMatch: CharColor = .init(color: .green)
}

struct WordView<VM: ViewModel>: View {
    @EnvironmentObject private var vm: VM
    @EnvironmentObject private var local: LanguageSetting
    
    private let length: Int
    private let done: () -> ()
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    @Binding private var gainFocus: Bool
    @Binding private var word: [String]
    @State private var wordBakup: [String]
    @Binding private var colors: [CharColor]
    @FocusState private var fieldFocus: FieldFocus?
    
    init(length: Int, word: Binding<[String]>,  gainFocus: Binding<Bool>, colors: Binding<[CharColor]>, done: @escaping () -> ()) {
        self.length = length
        self.done = done
        self.wordBakup = [String](repeating: "", count: word.wrappedValue.count)
        _gainFocus = gainFocus
        _colors = colors
        _word = word
    }
    
    var body: some View {
        HStack {
            ForEach(0..<length, id: \.self) { i in
                CharView(text: $word[i],
                         didType: { text in
                    guard wordBakup[i] != text else { return }
                    guard fieldFocus?.rawValue == i else { return }
                    handleWordWriting(value: text,
                                      current: i)
                    wordBakup[i] = word[i]
                    guard word.joined().count == length else { return }
                    done()
                })
                .frame(maxHeight: .infinity)
                .focused($fieldFocus, equals: FieldFocus(rawValue: i)!)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .background(colors[i].color)
                .onTapGesture { fieldFocus = FieldFocus(rawValue: i)! }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.black,
                                lineWidth: 1)
                )
                .shadow(radius: 2)
            }
        }
        .onChange(of: vm.current) {
            wordBakup = [String](repeating: "", count: $word.wrappedValue.count)
            fieldFocus = .one
        }
        .onAppear {
            guard gainFocus else { return }
            fieldFocus = .one
        }
        .environment(\.layoutDirection, language == "he" ? .rightToLeft : .leftToRight)
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
        }
        else {
            if  current > 0 && fieldFocus != .one && !word[current - 1].isEmpty {
                fieldFocus = FieldFocus(rawValue: current - 1)!
            }
        }
    }
}
