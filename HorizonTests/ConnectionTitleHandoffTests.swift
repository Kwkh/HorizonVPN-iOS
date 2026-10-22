import Foundation
import NetworkExtension
import Testing
@testable import Horizon

@MainActor struct ConnectionTitleHandoffTests {
    @Test func delayedSystemHandoffDoesNotReturnToDisconnected() {
        var handoff = ConnectionTitleHandoff()
        var titles: [NEVPNStatus] = [.disconnected]
        func append(_ status: NEVPNStatus) {
            if titles.last != status { titles.append(status) }
        }
        let ticket = handoff.begin()
        append(handoff.titleStatus(system: .disconnected, preparing: true))
        handoff.enqueue(ticket)
        handoff.preparationEnded(ticket) // Async revision task has not run yet.
        append(handoff.titleStatus(system: .disconnected, preparing: false))
        handoff.submit()
        for _ in 0..<3 {
            handoff.observe(.disconnected) // Stale synchronous system reads.
            append(handoff.titleStatus(system: .disconnected, preparing: false))
        }
        handoff.observe(.connecting, notification: true)
        append(handoff.titleStatus(system: .connecting, preparing: false))
        handoff.observe(.connected, notification: true)
        append(handoff.titleStatus(system: .connected, preparing: false))
        #expect(titles == [.disconnected, .connecting, .connected])
        #expect(!handoff.isPending)
    }

    @Test func profilePreparationNotificationsDoNotEndTheRequest() {
        var handoff = ConnectionTitleHandoff()
        _ = handoff.begin()
        handoff.observe(.invalid, notification: true)
        handoff.observe(.disconnected, notification: true)
        #expect(handoff.isPending)
        #expect(handoff.titleStatus(system: .invalid, preparing: true) == .connecting)
    }

    @Test func deniedPermissionOrPreparationFailureReturnsToRealStatus() {
        var handoff = ConnectionTitleHandoff()
        let ticket = handoff.begin()
        handoff.preparationEnded(ticket)
        #expect(!handoff.isPending)
        #expect(handoff.titleStatus(system: .disconnected, preparing: false) == .disconnected)
    }

    @Test func rejectedSubmittedStartDoesNotStayConnecting() {
        var handoff = ConnectionTitleHandoff()
        let ticket = handoff.begin()
        handoff.enqueue(ticket)
        handoff.submit()
        handoff.observe(.disconnected, notification: true)
        #expect(!handoff.isPending)
    }

    @Test func synchronousErrorCancellationAndTimeoutReleaseTheBridge() {
        for submitted in [false, true] {
            var handoff = ConnectionTitleHandoff()
            let ticket = handoff.begin()
            handoff.enqueue(ticket)
            if submitted { handoff.submit() }
            handoff.finish(ticket)
            #expect(!handoff.isPending)
            #expect(handoff.titleStatus(system: .disconnected, preparing: false) == .disconnected)
        }
    }

    @Test func lateCompletionFromAnOlderAttemptCannotClearANewAttempt() {
        var handoff = ConnectionTitleHandoff()
        let old = handoff.begin()
        handoff.finish(old)
        let current = handoff.begin()
        handoff.enqueue(current)
        handoff.finish(old)
        handoff.preparationEnded(old)
        #expect(handoff.id == current)
    }

    @Test func realSystemStatesTakePriorityEvenWhilePreparationIsFinishing() {
        var handoff = ConnectionTitleHandoff()
        _ = handoff.begin()
        for status in [NEVPNStatus.connecting, .connected, .reasserting, .disconnecting] {
            #expect(handoff.titleStatus(system: status, preparing: true) == status)
        }
    }

    @Test func realFailureAfterHandoffIsNotHidden() {
        var handoff = ConnectionTitleHandoff()
        let ticket = handoff.begin()
        handoff.enqueue(ticket)
        handoff.submit()
        handoff.observe(.connecting)
        handoff.observe(.disconnected, notification: true)
        #expect(handoff.titleStatus(system: .disconnected, preparing: false) == .disconnected)
    }
}
