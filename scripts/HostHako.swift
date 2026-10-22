// Host-only module shim: the same Swift contract calls the pinned Go parser via pipes.
// Never included in an app target. No networking or service startup.
import Foundation

public struct HostStringBox { public let value: String }
private func call(_ operation: String, _ input: String) -> HostStringBox? {
    guard let executable = ProcessInfo.processInfo.environment["CLASH_HOST_BRIDGE"] else { return nil }
    let process = Process(), stdin = Pipe(), stdout = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = [operation]
    process.standardInput = stdin; process.standardOutput = stdout; process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let response = try JSONSerialization.jsonObject(with: output) as? [String: Any],
              response["OK"] as? Bool == true, let value = response["Value"] as? String else { return nil }
        return HostStringBox(value: value)
    } catch { return nil }
}
public func HakoValidateConfigShape(_ value: String, _ error: inout NSError?) -> Bool { call("shape", value) != nil }
public func HakoCheckConfig(_ value: String, _ error: inout NSError?) -> Bool { call("check", value) != nil }
public func HakoYamlToJSON(_ value: String, _ error: inout NSError?) -> HostStringBox? { call("yaml", value) }
public func HakoConfigDeviationsJSON(_ value: String, _ profile: String, _ error: inout NSError?) -> HostStringBox? { call("deviations", value) }

public func HakoJSONToYaml(_ value: String, _ error: inout NSError?) -> HostStringBox? { call("json", value) }

public func HakoPlanResourcesForIOS(_ value: String, _ error: inout NSError?) -> HostStringBox? { call("plan", value) }
public func HakoInspectProviderForIOS(_ kind: String, _ behavior: String, _ format: String, _ payload: Data, _ count: inout Int, _ error: inout NSError?) -> Bool {
    let data = try! JSONSerialization.data(withJSONObject: ["kind": kind, "behavior": behavior, "format": format, "payload": payload.base64EncodedString()])
    guard let value = call("provider", String(decoding: data, as: UTF8.self)), let number = Int(value.value) else { return false }
    count = number; return true
}
public func HakoValidateGeodataCodesForIOS(_ kind: String, _ format: String, _ path: String, _ codes: String, _ error: inout NSError?) -> Bool {
    let data = try! JSONSerialization.data(withJSONObject: ["kind": kind, "format": format, "path": path, "codes": codes])
    return call("geo", String(decoding: data, as: UTF8.self)) != nil
}

public func HakoResolvePolicyForIOS(_ value: String, _ error: inout NSError?) -> HostStringBox? { call("policy", value) }

public func HakoPreserveDNSPolicyOrderForIOS(_ source: String, _ runtime: String, _ error: inout NSError?) -> HostStringBox? {
    guard let data = try? JSONSerialization.data(withJSONObject: ["Source": source, "Runtime": runtime]) else { return nil }
    return call("dns-order", String(decoding: data, as: UTF8.self))
}
