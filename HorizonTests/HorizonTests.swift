//
//  HorizonTests.swift
//  HorizonTests
//
//  Created by 吴铠涵 on 2026/10/1.
//

import Testing
import Foundation
@testable import Horizon

struct HorizonTests {
    @MainActor @Test func singleNodeContractAndRefusals() {
        let result = PrototypeSelfCheck.run()
        #expect(result.failures.isEmpty)
        #expect(result.passed == result.total)
    }

    @MainActor @Test func diagnosticFailureIsExplicit() {
        let error = TunnelDiagnostics.startupError()
        #expect(error.domain == TunnelDiagnostics.errorDomain)
        #expect(error.code == 1001)
        #expect(TunnelDiagnostics.safeErrorSummary(error).contains("内核未接入"))
    }

    @MainActor @Test func foreignErrorsDoNotExposeCredentials() {
        let error = NSError(domain: "https://example.invalid/token=FAKE_SECRET", code: 42,
                            userInfo: [NSLocalizedDescriptionKey: "FAKE_PASSWORD"])
        let summary = TunnelDiagnostics.safeErrorSummary(error)
        #expect(!summary.contains("FAKE"))
        #expect(!summary.contains("example.invalid"))
        #expect(summary.contains("42"))
    }

}
