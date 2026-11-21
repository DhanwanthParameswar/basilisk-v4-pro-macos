import SwiftUI

/// The Basilisk V4 Pro, drawn natively from the Synapse artwork.
/// LED zones are painted in their live colours (with a soft glow) and can be clicked to select a zone.
struct MouseView: View {
    var ledColors: [LightingZone: Color] = [:]
    var ledsOn = true
    var highlightedZone: LightingZone? = nil
    var highlightedPoint: CGPoint? = nil
    var markers: [CGPoint] = []
    var onTapZone: ((LightingZone) -> Void)? = nil

    @State private var hoverZone: LightingZone?

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
                // 4. Button markers
                for p in markers {
                    let r: CGFloat = 4.5
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(0.85)))
                }
                if let p = highlightedPoint {
                    let r: CGFloat = 7
                    let ring = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    ctx.fill(ring, with: .color(.accentColor))
                    ctx.stroke(ring, with: .color(.white), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard onTapZone != nil else { return }
                switch phase {
                case .active(let loc): hoverZone = zone(at: loc, fit: fit)
                case .ended: hoverZone = nil
                }
            }
            .onTapGesture { loc in
                if let z = zone(at: loc, fit: fit) { onTapZone?(z) }
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
