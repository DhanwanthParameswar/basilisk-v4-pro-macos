import SwiftUI

/// Where each physical button is on the artwork. The faces come from the `Buttons` layer added to
/// `assets/mouse/basilisk_v4_pro_lighting.svg` (Razer's asset has none). The wheel's face is the ribbed
/// wheel itself, not Razer's padded selection box.
enum ButtonShapes {
    static let faces: [MouseButton: Path] = Dictionary(uniqueKeysWithValues:
        MouseArtPaths.items.compactMap { item in
            guard item.shape.layer == .button, let b = MouseButton(rawValue: UInt8(item.shape.index)) else { return nil }
            return (b, item.path)
        })

    static let wheel: Path = faces[.wheelClick]!

    /// The multi-function trigger sits under the thumb and isn't visible from above: point at it instead.
    static let hypershiftCallout = (from: CGPoint(x: 8, y: 116), to: CGPoint(x: 27, y: 136))
}

extension MouseButton {
    /// The part of the mouse this button lives on (nil when it can't be seen from above).
    var shape: Path? {
        switch self {
        case .wheelClick, .wheelUp, .wheelDown, .tiltLeft, .tiltRight: ButtonShapes.wheel
        default: ButtonShapes.faces[self]
        }
    }

    /// Direction cue drawn on the wheel for scroll inputs (radians, 0 = right).
    var wheelArrow: Double? {
        switch self {
        case .wheelUp: -.pi / 2
        case .wheelDown: .pi / 2
        default: nil
        }
    }

    /// -1 / +1 rocks the wheel left / right on the artwork.
    var wheelTilt: Double {
        switch self {
        case .tiltLeft: -1
        case .tiltRight: 1
        default: 0
        }
    }

    /// Hit-test order: small parts first so they win over the large click surfaces around them.
    static let hitOrder: [MouseButton] = [.profile, .scrollMode, .sensitivity, .aiPrompt,
                                          .forward, .back, .wheelClick, .left, .right]
}
