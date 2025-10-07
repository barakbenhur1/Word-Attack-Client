import SwiftUI

public struct ServerLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity: CGFloat = 1
    
    @FocusState private var isFirstResponder: Bool
    
    private let keyboardHeightStore = KeyboardHeightStore()
    
    public var body: some View {
        contant()
            .onAppear { animate() }
            .onDisappear { reset() }
            .ignoresSafeArea(.keyboard)
    }
    
    @ViewBuilder private func contant() -> some View {
        ZStack {
            if keyboardHeightStore.height == 0 {
                TextField("", text: .constant(""))
                    .focused($isFirstResponder)
            }
            VStack {
                Spacer()
                AppTitle(animated: true)
                    .opacity(opacity)
                Spacer()
            }
            .onAppear {
                guard keyboardHeightStore.height == 0  else { return }
                isFirstResponder = true
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                    isFirstResponder = false
//                }
            }
        }
    }
    
    private func animate() {
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                opacity = 0.6
            }
        }
    }
    
    private func reset() {
        opacity = 1
    }
}
