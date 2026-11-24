import SwiftUI

/// Outline of each physical button on the artwork (canvas coordinates, 200 × 320).
/// Right click and the wheel come straight from Razer's drawing; the rest were traced over it.
enum ButtonShapes {
    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private static func polygon(_ pts: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(pts)
        path.closeSubpath()
        return path
    }

    static let rightClick = MouseArtPaths.parse("M162.5,80.7L162.2,76.1L161.8,71.6L161.2,67.1L160.5,62.6L159.7,58.1L158.9,53.9L158.9,53.9L158.6,52.6L158.6,52.6L158.1,50.2L158.1,50.2L157.5,47.2L157.5,47.2L157.4,46.6L157.1,45.8L156.6,45L156,44.3L155.3,43.7L154.6,43.2L153.7,42.7L153.7,42.7L148.4,40.2L142.5,37.3L142.7,36.9L142.5,37.3L129.6,30.8L126.4,29.2L125.6,28.9L124.9,28.8L124.6,28.8L124,28.8L123.5,28.9L123.1,29.1L122.6,29.6L122.4,30L122.3,30.5L122.3,31L122.3,143.5C122.3,144.6,122.9,145.6,123.8,146.2C124.7,146.8,125.9,146.8,126.9,146.4L155.5,132.5L155.5,132.5L156.2,132.1L157,131.5L157.7,130.8L158.3,130L158.8,129.1L159.2,128.1L159.5,126.8L160.4,121.3L161.2,115.7L161.8,110.3L162.3,105.1L162.6,100L162.8,95.1L162.9,90.3L162.8,85.6L162.5,80.7Z")
    static let wheel = MouseArtPaths.parse("M106.1,119L114.9,119C117.7,119,120,116.7,120,113.9L120,67.1C120,64.3,117.7,62,114.9,62L106.1,62C103.3,62,101,64.3,101,67.1L101,113.9C101,116.7,103.3,119,106.1,119Z")
    static let leftClick = polygon([p(76, 45), p(97, 35), p(101, 36), p(102, 40), p(102, 153), p(99, 159), p(95, 162), p(66, 176), p(62, 173), p(59, 163), p(55, 140), p(54, 112), p(57, 80), p(70, 73.5), p(72, 71), p(75, 52)])
    /// The "M1 edge" button notched into the left click.
    static let profile = polygon([p(61, 51), p(75, 45.5), p(73, 68), p(71, 72), p(57, 79.5), p(58, 60)])
    static let scrollMode = Path(roundedRect: CGRect(x: 105.5, y: 125, width: 11.5, height: 12), cornerRadius: 2)
    static let sensitivity = polygon([p(105.5, 141), p(117, 141), p(117, 149), p(107.5, 155), p(105.5, 154)])
    /// Thumb side, front to back.
    static let hypershift = polygon([p(26.5, 140), p(43, 126.5), p(43.5, 140), p(41, 143), p(27, 143.5)])
    static let aiPrompt = polygon([p(43, 115), p(46.5, 113.5), p(46.5, 142.5), p(44.5, 144), p(43, 139)])
    static let forward = polygon([p(45, 143), p(49, 142.5), p(50.5, 172), p(48, 175), p(46, 171.5), p(45, 150)])
    static let back = polygon([p(48, 175.5), p(50.5, 173.5), p(55, 187), p(57, 204), p(55.5, 205.5), p(49, 199), p(47, 186)])
}

extension MouseButton {
    /// The part of the mouse this button lives on.
    var shape: Path {
        switch self {
        case .left: ButtonShapes.leftClick
        case .right: ButtonShapes.rightClick
        case .wheelClick, .wheelUp, .wheelDown, .tiltLeft, .tiltRight: ButtonShapes.wheel
        case .scrollMode: ButtonShapes.scrollMode
        case .sensitivity: ButtonShapes.sensitivity
        case .profile: ButtonShapes.profile
        case .hypershift: ButtonShapes.hypershift
        case .aiPrompt: ButtonShapes.aiPrompt
        case .forward: ButtonShapes.forward
        case .back: ButtonShapes.back
        }
    }

    /// Direction cue drawn on the wheel for scroll/tilt inputs (radians, 0 = right).
    var wheelArrow: Double? {
        switch self {
        case .wheelUp: -.pi / 2
        case .wheelDown: .pi / 2
        case .tiltLeft: .pi
        case .tiltRight: 0
        default: nil
        }
    }

    /// Hit-test order: small parts first so they win over the large click surfaces around them.
    static let hitOrder: [MouseButton] = [.profile, .scrollMode, .sensitivity, .hypershift, .aiPrompt,
                                          .forward, .back, .wheelClick, .left, .right]
}
