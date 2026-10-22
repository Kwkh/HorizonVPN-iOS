import Foundation
import Hako

/// Compile/link probe only. Does not start a service or install network settings.
public func coreBuildIdentity() -> String {
    HakoVersion() + " / " + HakoGoVersion()
}

/// Uses a credential-free document; a shape check is not routing validation.
public func coreCanValidateShape() -> Bool {
    var error: NSError?
    return HakoValidateConfigShape("mode: rule\nrules:\n  - MATCH,DIRECT\n", &error)
}

/// The bound symbol must exist in all three iOS slices; this function is not run.
public func coreCanLinkTimedProbe() -> Int32 {
    HakoURLTestWithTimeout("SYNTHETIC-MISSING", "http://example.invalid/", 10_000)
}
