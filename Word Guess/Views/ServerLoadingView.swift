import SwiftUI

public struct ServerLoadingView: View {
    @State private var opacity: CGFloat = 1
    public var body: some View {
        VStack {
            Spacer()
            AppTitle()
                .opacity(opacity)
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                opacity = 0.6
            }
        }
        .onDisappear { opacity = 1 }
    }
}
