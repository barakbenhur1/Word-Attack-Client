//
//  KeyboardHeightView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 06/10/2025.
//

import SwiftUI
import Combine

// MARK: Cache + live updates
@Observable
final class KeyboardHeightStore: ObservableObject {
    private var lastKnownHeight: CGFloat?
    
    var height: CGFloat { max(0, lastKnownHeight ?? 0) }
    
    private var subs = Set<AnyCancellable>()
    
    init() {
        self.lastKnownHeight = UserDefaults.standard.object(forKey: "kb.lastKnownHeight") as? CGFloat
        guard self.lastKnownHeight == nil || self.lastKnownHeight == 0 else { return }
        let willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        let willHide   = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        
        willChange
            .merge(with: willHide)
            .sink { [weak self] note in
                guard let self else { return }
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
                
                // Compute overlap with the key window (covers rotation, external displays, etc.)
                let window = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first { $0.isKeyWindow }
                
                let overlap = window.map { max(0, $0.bounds.maxY - end.origin.y) } ?? end.height
                lastKnownHeight = overlap.rounded(.toNearestOrAwayFromZero)
                UserDefaults.standard.set(lastKnownHeight, forKey: "kb.lastKnownHeight")
            }
            .store(in: &subs)
    }
}

// MARK: Heuristic (used only if no cached value yet)
func estimatedKeyboardHeightFallback() -> CGFloat {
    // Conservative estimates that look decent until we have a real value.
    // You can tweak to your app’s needs.
    let idiom = UIDevice.current.userInterfaceIdiom
    let isPortrait = UIScreen.main.bounds.height >= UIScreen.main.bounds.width
    let bottomSafe = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }?.safeAreaInsets.bottom ?? 0

    switch idiom {
    case .phone:
        // Typical iPhone portrait keyboards are ~300–350pt; landscape ~200–240pt. Add safe area if present.
        return (isPortrait ? 270 : 220) + bottomSafe
    case .pad:
        // iPad varies with floating/split—pick a middle ground.
        return (isPortrait ? 290 : 300) + bottomSafe
    default:
        return 330 + bottomSafe
    }
}

// MARK: View: use keyboard height even when hidden
struct KeyboardHeightView: View {
    let adjustBy: CGFloat
    private var store: KeyboardHeightStore
    
    init(adjustBy: CGFloat = 0) {
        self.store = KeyboardHeightStore()
        self.adjustBy = adjustBy
    }
    
    var body: some View {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        Color.clear
            .frame(height: store.height > 0 ? store.height - (isPad ? 15 : 35) + adjustBy : estimatedKeyboardHeightFallback())
    }
}
