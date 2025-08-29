//
//  HideInputAssistant.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 29/08/2025.
//

import SwiftUI
import UIKit

struct HideInputAssistant: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField(frame: .zero)
        tf.isHidden = true
        // Clearing both groups hides the SystemInputAssistantView globally
        let item = tf.inputAssistantItem
        item.leadingBarButtonGroups  = []
        item.trailingBarButtonGroups = []
        return tf
    }
    func updateUIView(_ uiView: UITextField, context: Context) {}
}

extension View {
    /// Add this somewhere inside the view tree that hosts your text inputs
    func hideSystemInputAssistant() -> some View {
        background(HideInputAssistant().frame(width: 0, height: 0))
    }
}
