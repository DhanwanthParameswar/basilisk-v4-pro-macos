import SwiftUI

/// The Basilisk V4 Pro, drawn natively from the Synapse artwork.
/// LED zones are painted in their live colours (with a soft glow) and can be clicked to select a zone.
struct MouseView: View {
    var ledColors: [LightingZone: Color] = [:]
    var ledsOn = true
    var highlightedZone: LightingZone? = nil
    var highlightedButton: MouseButton? = nil
    var onTapZone: ((LightingZone) -> Void)? = nil
    var onTapButton: ((MouseButton) -> Void)? = nil

    @State private var hoverZone: LightingZone?
    @State private var hoverButton: MouseButton?

    var body: some View {
        GeometryReader { geo in
            let fit = Self.fit(in: geo.size)
            Canvas { ctx, _ in
                ctx.translateBy(x: fit.origin.x, y: fit.origin.y)
                ctx.scaleBy(x: fit.scale, y: fit.scale)

                // 1. Body
                for item in MouseArtPaths.items where item.shape.layer == .body {
                    draw(item, in: &ctx)
                }
                // 2. LEDs: glow pass, then crisp pass
                if ledsOn {
                    var glow = ctx
                    glow.addFilter(.blur(radius: 6 / max(fit.scale, 0.5)))
                    for item in MouseArtPaths.items where item.shape.isLED {
                        glow.fill(item.path, with: .color(color(for: item.shape).opacity(0.9)))
                    }
                }
                for item in MouseArtPaths.items where item.shape.isLED {
                    let c = ledsOn ? color(for: item.shape) : Color(hex: 0x2A2A2A)
                    ctx.fill(item.path, with: .color(c))
                }
                // 3. Selection / hover outline
                let outlined = hoverZone ?? highlightedZone
                if let z = outlined {
                    for item in MouseArtPaths.items where item.shape.isSelection && item.shape.zone == z {
                        ctx.stroke(item.path, with: .color(.accentColor),
                                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    }
                }
                // 4. Buttons: hover hint, then the selected part
                if let b = hoverButton, b.shape != highlightedButton?.shape {
                    ctx.stroke(b.shape, with: .color(.white.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }
                if let b = highlightedButton {
                    ctx.fill(b.shape, with: .color(.accentColor.opacity(0.32)))
                    ctx.stroke(b.shape, with: .color(.accentColor),
                               style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    if let angle = b.wheelArrow { drawArrow(angle: angle, in: ctx) }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard onTapZone != nil || onTapButton != nil else { return }
                switch phase {
                case .active(let loc):
                    hoverZone = zone(at: loc, fit: fit)
                    hoverButton = button(at: loc, fit: fit)
                case .ended:
                    hoverZone = nil
                    hoverButton = nil
                }
            }
            .onTapGesture { loc in
                if let z = zone(at: loc, fit: fit) { onTapZone?(z) }
                if let b = button(at: loc, fit: fit) { onTapButton?(b) }
            }
            .accessibilityElement()
            .accessibilityLabel("Razer Basilisk V4 Pro")
        }
        .aspectRatio(MouseArtwork.canvas.width / MouseArtwork.canvas.height, contentMode: .fit)
    }

    private func draw(_ item: MouseArtPaths.Item, in ctx: inout GraphicsContext) {
        let s = item.shape
        if let f = s.fill { ctx.fill(item.path, with: .color(Color(hex: f, opacity: s.opacity))) }
        if let st = s.stroke, s.strokeWidth > 0 {
            ctx.stroke(item.path, with: .color(Color(hex: st, opacity: s.opacity)), lineWidth: s.strokeWidth)
        }
    }

    private func color(for s: ArtShape) -> Color {
        guard let z = s.zone else { return .clear }
        return ledColors[z] ?? RGB.razerGreen.color
    }

    /// Chevron on the wheel showing scroll / tilt direction.
    private func drawArrow(angle: Double, in ctx: GraphicsContext) {
        let c = ButtonShapes.wheel.boundingRect
        let center = CGPoint(x: c.midX, y: c.midY)
        let tip = CGPoint(x: center.x + cos(angle) * 9, y: center.y + sin(angle) * 9)
        var arrow = Path()
        for side in [-1.0, 1.0] {
            let a = angle + .pi + side * 0.6
            arrow.move(to: CGPoint(x: tip.x + cos(a) * 6, y: tip.y + sin(a) * 6))
            arrow.addLine(to: tip)
        }
        ctx.stroke(arrow, with: .color(.white), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
    }

    private func button(at point: CGPoint, fit: (origin: CGPoint, scale: CGFloat)) -> MouseButton? {
        guard onTapButton != nil else { return nil }
        let p = CGPoint(x: (point.x - fit.origin.x) / fit.scale, y: (point.y - fit.origin.y) / fit.scale)
        return MouseButton.hitOrder.first { $0.shape.contains(p) }
    }

    private func zone(at point: CGPoint, fit: (origin: CGPoint, scale: CGFloat)) -> LightingZone? {
        guard onTapZone != nil else { return nil }
        let p = CGPoint(x: (point.x - fit.origin.x) / fit.scale, y: (point.y - fit.origin.y) / fit.scale)
        for item in MouseArtPaths.items where item.shape.isSelection || item.shape.isLED {
            if item.path.boundingRect.insetBy(dx: -4, dy: -4).contains(p) { return item.shape.zone }
        }
        return nil
    }

    static func fit(in size: CGSize) -> (origin: CGPoint, scale: CGFloat) {
        let c = MouseArtwork.canvas
        // The artwork's drawing occupies roughly x 20…195 of the 200-wide canvas; centre on that.
        let scale = min(size.width / c.width, size.height / c.height)
        return (CGPoint(x: (size.width - c.width * scale) / 2 - 8 * scale, y: (size.height - c.height * scale) / 2), scale)
    }
}
