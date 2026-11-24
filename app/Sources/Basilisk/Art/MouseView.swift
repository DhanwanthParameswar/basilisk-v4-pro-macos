import SwiftUI

/// The Basilisk V4 Pro, drawn natively from the Synapse artwork.
/// LED zones are painted in their live colours (with a soft glow) and can be clicked to select a zone.
struct MouseView: View, Animatable {
    var ledColors: [LightingZone: Color] = [:]
    var ledsOn = true
    var highlightedZone: LightingZone? = nil
    var highlightedButton: MouseButton? = nil
    var onTapZone: ((LightingZone) -> Void)? = nil
    var onTapButton: ((MouseButton) -> Void)? = nil
    /// -1…1: rocks the scroll wheel left/right (tilt inputs). Animatable so it springs into place.
    var wheelTilt: Double = 0

    var animatableData: Double {
        get { wheelTilt }
        set { wheelTilt = newValue }
    }

    @State private var hoverZone: LightingZone?
    @State private var hoverButton: MouseButton?

    var body: some View {
        GeometryReader { geo in
            let fit = Self.fit(in: geo.size)
            Canvas { ctx, _ in
                ctx.translateBy(x: fit.origin.x, y: fit.origin.y)
                ctx.scaleBy(x: fit.scale, y: fit.scale)

                drawScene(in: ctx, scale: fit.scale)
                // Tilt: clear the wheel's slot, then redraw the wheel rocked inside it.
                if wheelTilt != 0 {
                    let slot = ButtonShapes.wheel
                    let c = CGPoint(x: slot.boundingRect.midX, y: slot.boundingRect.midY)
                    ctx.fill(slot, with: .color(Color(hex: 0x0B0B0B)))
                    ctx.drawLayer { layer in
                        layer.clip(to: slot)
                        layer.translateBy(x: c.x + wheelTilt * 2.2, y: c.y)
                        layer.rotate(by: .degrees(wheelTilt * 7))
                        layer.translateBy(x: -c.x, y: -c.y)
                        drawScene(in: layer, scale: fit.scale)
                    }
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
                if let b = hoverButton, let shape = b.shape, shape != highlightedButton?.shape {
                    ctx.stroke(shape, with: .color(.white.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }
                if let b = highlightedButton {
                    if let shape = b.shape {
                        ctx.fill(shape, with: .color(.accentColor.opacity(0.32)))
                        ctx.stroke(shape, with: .color(.accentColor),
                                   style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    } else if b == .hypershift {
                        drawCallout(in: ctx)
                    }
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

    /// Body and LEDs (everything except selection/highlight overlays).
    private func drawScene(in ctx: GraphicsContext, scale: CGFloat) {
        var ctx = ctx
        for item in MouseArtPaths.items where item.shape.layer == .body {
            draw(item, in: &ctx)
        }
        if ledsOn {
            var glow = ctx
            glow.addFilter(.blur(radius: 6 / max(scale, 0.5)))
            for item in MouseArtPaths.items where item.shape.isLED {
                glow.fill(item.path, with: .color(color(for: item.shape).opacity(0.9)))
            }
        }
        for item in MouseArtPaths.items where item.shape.isLED {
            let c = ledsOn ? color(for: item.shape) : Color(hex: 0x2A2A2A)
            ctx.fill(item.path, with: .color(c))
        }
    }

    /// Arrow pointing at a control that's out of view from above (the thumb trigger).
    private func drawCallout(in ctx: GraphicsContext) {
        let (from, to) = ButtonShapes.hypershiftCallout
        let angle = atan2(to.y - from.y, to.x - from.x)
        var arrow = Path()
        arrow.move(to: from)
        arrow.addLine(to: to)
        for side in [-1.0, 1.0] {
            let a = angle + .pi + side * 0.5
            arrow.move(to: CGPoint(x: to.x + cos(a) * 6, y: to.y + sin(a) * 6))
            arrow.addLine(to: to)
        }
        ctx.stroke(arrow, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: to.x - 2.5, y: to.y - 2.5, width: 5, height: 5)), with: .color(.accentColor))
    }

    /// Chevron on the wheel showing scroll direction.
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
        return MouseButton.hitOrder.first { $0.shape?.contains(p) ?? false }
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
