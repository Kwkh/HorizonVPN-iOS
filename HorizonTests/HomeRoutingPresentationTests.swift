import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Horizon

@MainActor struct HomeRoutingPresentationTests {
    @Test func routingCommitKeepsInteractionLockedUntilCompletion() async throws {
        let storage = PausedRoutingReadStorage()
        let repository = SubscriptionRepository(storage: storage)
        let prepared = try PrototypeConfiguration.prepare(Data(PrototypeSelfCheck.fixture.utf8))
        let id = try repository.add(.init(source: prepared.source, choices: prepared.catalog.choices),
            fileName: "Test.yaml", nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: true)
        let expected = try repository.record(id)
        let tunnel = TunnelController(repository: repository, permitsNetwork: false)
        await tunnel.refresh()
        storage.arm()
        defer { storage.release() }
        let operation = Task {
            await tunnel.applySubscriptionRevision(id, expected: expected, prepared: prepared,
                sourceURL: nil, reconnect: false, routingChange: true)
        }
        for _ in 0..<100 {
            if storage.entered { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(storage.entered)
        #expect(tunnel.isApplyingRouting && tunnel.isBusy)
        #expect(!tunnel.canManageSubscriptions && !tunnel.canTestPing && !tunnel.isIdle)
        storage.release()
        #expect(await operation.value)
        #expect(!tunnel.isApplyingRouting && !tunnel.isBusy)
        #expect(tunnel.canManageSubscriptions)
    }

    @Test func connectionPreparationKeepsNativePickerEnabledAndSelectionStable() async throws {
        let storage = PausedRoutingReadStorage()
        let repository = SubscriptionRepository(storage: storage)
        let prepared = try PrototypeConfiguration.prepare(Data(PrototypeSelfCheck.fixture.utf8))
        let id = try repository.add(.init(source: prepared.source, choices: prepared.catalog.choices),
            fileName: "Test.yaml", nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: true)
        let tunnel = TunnelController(repository: repository, permitsNetwork: false)
        await tunnel.refresh()
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let host = UIHostingController(rootView: HomeRoutingPickerView(tunnel: tunnel, id: id, visible: true).environment(settings))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 200)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; storage.release() }
        func picker(in view: UIView) -> UISegmentedControl? {
            if let control = view as? UISegmentedControl { return control }
            return view.subviews.lazy.compactMap { picker(in: $0) }.first
        }
        for _ in 0..<100 {
            host.view.layoutIfNeeded()
            if let control = picker(in: host.view), control.selectedSegmentIndex == 0 && control.isEnabled { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let control = try #require(picker(in: host.view))
        #expect(control.selectedSegmentIndex == 0 && control.isEnabled)
        storage.arm()
        let connection = Task { await tunnel.connectCurrentProfile() }
        for _ in 0..<100 {
            if storage.entered { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(storage.entered)
        #expect(tunnel.isBusy && !tunnel.canManageSubscriptions)
        // Give Observation and UIKit a full update while preparation is held open.
        try await Task.sleep(for: .milliseconds(100))
        host.view.layoutIfNeeded()
        #expect(control.isEnabled, "Temporary connection lock must not apply the native grey palette")
        #expect(control.selectedSegmentIndex == 0)
        #expect(picker(in: host.view) === control, "Do not recreate the segmented control on connect")
        storage.release()
        await connection.value
        try await Task.sleep(for: .milliseconds(100))
        #expect(control.isEnabled && control.selectedSegmentIndex == 0)
        #expect(try ConfigurationRouting.mode(in: repository.record(id).source) == .subscription)
    }
}

/// Holds only one worker read; tests never create a Network Extension or access Keychain.
nonisolated private final class PausedRoutingReadStorage: SubscriptionStorage, @unchecked Sendable {
    private let memory = MemorySubscriptionStorage()
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var armed = false
    private var didEnter = false
    var entered: Bool { lock.withLock { didEnter } }
    func arm() { lock.withLock { armed = true } }
    func release() { gate.signal() }
    func keys() throws -> [String] { try memory.keys() }
    func read(_ key: String) throws -> Data? {
        let pause = lock.withLock { if armed { armed = false; didEnter = true; return true }; return false }
        if pause {
            #expect(!Thread.isMainThread)
            _ = gate.wait(timeout: .now() + 5)
        }
        return try memory.read(key)
    }
    func write(_ data: Data, for key: String) throws { try memory.write(data, for: key) }
    func remove(_ key: String) throws { try memory.remove(key) }
}
