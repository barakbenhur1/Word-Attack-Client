import SwiftUI

struct CenterPinnedBurstModifier: ViewModifier {
    @Binding var trigger: Bool
    
    func body(content: Content) -> some View {
        content
            .mask(Circle())
            .scaleEffect(!trigger ? 0.2 : 3)
            .opacity(trigger ? 1 : 0)
    }
}

struct ElevatedModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var shadowColor: Color = .black.opacity(0.15)
    var shadowRadius: CGFloat = 8
    var shadowYOffset: CGFloat = 4
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius,
                                 style: .continuous)
                .fill(Color.white)
                .shadow(color: shadowColor,
                        radius: shadowRadius,
                        x: 0,
                        y: shadowYOffset)
                .shadow(color: .black.opacity(0.05),
                        radius: 2,
                        x: 0,
                        y: 1) // subtle secondary shadow
            )
    }
}

struct RealisticCellModifier: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(gradient: Gradient(colors: [color,
                                                                     color.opacity(0.15)]),
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3),
                        lineWidth: 1))
            .shadow(color: .black.opacity(0.15),
                    radius: 6,
                    x: 3,
                    y: 3)
            .shadow(color: .white.opacity(0.7),
                    radius: 6,
                    x: -3,
                    y: -3) // top-left glow
            .padding(4)
    }
}

struct LoadingViewModifier: ViewModifier {
    let show: Bool
    
    func body(content: Content) -> some View {
        ZStack {
            content
            if show {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
    }
}

extension View {
    func circleReveal(trigger: Binding<Bool>) -> some View { modifier(CenterPinnedBurstModifier(trigger: trigger)) }
    func realisticCell(color: Color) -> some View { modifier(RealisticCellModifier(color: color)) }
    func elevated(cornerRadius: CGFloat) -> some View { modifier(ElevatedModifier(cornerRadius: cornerRadius)) }
    func loading(show: Bool) -> some View { modifier(LoadingViewModifier(show: show)) }
}
