import Foundation
import Darwin
import Hako

enum BootstrapResolver {
    /// Call after private core setup but BEFORE installing NEDNSSettings.
    /// Reading again inside the running tunnel could capture its own DNS address.
    static func capture() throws -> [String] {
        let values = HakoSystemResolverLines().split(separator: "\n").map(String.init)
        let usable = values.filter { text in
            var v4 = in_addr()
            var v6 = in6_addr()
            if inet_pton(AF_INET, text, &v4) == 1 {
                return !text.hasPrefix("127.") && !text.hasPrefix("0.")
            }
            return inet_pton(AF_INET6, text, &v6) == 1 && text != "::1" && text != "::"
        }
        guard !usable.isEmpty else { throw PrototypeError.bootstrapUnavailable }
        return Array(usable.prefix(3))
    }
}
