// ==================================================
// MARK: DoorOrnamentsView (refined gold + shimmer)
// ==================================================

import SwiftUI

enum DoorSide { case left, right }
enum CrestPlacement { case center, left, right }

// Professional burnished gold palette
enum Gold {
    // hi: warm highlight, mid: brass body, deep: shadowed brass, edge: rim line
    static let hi   = Color(red: 1.00, green: 0.94, blue: 0.76)   // #FFF0C1
    static let mid  = Color(red: 0.83, green: 0.69, blue: 0.22)   // #D4AF37
    static let deep = Color(red: 0.49, green: 0.36, blue: 0.13)   // #7D5C21
    static let edge = Color(red: 0.30, green: 0.22, blue: 0.09)   // #4D3817
}

struct DoorOrnamentsView: View {
    var cornerRadius: CGFloat = 28
    var inset: CGFloat = 42
    var lineWidth: CGFloat = 2
    var studsSpacing: CGFloat = 30
    var studSize: CGFloat = 7
    
    var showHinges: Bool = true
    var showHandle: Bool = true
    var showCrest: Bool = true
    var shimmer: Bool = true
    
    var side: DoorSide = .left
    var crestPlacement: CrestPlacement = .center
    var openProgress: CGFloat = 0
    
    @State private var shimmerPhase: CGFloat = -1
    @Environment(\.colorScheme) private var scheme
    
    var body: some View {
        GeometryReader { geo in
            let rect = geo.frame(in: .local).insetBy(dx: inset, dy: inset)
            
            ZStack {
                // Beveled frame with subtler lighting
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .inset(by: lineWidth/2)
                    .stroke(
                        LinearGradient(colors: [Gold.hi, Gold.mid, Gold.deep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: lineWidth
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .inset(by: lineWidth + 1.0)
                            .stroke(
                                LinearGradient(colors: [
                                    Gold.deep.opacity(0.90),
                                    Gold.mid.opacity(0.60),
                                    Gold.hi.opacity(0.40)
                                ],
                                               startPoint: .bottomTrailing, endPoint: .topLeading),
                                lineWidth: 1
                            )
                    )
                
                studs(in: rect)
                
                if showHinges {
                    hinge(in: rect, y: rect.minY + rect.height * 0.28)
                    hinge(in: rect, y: rect.minY + rect.height * 0.72)
                }
                
                if showHandle { handle(in: rect) }
                if showCrest  { crest(in: rect) }
                
                if shimmer {
                    let dir: CGFloat = (side == .left) ? 1 : -1
                    let start: UnitPoint = (side == .left) ? .leading : .trailing
                    let end:   UnitPoint = (side == .left) ? .trailing : .leading
                    let reveal = max(0, min(openProgress, 1))
                    
                    let highlight = LinearGradient(
                        colors: [
                            .white.opacity(0.00),
                            .white.opacity(scheme == .dark ? 0.26 : 0.14), // toned down
                            .white.opacity(0.00)
                        ],
                        startPoint: start, endPoint: end
                    )
                    let mode: BlendMode = (scheme == .dark) ? .screen : .overlay
                    
                    let shadow = LinearGradient(
                        colors: [
                            .black.opacity(0.00),
                            .black.opacity(0.14),
                            .black.opacity(0.00)
                        ],
                        startPoint: start, endPoint: end
                    )
                        .blendMode(.multiply)
                        .offset(x: dir * 8)
                    
                    ZStack { highlight.blendMode(mode); shadow }
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: dir * (shimmerPhase - 0.5) * rect.width)
                        .mask(
                            ZStack(alignment: side == .left ? .trailing : .leading) {
                                Color.clear
                                Rectangle().fill(Color.white)
                                    .frame(width: rect.width * reveal * 2, height: rect.height)
                            }
                        )
                        .opacity(reveal > 0 ? 1 : 0)
                        .compositingGroup()
                        .onAppear {
                            shimmerPhase = -1
                            withAnimation(.linear(duration: 2).delay(1).repeatForever(autoreverses: false)) {
                                shimmerPhase = 1.5
                            }
                        }
                        .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(false)
        }
    }
    
    // studs
    private func studs(in rect: CGRect) -> some View {
        let xs = stride(from: rect.minX + cornerRadius, through: rect.maxX - cornerRadius, by: studsSpacing)
        let ys = stride(from: rect.minY + cornerRadius, through: rect.maxY - cornerRadius, by: studsSpacing)
        
        func stud() -> some View {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Gold.hi, Gold.mid, Gold.deep],
                        center: .init(x: 0.35, y: 0.35),
                        startRadius: 0, endRadius: studSize
                    )
                )
                .overlay(Circle().stroke(Gold.edge.opacity(0.35), lineWidth: 0.7))
                .frame(width: studSize, height: studSize)
                .shadow(color: .black.opacity(0.22), radius: 1, x: 0, y: 1)
        }
        
        return ZStack {
            ForEach(Array(xs.enumerated()), id: \.offset) { _, x in stud().position(x: x, y: rect.minY) }
            ForEach(Array(xs.enumerated()), id: \.offset) { _, x in stud().position(x: x, y: rect.maxY) }
            ForEach(Array(ys.enumerated()), id: \.offset) { _, y in stud().position(x: rect.minX, y: y) }
            ForEach(Array(ys.enumerated()), id: \.offset) { _, y in stud().position(x: rect.maxX, y: y) }
        }
    }
    
