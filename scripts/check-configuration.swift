import Foundation

@main struct CheckConfiguration {
    static func main() throws {
        try ExtendedCompatibilitySelfCheck.document.write(to: URL(fileURLWithPath: ".build/research/expanded-source.json"))
        let check = PrototypeSelfCheck.run()
        print(check.summary)
        for failure in check.failures { print("FAIL synthetic: " + failure) }
        guard check.failures.isEmpty else { exit(1) }
        let expanded = try PrototypeConfiguration.prepare(ExtendedCompatibilitySelfCheck.document)
        try Data(expanded.runtimeJSON.utf8).write(to: URL(fileURLWithPath: ".build/research/expanded-fixture-runtime.json"))
        let examples = URL(fileURLWithPath: "Examples/compatibility", isDirectory: true)
        try FileManager.default.createDirectory(at: examples, withIntermediateDirectories: true)
        for sample in CompatibilitySamples.all {
            try Data(sample.yaml.utf8).write(to: examples.appendingPathComponent(sample.id + ".yaml"))
        }
        // Only the synthetic fixture is exported, never a supplied profile.
        let synthetic = try PrototypeConfiguration.prepare(Data(CompatibilityFixture.yaml.utf8))
        try Data(synthetic.runtimeJSON.utf8).write(to: URL(fileURLWithPath: ".build/research/compat-fixture-runtime.json"))
        try Data(CompatibilityFixture.yaml.utf8).write(to: URL(fileURLWithPath: "Examples/dual-protocol.redacted.yaml"))
        if CommandLine.arguments.count == 2 {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
                let prepared = try PrototypeConfiguration.prepare(data)
                print("Supplied local file contract: PASS; " + prepared.summary)
                print("Original source retained: \(prepared.source == data); custom bootstrap retained: \(!prepared.needsSystemBootstrap)")
                print("No service, node connection, Keychain write or raw configuration output.")
            } catch let error as ConfigurationIssue {
                print("Supplied local file contract: FAIL; " + error.detail); exit(2)
            } catch {
                print("Supplied local file contract: FAIL code=\((error as? PrototypeError)?.rawValue ?? 0)"); exit(2)
            }
        }
    }
}
