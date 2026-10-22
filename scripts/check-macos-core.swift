import Foundation
import Hako

/// Executes only local parsers/validators with synthetic inputs. No Setup, service
/// creation, node probe, Keychain, CloudKit or network connection is performed.
@main struct CheckMacOSCore {
    static func main() throws {
        let report = PrototypeSelfCheck.run()
        guard report.failures.isEmpty else {
            for failure in report.failures { print("FAIL synthetic: " + failure) }
            exit(1)
        }
        print("PASS native macOS SDK: " + report.summary)
        let fixture = "mode: rule\nproxies: []\nproxy-groups: []\nrules: ['MATCH,DIRECT']\n"
        for profile in ["iosPacketTunnel", "macosPacketTunnel", "macosApplication"] {
            var error: NSError?
            guard let deviations = HakoConfigDeviationsJSON(fixture, profile, &error), error == nil,
                  let bytes = deviations.value.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: bytes)) != nil else {
                fatalError("Synthetic deviation check failed for " + profile)
            }
            error = nil
            guard let resources = HakoPlanResourcesForProfile(fixture, profile, &error), error == nil,
                  let bytes = resources.value.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: bytes)) != nil else {
                fatalError("Synthetic resource plan failed for " + profile)
            }
            print("PASS local deviation and resource APIs: " + profile)
        }
        print("Core " + HakoVersion() + "; " + HakoGoVersion())
        print("No VPN, real subscription, Keychain or cloud operation was performed.")
    }
}
