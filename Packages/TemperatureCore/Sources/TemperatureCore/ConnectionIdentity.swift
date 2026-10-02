import CryptoKit
import Foundation

// Internal package identity for a new connection/definition; display names
// never determine physical meaning. The first generation retains existing IDs.
package enum ConnectionIdentity {
    package static func uuid(role: String, generation: UInt64, identity: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("temperature-monitor/\(role)/\(generation)/\(identity)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
