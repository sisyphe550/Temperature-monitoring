import Foundation
import Testing
@testable import TemperatureCore

@Suite struct AppBundleConfigurationTests {
    @Test func appResourcesMatchBundledContracts() throws {
        let repoRoot = try repositoryRoot()
        let appDefaults = try Configuration.load(
            from: repoRoot.appendingPathComponent("App/Resources/defaults-v1.json")
        )
        let bundledDefaults = try Configuration.bundledDefaults()
        #expect(appDefaults == bundledDefaults)

        let appProfile = try Configuration.loadProfile(
            from: repoRoot.appendingPathComponent("App/Resources/first-profile-v1.json")
        )
        let bundledProfile = try Configuration.bundledProfile()
        #expect(appProfile == bundledProfile)

        let contractThirdParty = repoRoot.appendingPathComponent("docs/contracts/third-party-v1.json")
        let appThirdParty = repoRoot.appendingPathComponent("App/Resources/third-party-v1.json")
        #expect(try Data(contentsOf: contractThirdParty) == Data(contentsOf: appThirdParty))
    }
}

private func repositoryRoot() throws -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0 ..< 5 {
        url.deleteLastPathComponent()
    }
    return url
}
