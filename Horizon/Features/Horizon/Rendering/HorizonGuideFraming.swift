import CoreGraphics

/// A wide tablet must not expose the neighbouring chapter's stage.
/// Home's final viewport and every phone camera remain unchanged.
enum HorizonGuideFraming {
    static func viewport(_ frame: CGRect, tablet: Bool) -> CGRect {
        guard tablet else { return frame }
        let width = min(frame.width, frame.height * 1.15)
        return CGRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: frame.height)
    }
    static func visibility(chapter: Int, focus: Double, tablet: Bool) -> Double {
        guard tablet else { return 1 }
        let t = max(0, min(1, 1 - abs(Double(chapter) - focus)))
        return t * t * (3 - 2 * t)
    }
}
