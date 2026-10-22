import SwiftUI
import UIKit

/// Typography follows the oversized globe while staying clear of its silhouette.
struct HorizonTitleView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: String
    let progress: HorizonSceneProgress
    let viewport: CGSize
    @ScaledMetric(relativeTo: .caption) private var brandSize: CGFloat = 15
    @ScaledMetric(relativeTo: .title) private var statusSize: CGFloat = 28

    private struct Presentation: Equatable {
        let top: CGFloat
        let emphasis: CGFloat
        let brandHeight: CGFloat
        let statusHeight: CGFloat
        var brandScale: CGFloat { 1 + 0.08 * emphasis }
        var statusScale: CGFloat { 1 + 0.14 * emphasis }
        var height: CGFloat { brandHeight * brandScale + 9 + statusHeight * statusScale }
    }

    private var presentation: Presentation {
        let brandHeight = ceil(UIFont.systemFont(ofSize: brandSize, weight: .medium).lineHeight)
        let statusHeight = ceil(UIFont.systemFont(ofSize: statusSize, weight: .light).lineHeight)
        let baseline = Presentation(top: 22, emphasis: 0,
                                    brandHeight: brandHeight, statusHeight: statusHeight)
        guard viewport.width > 0, viewport.height > 0 else { return baseline }
        let aspect = Float(viewport.width / viewport.height)
        let sphere = HorizonGeometry.globe(scale: Float(settings.globeScale), aspect: aspect)
        let projection = HorizonGeometry.globeProjection(scale: Float(settings.globeScale), aspect: aspect)
        let t = min(1, max(0, CGFloat(projection.halfWidth - 1) / 0.45))
        let emphasis = t * t * (3 - 2 * t)
        let enlarged = Presentation(top: 22, emphasis: emphasis,
                                    brandHeight: brandHeight, statusHeight: statusHeight)
        let drop = CGFloat(max(0, 5.15 - sphere.y)) * viewport.height * 0.08 * emphasis
        let globeTop = CGFloat(1 - projection.top) * viewport.height / 2
        // Derive the destination from font metrics, never from an animating view's geometry.
        let availableDrop = max(0, globeTop - enlarged.height - 24 - 22)
        return Presentation(top: 22 + min(drop, availableDrop), emphasis: emphasis,
                            brandHeight: brandHeight, statusHeight: statusHeight)
    }

    var body: some View {
        let destination = presentation
        // Ease only the overlay. Metal keeps its original assembly and camera motion.
        // Delay the early displacement without a hold or a discontinuous start.
        // Quintic easing still brings speed and acceleration to zero at both endpoints.
        let rawProgress = min(1, max(0, CGFloat(progress.formation)))
        let t = pow(rawProgress, 1.4)
        let formation = t * t * t * (t * (t * 6 - 15) + 10)
        let presentation = Presentation(top: 22 + (destination.top - 22) * formation,
                                        emphasis: destination.emphasis * formation,
                                        brandHeight: destination.brandHeight, statusHeight: destination.statusHeight)
        VStack(spacing: 9) {
            Text("HORIZON")
                .font(.system(size: brandSize, weight: .medium))
                .tracking(6).foregroundStyle(.secondary)
                .frame(height: presentation.brandHeight)
                // Compensate for trailing tracking space so the visible glyphs are centered.
                .offset(x: 3)
                .scaleEffect(presentation.brandScale, anchor: .top)
                .frame(height: presentation.brandHeight * presentation.brandScale, alignment: .top)
            HorizonStatusText(status: status, fontSize: statusSize, lineHeight: presentation.statusHeight)
                .scaleEffect(presentation.statusScale, anchor: .top)
                .frame(height: presentation.statusHeight * presentation.statusScale, alignment: .top)
        }
        // Reserve horizontal clearance for the largest title, independent of its current text.
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
        .offset(y: presentation.top)
        // Remap the renderer progress directly, without a separate timer or trailing animation.
        // Only changing size preferences animates the destination itself.
        .animation(reduceMotion ? nil : .smooth(duration: 0.65), value: destination)
        .allowsHitTesting(false)
    }
}
