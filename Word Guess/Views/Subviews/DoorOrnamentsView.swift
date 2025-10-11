//
//  DoorOrnamentsView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 10/10/2025.
//

import SwiftUI

// MARK: - Gold palette (refined)
enum Gold {
    static let hi   = Color(red: 1.00, green: 0.96, blue: 0.78)   // #FFF5C7
    static let mid  = Color(red: 1.00, green: 0.84, blue: 0.00)   // #FFD200
    static let deep = Color(red: 0.62, green: 0.42, blue: 0.00)   // #9E6B00
    static let edge = Color(red: 0.45, green: 0.31, blue: 0.00)   // rim shadow
}

enum DoorSide { case left, right }
enum CrestPlacement { case center, left, right }

// MARK: - Gold-only ornaments
struct DoorOrnamentsView: View {
    // Layout
    var cornerRadius: CGFloat = 28
    var inset: CGFloat = 42
    var lineWidth: CGFloat = 2
    var studsSpacing: CGFloat = 30
    var studSize: CGFloat = 7
    
    // Features
    var showHinges: Bool = true
    var showHandle: Bool = true
    var showCrest: Bool = true
    var shimmer: Bool = true
    
    /// Hinge side (handle auto-placed opposite)
    var side: DoorSide = .left
    
    /// Crest placement (default centered)
    var crestPlacement: CrestPlacement = .center
    
    /// 0..1 open progress (used to limit shimmer to the opened band)
    var openProgress: CGFloat = 0
    
    @State private var shimmerPhase: CGFloat = -1
    @Environment(\.colorScheme) private var scheme
    
