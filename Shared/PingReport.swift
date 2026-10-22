import Foundation

/// The extension returns only a fixed outcome and a bounded duration.
struct PingReport: Codable, Equatable {
    // Match this user's Clash Verge 2.5.2 defaults (no URL or timeout override).
    static let testURL = "http://cp.cloudflare.com/generate_204"
    static let timeoutMilliseconds: Int32 = 10_000
    static let responseTimeout = TimeInterval(timeoutMilliseconds) / 1_000

    enum Outcome: String, Codable {
        case success, failed, timedOut, busy, unavailable
    }

    let outcome: Outcome
    let milliseconds: Int32?

    init(outcome: Outcome, milliseconds: Int32? = nil) {
        if outcome == .success {
            if let milliseconds, (1...65535).contains(milliseconds) {
                self.outcome = milliseconds < Self.timeoutMilliseconds ? .success : .timedOut
                self.milliseconds = self.outcome == .success ? milliseconds : nil
            } else {
                self.outcome = .failed
                self.milliseconds = nil
            }
        } else {
            self.outcome = outcome
            self.milliseconds = nil
        }
    }

    init(coreDelay: Int32) {
        self.init(outcome: .success, milliseconds: coreDelay)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(outcome: try values.decode(Outcome.self, forKey: .outcome),
                  milliseconds: try values.decodeIfPresent(Int32.self, forKey: .milliseconds))
    }

    var summary: String {
        switch outcome {
        case .success: "\(milliseconds ?? 0) ms"
        case .failed: "请求失败或超时"
        case .timedOut: "等待测试结果超时"
        case .busy: "内核正在执行另一项测试"
        case .unavailable: "测试暂不可用"
        }
    }
}
