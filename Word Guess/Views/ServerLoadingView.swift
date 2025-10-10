import SwiftUI

public struct ServerLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity: CGFloat = 1
  
    public var body: some View {
        contant()
            .onAppear { animate() }
            .onDisappear { reset() }
            .ignoresSafeArea(.keyboard)
    }
    
    @ViewBuilder private func contant() -> some View {
        ZStack {
            VStack {
                Spacer()
                AppTitle(animated: true)
                    .opacity(opacity)
                Spacer()
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