    var body: some View {
        GeometryReader { geo in
            let rect = geo.frame(in: .local).insetBy(dx: inset, dy: inset)
            
            ZStack {
                // 1) Beveled gold frame
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .inset(by: lineWidth/2)
                    .stroke(
                        LinearGradient(colors: [Gold.hi, Gold.mid, Gold.deep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: lineWidth
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .inset(by: lineWidth + 1.2)
                            .stroke(
                                LinearGradient(colors: [Gold.deep.opacity(0.95),
                                                        Gold.mid.opacity(0.7),
                                                        Gold.hi.opacity(0.5)],
                                               startPoint: .bottomTrailing, endPoint: .topLeading),
                                lineWidth: 1
                            )
                    )
                
                // 2) Studs around frame
                studs(in: rect)
                
                // 3) Hinges (hinge side)
                if showHinges {
                    hinge(in: rect, y: rect.minY + rect.height * 0.28)
                    hinge(in: rect, y: rect.minY + rect.height * 0.72)
                }
                
                // 4) Handle (opposite hinge side)
                if showHandle { handle(in: rect) }
                
                // 5) Crest (center by default)
                if showCrest { crest(in: rect) }
                
                // 6) Shimmer — mirrored by hinge side AND clipped to opened portion
                if shimmer {
                    let dir: CGFloat = (side == .left) ? 1 : -1
                    let start: UnitPoint = (side == .left) ? .leading : .trailing
                    let end:   UnitPoint = (side == .left) ? .trailing : .leading
                    let reveal = max(0, min(openProgress, 1)) // clamp 0..1
                    
                    // Highlight that works in both modes
                    let highlight = LinearGradient(
                        colors: [
                            .white.opacity(0.00),
                            .white.opacity(scheme == .dark ? 0.32 : 0.18),
                            .white.opacity(0.00)
                        ],
                        startPoint: start, endPoint: end
                    )
                    // disambiguate BlendMode in the ternary
                    let mode: BlendMode = (scheme == .dark) ? .screen : .overlay
                    
                    // Subtle shadow ridge for light backgrounds
                    let shadow = LinearGradient(
                        colors: [
                            .black.opacity(0.00),
                            .black.opacity(0.18),
                            .black.opacity(0.00)
                        ],
                        startPoint: start, endPoint: end
                    )
                        .blendMode(.multiply)
                        .offset(x: dir * 8)
                    
                    ZStack {
                        highlight.blendMode(mode)
                        shadow
                    }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: dir * (shimmerPhase - 0.5) * rect.width)
                    .mask(  // seam-anchored mask: grows from inner edge
                        ZStack(alignment: side == .left ? .trailing : .leading) {
                            Color.clear
                            Rectangle().fill(Color.white)
                                .frame(width: rect.width * reveal * 2, height: rect.height)
                        }
                    )
                    .opacity(reveal > 0 ? 1 : 0)
                    .compositingGroup() // ensure blends compose against the door
                    .onAppear {
                        shimmerPhase = -1
                        withAnimation(.linear(duration: 2).delay(1).repeatForever(autoreverses: false)) {
                            shimmerPhase = 1.5
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(false) // ornaments don't intercept taps
        }
    }
    
    // MARK: studs
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
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
        }
        
        return ZStack {
            ForEach(Array(xs.enumerated()), id: \.offset) { _, x in stud().position(x: x, y: rect.minY) }
            ForEach(Array(xs.enumerated()), id: \.offset) { _, x in stud().position(x: x, y: rect.maxY) }
            ForEach(Array(ys.enumerated()), id: \.offset) { _, y in stud().position(x: rect.minX, y: y) }
            ForEach(Array(ys.enumerated()), id: \.offset) { _, y in stud().position(x: rect.maxX, y: y) }
        }
    }
    
    // MARK: hinge plates (hinge side)
    @ViewBuilder
    private func hinge(in rect: CGRect, y: CGFloat) -> some View {
        let h = max(36, rect.width * 0.10)
        let w: CGFloat = 22
        
        // Keep hinge clear of the studs and frame stroke
        let edgePadding: CGFloat = -31
        
        // Correct edge per hinge side (centered, with clearance)
        let x: CGFloat = (side == .left)
        ? rect.minX + edgePadding
        : rect.maxX - edgePadding
        
        // Clamp vertically so the plate never hits the rounded corners
        let yMin = rect.minY + cornerRadius + h/2 + 2
        let yMax = rect.maxY - cornerRadius - h/2 - 2
        let ySafe = min(max(y, yMin), yMax)
        
        let screw: CGFloat = 2.2
        
        // Mirror lighting so the brighter edge faces inward
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
                .shadow(color: .black.opacity(0.35),
                        radius: 2,
                        x: side == .left ? 1 : -1,
                        y: 1)
            
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
    
    // MARK: handle plaque (opposite hinge side)
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
                .shadow(color: .black.opacity(0.35),
                        radius: 2,
                        x: isRightHandle ? 1 : -1,
                        y: 1)
            
            // ring
            Circle()
                .stroke(
                    LinearGradient(colors: [Gold.hi, Gold.mid, Gold.deep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 3
                )
                .frame(width: 18, height: 18)
                .position(x: x, y: y + 2)
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
        }
    }
    
    @ViewBuilder
    private func singleCrest(
        cx: CGFloat,
        cy: CGFloat,
        width w: CGFloat,
        height h: CGFloat,
        inverted: Bool,
        plateFill: LinearGradient
    ) -> some View {
        let shadowYOffset: CGFloat = inverted ? -1 : 1
        let r = h * 0.33
        
        ZStack {
            // plaque
            Capsule(style: .continuous)
                .fill(plateFill)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Gold.edge.opacity(0.35), lineWidth: 0.8)
                )
                .frame(width: w, height: h)
                .position(x: cx, y: cy)
                .shadow(color: .black.opacity(0.30), radius: 2, x: 1, y: shadowYOffset)
            
            // filigree
            Path { p in
                if !inverted {
                    // TOP
                    p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                             startAngle: .degrees(200), endAngle: .degrees(-20), clockwise: false)
                    p.move(to: CGPoint(x: cx - r*0.8, y: cy))
                    p.addQuadCurve(to: CGPoint(x: cx, y: cy - r*0.9),
                                   control: CGPoint(x: cx - r*1.2, y: cy - r*0.7))
                    p.move(to: CGPoint(x: cx + r*0.8, y: cy))
                    p.addQuadCurve(to: CGPoint(x: cx, y: cy - r*0.9),
                                   control: CGPoint(x: cx + r*1.2, y: cy - r*0.7))
                } else {
                    // BOTTOM (mirror)
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
            .shadow(color: .black.opacity(0.20), radius: 1, x: 0, y: shadowYOffset)
        }
    }
    
    // MARK: crest (center by default; supports left/right)
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
            // top
            singleCrest(cx: cx, cy: rect.minY + h, width: w, height: h, inverted: false, plateFill: plateFill)
            // bottom
            singleCrest(cx: cx, cy: rect.maxY - h, width: w, height: h, inverted: true,  plateFill: plateFill)
        }
    }
}
