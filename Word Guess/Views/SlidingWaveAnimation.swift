import SwiftUI

// MARK: API

public enum SlideEdge: Sendable { case leading, trailing, top, bottom }

public extension View {
    /// Full color when `isEmptying == false`. When it becomes true, plays a one-shot fluid emptying to `cleanColor`.
    func fluidEmptyingBackground(
        gradient: LinearGradient,
        isEmptying: Binding<Bool>,
        duration: Double = 1.2,
        edge: SlideEdge = .top,
        cleanColor: Color = .white,
        waveAmplitude: CGFloat = 18,
        waveLength: CGFloat = 140,
        waveCyclesDuringWipe: Double = 2.0,
        edgeHighlight: Double = 0.35,
        cornerRadius: CGFloat? = nil,
        overdraw: CGFloat = 5
    ) -> some View {
        background(
            FluidEmptyingLayer(
                gradient: gradient,
                isEmptying: isEmptying,
                duration: duration,
                edge: edge,
                cleanColor: cleanColor,
                waveAmplitude: waveAmplitude,
                waveLength: waveLength,
                waveCyclesDuringWipe: waveCyclesDuringWipe,
                edgeHighlight: edgeHighlight,
                cornerRadius: cornerRadius,
                overdraw: overdraw
            )
            .allowsHitTesting(false)
        )
    }
}

// MARK: Layer

private struct FluidEmptyingLayer: View {
    let gradient: LinearGradient
    @Binding var isEmptying: Bool
    let duration: Double
    let edge: SlideEdge
    let cleanColor: Color
    let waveAmplitude: CGFloat
    let waveLength: CGFloat
    let waveCyclesDuringWipe: Double
    let edgeHighlight: Double
    let cornerRadius: CGFloat?
    let overdraw: CGFloat
    
    @State private var progress: CGFloat = 0   // 0 full, 1 empty
    @State private var phase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            let sz = geo.size
            let done = progress >= 0.999
            
            ZStack {
                Rectangle().fill(cleanColor) // revealed base
                
                if !done {
                    // gradient only where paint remains
                    gradient
                        .frame(width: sz.width, height: sz.height)
                        .mask(
                            RemainingPaint(
                                progress: progress,
                                phase: phase,
                                amplitude: amplitude(for: progress),
                                wavelength: waveLength,
                                edge: edge,
                                overdraw: overdraw
                            ).fill(.black)
                        )
                    
                    if edgeHighlight > 0 {
                        RemainingPaint(
                            progress: progress,
                            phase: phase,
                            amplitude: amplitude(for: progress),
                            wavelength: waveLength,
                            edge: edge,
                            overdraw: overdraw
                        )
                        .stroke(cleanColor.opacity(edgeHighlight), lineWidth: 2)
                        .blur(radius: 3)
                        .blendMode(.plusLighter)
                    }
                }
            }
            .frame(width: sz.width, height: sz.height)
            .modifier(ClipIfNeeded(radius: cornerRadius))  // ✅ no AnyShape
        }
        // run on first render and each toggle
        .task(id: isEmptying) { start(isEmptying) }
        // ensure progress animates even if parent disables animations elsewhere
        .animation(.easeInOut(duration: duration), value: progress)
    }
    
    private func start(_ empty: Bool) {
        // Always reset visually to "full paint" first
        progress = 0
        phase = 0
        guard empty else { return }
        
        // Next runloop so SwiftUI sees 0→1 change to animate
        DispatchQueue.main.async {
            progress = 1
            withAnimation(.linear(duration: duration)) {
                phase = .pi * 2 * waveCyclesDuringWipe
            }
        }
    }
    
    private func amplitude(for p: CGFloat) -> CGFloat {
        // fade-in amplitude so p==0 shows zero white
        waveAmplitude * min(1, max(0, p * 1.5))
    }
}

// MARK: Mask shape (remaining paint), with overdraw to kill corner bleed

private struct RemainingPaint: Shape {
    var progress: CGFloat     // 0 full, 1 empty
    var phase: CGFloat
    var amplitude: CGFloat
    var wavelength: CGFloat
    var edge: SlideEdge
    var overdraw: CGFloat
    
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(Double(progress), Double(phase)) }     // ✅ no .map
        set { progress = CGFloat(newValue.first); phase = CGFloat(newValue.second) }
    }
    
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let λ = max(8, wavelength)
        let steps = max(24, Int(((edge == .leading || edge == .trailing) ? h : w) / 5))
        let τ: CGFloat = .pi * 2
        
        switch edge {
        case .top:
            // remaining paint is BELOW the wave
            func Y(_ x: CGFloat) -> CGFloat {
                let base = h * progress
                let s = sin((x/λ)*τ + phase) + 0.35 * sin((x/(λ*0.6))*τ + phase*0.6)
                return min(max(base + amplitude*s, -overdraw), h + overdraw)
            }
            p.move(to: .init(x: 0, y: h + overdraw))
            p.addLine(to: .init(x: w, y: h + overdraw))
            for i in stride(from: steps, through: 0, by: -1) {
                let x = w * CGFloat(i) / CGFloat(steps)
                p.addLine(to: .init(x: x, y: Y(x)))
            }
            p.addLine(to: .init(x: 0, y: Y(0)))
            p.closeSubpath()
            
        case .bottom:
            func Y(_ x: CGFloat) -> CGFloat {
                let base = h * (1 - progress)
                let s = sin((x/λ)*τ + phase) + 0.35 * sin((x/(λ*0.6))*τ + phase*0.6)
                return min(max(base + amplitude*s, -overdraw), h + overdraw)
            }
            p.move(to: .init(x: 0, y: -overdraw))
            p.addLine(to: .init(x: w, y: -overdraw))
            for i in 0...steps {
                let x = w * CGFloat(i) / CGFloat(steps)
                p.addLine(to: .init(x: x, y: Y(x)))
            }
            p.addLine(to: .init(x: 0, y: Y(0)))
            p.closeSubpath()
            
        case .leading:
            func X(_ y: CGFloat) -> CGFloat {
                let base = w * progress
                let s = sin((y/λ)*τ + phase) + 0.35 * sin((y/(λ*0.6))*τ + phase*0.6)
                return min(max(base + amplitude*s, -overdraw), w + overdraw)
            }
            p.move(to: .init(x: w + overdraw, y: 0))
            p.addLine(to: .init(x: w + overdraw, y: h))
            for i in stride(from: steps, through: 0, by: -1) {
                let y = h * CGFloat(i) / CGFloat(steps)
                p.addLine(to: .init(x: X(y), y: y))
            }
            p.addLine(to: .init(x: X(0), y: 0))
            p.closeSubpath()
            
        case .trailing:
            func X(_ y: CGFloat) -> CGFloat {
                let base = w * (1 - progress)
                let s = sin((y/λ)*τ + phase) + 0.35 * sin((y/(λ*0.6))*τ + phase*0.6)
                return min(max(base + amplitude*s, -overdraw), w + overdraw)
            }
            p.move(to: .init(x: -overdraw, y: 0))
            p.addLine(to: .init(x: -overdraw, y: h))
            for i in 0...steps {
                let y = h * CGFloat(i) / CGFloat(steps)
                p.addLine(to: .init(x: X(y), y: y))
            }
            p.addLine(to: .init(x: X(0), y: 0))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: Small helper – clip only when you have a radius (no AnyShape)

private struct ClipIfNeeded: ViewModifier {
    let radius: CGFloat?
    func body(content: Content) -> some View {
        if let r = radius { content.clipShape(RoundedRectangle(cornerRadius: r, style: .continuous)) }
        else { content }
    }
}
