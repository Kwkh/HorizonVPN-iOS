import Foundation

enum AutomatedSelfCheck {
    static func runIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["CLASH_OFFLINE_CHECK"] == "1" else { return }
        let result = PrototypeSelfCheck.run()
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline-check.json")
        try? JSONEncoder().encode(result).write(to: file, options: .atomic)
        if ProcessInfo.processInfo.environment["CLASH_CORE_INIT_CHECK"] == "1" {
            let initialization = CoreInitializationSelfCheck.run()
            let report = file.deletingLastPathComponent().appendingPathComponent("core-initialization-check.json")
            try? JSONEncoder().encode(initialization).write(to: report, options: .atomic)
        }
        #endif
    }
}
