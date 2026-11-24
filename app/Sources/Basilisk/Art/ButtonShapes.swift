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

    /// The multi-function trigger (Hypershift) is on the side wall above the thumb buttons, so it can't
    /// be seen from above. Mark its spot with a slim capsule hugging the outside of the left edge there
    /// (the edge runs x 47.75 → 46.5 over y 96 → 111 in the artwork).
    static let hypershiftMarker: Path = {
        let length: CGFloat = 14, width: CGFloat = 2.4
        let capsule = Path(roundedRect: CGRect(x: -width / 2, y: -length / 2, width: width, height: length),
                           cornerRadius: width / 2)
        let tilt = atan2(-1.25, 15.0)                    // follow the edge's slope
        return capsule
            .applying(CGAffineTransform(rotationAngle: -tilt))
            .applying(CGAffineTransform(translationX: 45.5, y: 103.5))
    }()
}

extension MouseButton {
    /// The part of the mouse this button lives on.
    var shape: Path? {
        switch self {
        case .wheelClick, .wheelUp, .wheelDown, .tiltLeft, .tiltRight: ButtonShapes.wheel
        case .hypershift: ButtonShapes.hypershiftMarker
        default: ButtonShapes.faces[self]
        }
    }

    /// Roll direction of the wheel for scroll inputs: -1 rolls the top surface forward (up), 1 back (down).
    var wheelRoll: Double? {
        switch self {
        case .wheelUp: -1
        case .wheelDown: 1
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
    static let hitOrder: [MouseButton] = [.hypershift, .profile, .scrollMode, .sensitivity, .aiPrompt,
                                          .forward, .back, .wheelClick, .left, .right]
}
