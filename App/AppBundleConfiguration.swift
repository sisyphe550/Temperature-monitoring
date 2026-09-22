import Foundation
import TemperatureCore

enum AppBundleConfiguration {
    static func loadRuntimeConfiguration() throws -> RuntimeConfiguration {
        try Configuration.load(from: try resourceURL(name: "defaults-v1", extension: "json"))
    }

    static func loadProfile() throws -> SensorProfile {
        try Configuration.loadProfile(from: try resourceURL(name: "first-profile-v1", extension: "json"))
    }

    static func thirdPartyManifestURL() throws -> URL {
        try resourceURL(name: "third-party-v1", extension: "json")
    }

    static func thirdPartyNoticesURL() throws -> URL {
        try resourceURL(name: "ThirdPartyNotices", extension: "md")
    }

    private static func resourceURL(name: String, extension: String) throws -> URL {
        if let bundled = Bundle.main.url(forResource: name, withExtension: `extension`) {
            return bundled
        }
        throw ConfigurationError.unreadable("App resource \(name).\(`extension`)")
    }
}

extension Bundle {
    var sensorWorkerExecutableURL: URL? {
        let url = bundleURL.appendingPathComponent("Contents/MacOS/SensorWorker")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
}