    // hinges
    @ViewBuilder
    private func hinge(in rect: CGRect, y: CGFloat) -> some View {
        let h = max(36, rect.width * 0.10)
        let w: CGFloat = 22
        let edgePadding: CGFloat = -31
        
        let x: CGFloat = (side == .left) ? rect.minX + edgePadding : rect.maxX - edgePadding
        let yMin = rect.minY + cornerRadius + h/2 + 2
        let yMax = rect.maxY - cornerRadius - h/2 - 2
        let ySafe = min(max(y, yMin), yMax)
        
        let plateFill: LinearGradient = (side == .left)
        ? LinearGradient(colors: [Gold.deep, Gold.mid, Gold.hi], startPoint: .leading, endPoint: .trailing)
        : LinearGradient(colors: [Gold.hi,  Gold.mid, Gold.deep], startPoint: .leading, endPoint: .trailing)
        
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(plateFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Gold.edge.opacity(0.35), lineWidth: 0.8)
                )
                .frame(width: w, height: h)
                .position(x: x, y: ySafe)
                .shadow(color: .black.opacity(0.30), radius: 2,
                        x: side == .left ? 1 : -1, y: 1)
            
            let screw: CGFloat = 2.2
            Group {
                Circle().fill(Gold.edge.opacity(0.9)).frame(width: screw*2, height: screw*2)
                    .position(x: x - w*0.36, y: ySafe - h*0.36)
                Circle().fill(Gold.edge.opacity(0.9)).frame(width: screw*2, height: screw*2)
                    .position(x: x + w*0.36, y: ySafe - h*0.36)
                Circle().fill(Gold.edge.opacity(0.9)).frame(width: screw*2, height: screw*2)
                    .position(x: x - w*0.36, y: ySafe + h*0.36)
                Circle().fill(Gold.edge.opacity(0.9)).frame(width: screw*2, height: screw*2)
                    .position(x: x + w*0.36, y: ySafe + h*0.36)
            }
        }
    }
    
    // handle
    @ViewBuilder
    private func handle(in rect: CGRect) -> some View {
        let w = max(44, rect.width * 0.13), h: CGFloat = 40
        let margin: CGFloat = -20
        let y = rect.midY - 2.5
        
        let isRightHandle = (side == .left)
        let x: CGFloat = isRightHandle
        ? rect.maxX - w/2 - margin
        : rect.minX + w/2 + margin
        
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Gold.hi, Gold.mid, Gold.deep],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Gold.edge.opacity(0.35), lineWidth: 1)
                )
                .frame(width: w, height: h)
                .position(x: x, y: y)
                .shadow(color: .black.opacity(0.30),
                        radius: 2, x: isRightHandle ? 1 : -1, y: 1)
            
            Circle()
                .stroke(
                    LinearGradient(colors: [Gold.hi, Gold.mid, Gold.deep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 3
                )
                .frame(width: 18, height: 18)
                .position(x: x, y: y + 2)
                .shadow(color: .black.opacity(0.22), radius: 1, x: 0, y: 1)
        }
    }
    
    // crest
    @ViewBuilder
    private func crest(in rect: CGRect) -> some View {
        let w = rect.width * 0.28
        let h: CGFloat = 22
        
        let cx: CGFloat = {
            switch crestPlacement {
            case .center: return rect.midX
            case .left:   return rect.minX + w/2 + 8
            case .right:  return rect.maxX - w/2 - 8
            }
        }()
        
        let plateFill: LinearGradient = (crestPlacement == .right)
        ? LinearGradient(colors: [Gold.deep, Gold.mid, Gold.hi], startPoint: .leading, endPoint: .trailing)
        : LinearGradient(colors: [Gold.hi,  Gold.mid, Gold.deep], startPoint: .leading, endPoint: .trailing)
        
        ZStack {
            singleCrest(cx: cx, cy: rect.minY + h, width: w, height: h, inverted: false, plateFill: plateFill)
            singleCrest(cx: cx, cy: rect.maxY - h, width: w, height: h, inverted: true,  plateFill: plateFill)
        }
    }
    
    @ViewBuilder
    private func singleCrest(
        cx: CGFloat, cy: CGFloat,
        width w: CGFloat, height h: CGFloat,
        inverted: Bool,
        plateFill: LinearGradient
    ) -> some View {
        let shadowYOffset: CGFloat = inverted ? -1 : 1
        let r = h * 0.33
        
        ZStack {
            Capsule(style: .continuous)
                .fill(plateFill)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Gold.edge.opacity(0.35), lineWidth: 0.8)
                )
                .frame(width: w, height: h)
                .position(x: cx, y: cy)
                .shadow(color: .black.opacity(0.28), radius: 2, x: 1, y: shadowYOffset)
            
            Path { p in
                if !inverted {
                    p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                             startAngle: .degrees(200), endAngle: .degrees(-20), clockwise: false)
                    p.move(to: CGPoint(x: cx - r*0.8, y: cy))
                    p.addQuadCurve(to: CGPoint(x: cx, y: cy - r*0.9),
                                   control: CGPoint(x: cx - r*1.2, y: cy - r*0.7))
                    p.move(to: CGPoint(x: cx + r*0.8, y: cy))
                    p.addQuadCurve(to: CGPoint(x: cx, y: cy - r*0.9),
                                   control: CGPoint(x: cx + r*1.2, y: cy - r*0.7))
                } else {
                    p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                             startAngle: .degrees(20), endAngle: .degrees(200), clockwise: false)
                    p.move(to: CGPoint(x: cx - r*0.8, y: cy))
                    p.addQuadCurve(to: CGPoint(x: cx, y: cy + r*0.9),
                                   control: CGPoint(x: cx - r*1.2, y: cy + r*0.7))
                    p.move(to: CGPoint(x: cx + r*0.8, y: cy))
                    p.addQuadCurve(to: CGPoint(x: cx, y: cy + r*0.9),
                                   control: CGPoint(x: cx + r*1.2, y: cy + r*0.7))
                }
            }
            .stroke(
                LinearGradient(colors: [Gold.hi, Gold.mid],
                               startPoint: inverted ? .bottom : .top,
                               endPoint:   inverted ? .top    : .bottom),
                lineWidth: 1.2
            )
            .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: shadowYOffset)
        }
    }
}
