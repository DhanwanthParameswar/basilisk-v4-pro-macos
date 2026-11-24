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
                if wheelTilt != 0 { drawTiltedWheel(in: ctx, scale: fit.scale) }
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
                        // Wheel inputs keep just the outline so the wheel (and its tilt) stays readable.
                        if shape != ButtonShapes.wheel { ctx.fill(shape, with: .color(.accentColor.opacity(0.32))) }
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

    /// The wheel rocking sideways about its front–back axis, as seen from above: it doesn't rotate on
    /// screen. Its top surface slides toward the tilt and foreshortens, the far side wall comes into view
    /// as a dark strip, and the slot behind it shows through on the near side.
    private func drawTiltedWheel(in ctx: GraphicsContext, scale: CGFloat) {
        guard let led = MouseArtPaths.items.first(where: { $0.shape.layer == .wheelLED }) else { return }
        let t = CGFloat(wheelTilt)                       // -1 left … 1 right
        let wheel = led.path.boundingRect.insetBy(dx: -0.8, dy: -0.6)
        let squash = 1 - 0.14 * abs(t)                  // cos of a ~30° lean
        let shift = t * wheel.width * 0.16
        let surfaceW = wheel.width * squash
        let surface = CGRect(x: wheel.midX - surfaceW / 2 + shift, y: wheel.minY, width: surfaceW, height: wheel.height)
        let radius = wheel.width * 0.3

        // Recess of the slot, then the side wall revealed opposite the lean.
        ctx.fill(Path(roundedRect: wheel.insetBy(dx: -0.6, dy: 0), cornerRadius: radius), with: .color(Color(hex: 0x070707)))
        let wallW = abs(shift) + (wheel.width - surfaceW) / 2
        let wall = CGRect(x: t < 0 ? surface.maxX - radius * 0.5 : surface.minX - wallW + radius * 0.5,
                          y: wheel.minY + 1, width: wallW + radius * 0.5, height: wheel.height - 2)
        let dark = Color(hex: 0x0E0E0E), lit = Color(hex: 0x2C2C2C)
        ctx.fill(Path(roundedRect: wall, cornerRadius: radius * 0.8),
                 with: .linearGradient(Gradient(colors: t < 0 ? [lit, dark] : [dark, lit]),
                                       startPoint: CGPoint(x: wall.minX, y: wall.midY),
                                       endPoint: CGPoint(x: wall.maxX, y: wall.midY)))

        // Top surface: the wheel (ribs + LED) squashed toward the lean.
        ctx.drawLayer { layer in
            layer.clip(to: Path(roundedRect: surface, cornerRadius: radius * squash))
            layer.translateBy(x: surface.midX, y: 0)
            layer.scaleBy(x: squash, y: 1)
            layer.translateBy(x: -wheel.midX, y: 0)
            drawScene(in: layer, scale: scale)
        }
        // Light falls off on the side leaning away.
        ctx.fill(Path(roundedRect: surface, cornerRadius: radius * squash),
                 with: .linearGradient(Gradient(colors: t < 0 ? [.clear, .black.opacity(0.35)] : [.black.opacity(0.35), .clear]),
                                       startPoint: CGPoint(x: surface.minX, y: surface.midY),
                                       endPoint: CGPoint(x: surface.maxX, y: surface.midY)))
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
