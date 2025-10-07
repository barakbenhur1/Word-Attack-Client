//
//  DynamicColors.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 07/10/2025.
//

import SwiftUI

extension Color {
    /// White in light mode, soft dark in dark mode (tweak values as you like)
    static let dynamicWhite = Color(UIColor { trait in
        if trait.userInterfaceStyle == .dark {
            return .black
        } else {
            return .white
        }
    })

    static let dynamicBlack = Color(UIColor { trait in
        if trait.userInterfaceStyle == .dark {
            return .white
        } else {
            return .black
        }
    })
}
