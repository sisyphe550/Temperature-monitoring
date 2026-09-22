import CryptoKit
import Foundation

enum BatchCanonicalHash {
    static func sha256(for batch: PersistenceBatch) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(batch)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
