import Foundation
import CoreGraphics
import Observation

/// Records the local first-run experience, independent of credentials or VPN permissions.
@MainActor @Observable final class FirstLaunchExperience {
    private(set) var resolved = false
    private(set) var requestID: UUID?
    private(set) var skipRequested = false
    private(set) var isShowingGuide = false
    private(set) var isPreparingScene = false
    private(set) var guideRotation: Double?
    private(set) var guideTime: Double?
    private(set) var guideClock: HorizonSceneClock?
    private(set) var preparedSceneID: UUID?
    private(set) var needsVPNSetupOffer: Bool
    @ObservationIgnored private var offerAfterIntroduction = false
    var sceneFrame = CGRect.zero
    // Remain hidden through the guide, bridge, and entire cinematic, including
    // the unresolved startup frame so a fresh launch cannot flash the tab bar.
    var suppressesTabBar: Bool { !resolved || requestID != nil }
    // Network-related system initialization must not interrupt either intro stage
    // or race the first-run VPN setup offer. This is presentation state, not consent.
    var allowsNetworkMonitoring: Bool {
        resolved && requestID == nil && !needsVPNSetupOffer
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let preview: Bool
    private static let key = "launch.homeIntroductionCompleted.v1"
    private static let vpnOfferKey = "launch.vpnSetupOfferPending.v1"
    static var previewRequested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["CLASH_FIRST_LAUNCH_PREVIEW"] == "1"
        #else
        false
        #endif
    }

    init(defaults: UserDefaults = .standard, preview: Bool = false) {
        self.defaults = defaults
        self.preview = preview
        needsVPNSetupOffer = !preview && defaults.bool(forKey: Self.vpnOfferKey)
    }
    func resolve(hasExistingConfiguration: Bool, horizon: Bool) {
        guard !resolved else { return }
        // Older builds did not write a launch marker. Saved preferences/configuration
        // are migration evidence; an untouched old install cannot be distinguished.
        let hasExistingPreferences = defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix("ui.") || $0.hasPrefix("connection.")
        }
        let completed = defaults.bool(forKey: Self.key)
        if preview || (!completed && !hasExistingConfiguration && !hasExistingPreferences && horizon) {
            requestID = UUID()
            isShowingGuide = true
            offerAfterIntroduction = !preview
        } else if !completed { defaults.set(true, forKey: Self.key) }
        resolved = true
    }
    func skip() { skipRequested = true }
    func prepareScene(_ id: UUID, rotation: Double?, time: Double? = nil, clock: HorizonSceneClock? = nil) {
        guard requestID == id, isShowingGuide else { return }
        guideRotation = rotation
        guideTime = time
        guideClock = clock
        isPreparingScene = true
        preparedSceneID = nil
    }
    func scenePresented(_ id: UUID) {
        guard requestID == id, isPreparingScene else { return }
        preparedSceneID = id
    }
    func beginScene(_ id: UUID) {
        guard requestID == id, isPreparingScene, preparedSceneID == id else { return }
        isShowingGuide = false
        isPreparingScene = false
    }
    func complete(_ id: UUID) {
        guard requestID == id else { return }
        if offerAfterIntroduction {
            needsVPNSetupOffer = true
            defaults.set(true, forKey: Self.vpnOfferKey)
            offerAfterIntroduction = false
        }
        if !preview { defaults.set(true, forKey: Self.key) }
        requestID = nil
        skipRequested = false
        isShowingGuide = false
        isPreparingScene = false
        guideRotation = nil
        guideTime = nil
        guideClock = nil
        preparedSceneID = nil
    }
    func dismissVPNSetupOffer() {
        needsVPNSetupOffer = false
        if !preview { defaults.set(false, forKey: Self.vpnOfferKey) }
    }
    func replay() {
        offerAfterIntroduction = false
        skipRequested = false
        requestID = UUID()
        isShowingGuide = true
        isPreparingScene = false
        guideRotation = nil
        guideTime = nil
        guideClock = nil
        preparedSceneID = nil
    }
}
