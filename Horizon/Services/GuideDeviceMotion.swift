import CoreMotion
import Observation
import UIKit
import simd

/// Owned by the guide scene only; no recording, global observer, or motion on the home page.
@MainActor @Observable final class GuideDeviceMotion {
    private(set) var offset = SIMD2<Float>.zero
    // Desktop hosts have no device tilt input. Avoid creating Core Motion's
    // internal motion thread there; pointer gestures still move the scene.
    @ObservationIgnored private let manager: CMMotionManager? = {
        #if targetEnvironment(macCatalyst) || os(macOS)
        return nil
        #else
        guard !ProcessInfo.processInfo.isiOSAppOnMac else { return nil }
        return CMMotionManager()
        #endif
    }()
    @ObservationIgnored private var filter = GuideTiltFilter()
    @ObservationIgnored private var generation = UUID()

    func run(enabled: Bool) async {
        guard enabled, let manager, manager.isDeviceMotionAvailable else { return }
        let currentGeneration = UUID()
        generation = currentGeneration
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        defer {
            if generation == currentGeneration { manager.stopDeviceMotionUpdates() }
        }
        var neutral = GuideTiltNeutral()
        var orientation = UIInterfaceOrientation.unknown
        var lastTime = ProcessInfo.processInfo.systemUptime
        // Keep the rendered offset on suspension; rebase the sensor on return and
        // smoothly settle to its new neutral instead of snapping the camera.
        while !Task.isCancelled && generation == currentGeneration {
            do { try await Task.sleep(for: .seconds(1.0 / 30)) } catch { break }
            guard !Task.isCancelled, generation == currentGeneration else { break }
            let now = ProcessInfo.processInfo.systemUptime
            let delta = now - lastTime
            lastTime = now
            guard let motion = manager.deviceMotion, now - motion.timestamp < 0.5 else { continue }
            let q = motion.attitude.quaternion
            let attitude = simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w)
            let nextOrientation = (UIApplication.shared.connectedScenes.first {
                $0.activationState == .foregroundActive
            } as? UIWindowScene)?.effectiveGeometry.interfaceOrientation ?? .portrait
            if orientation != nextOrientation {
                neutral.reset(to:attitude)
                orientation = nextOrientation
            }
            let rate = motion.rotationRate
            neutral.update(sample:attitude,angularSpeed:simd_length(SIMD3(rate.x,rate.y,rate.z)),delta:delta)
            var relative = neutral.attitude.inverse * attitude
            if relative.real < 0 { relative = simd_quatd(vector: -relative.vector) }
            var angles = SIMD2(relative.imag.y, -relative.imag.x) * 2
            switch orientation {
            case .landscapeLeft: angles = [-angles.y, angles.x]
            case .landscapeRight: angles = [angles.y, -angles.x]
            case .portraitUpsideDown: angles = -angles
            default: break
            }
            let filtered = filter.update(angles: angles, delta: delta, recentering: neutral.isRecentering)
            offset = SIMD2(Float(filtered.x), Float(filtered.y))
        }
    }
}
