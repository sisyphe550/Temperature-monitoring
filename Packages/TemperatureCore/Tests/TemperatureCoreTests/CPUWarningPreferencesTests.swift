import Foundation
import Testing
@testable import TemperatureCore
@testable import TemperaturePresentation

@Suite(.serialized) @MainActor struct CPUWarningPreferencesTests {
    @Test func savedRuleSurvivesNewPreferencesInstanceWithoutSessionState() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = try Configuration.bundledDefaults()
        let preferences = try CPUWarningPreferences(configuration: configuration, userDefaults: defaults)
        let initial = preferences.load()
        #expect(initial.rule.enabled)
        #expect(initial.rule.thresholdC == 90)
        #expect(initial.rule.durationSeconds == 5)
        #expect(!initial.rule.systemNotificationsEnabled)
        #expect(initial.issues.isEmpty)
        let rule = try CPUWarningRule(enabled: true, thresholdC: 80.5, durationSeconds: 7,
            systemNotificationsEnabled: true)
        try preferences.save(rule)
        let reopened = try CPUWarningPreferences(configuration: configuration, userDefaults: defaults).load()
        #expect(reopened.rule == rule)
        #expect(reopened.issues.isEmpty)
        let data = try #require(defaults.data(forKey: "cpuWarning.rule.v1"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == Set(["enabled", "thresholdC", "durationSeconds", "systemNotificationsEnabled"]))
    }

    @Test func invalidFieldsUseDefaultsWhileValidNotificationChoiceSurvives() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"enabled":"bad","thresholdC":121,"durationSeconds":0,"systemNotificationsEnabled":true}"#.utf8),
            forKey: "cpuWarning.rule.v1")
        let result = try CPUWarningPreferences(configuration: Configuration.bundledDefaults(), userDefaults: defaults).load()
        #expect(result.rule.enabled)
        #expect(result.rule.thresholdC == 90)
        #expect(result.rule.durationSeconds == 5)
        #expect(result.rule.systemNotificationsEnabled)
        #expect(Set(result.issues.map(\.field)) == Set(["enabled", "thresholdC", "durationSeconds"]))
    }

    @Test func missingFieldsDoNotDiscardAnExplicitDisabledChoice() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"enabled":false}"#.utf8), forKey: "cpuWarning.rule.v1")
        let result = try CPUWarningPreferences(configuration: Configuration.bundledDefaults(), userDefaults: defaults).load()
        #expect(!result.rule.enabled)
        #expect(result.rule.thresholdC == 90)
        #expect(result.rule.durationSeconds == 5)
        #expect(!result.rule.systemNotificationsEnabled)
        #expect(result.issues.count == 3)
    }

    @Test(arguments: ["4.99", "120.01", "1e309", #""NaN""#])
    func invalidThresholdNeverDisablesMonitoring(thresholdJSON: String) throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let json = "{\"enabled\":true,\"thresholdC\":\(thresholdJSON),\"durationSeconds\":5,\"systemNotificationsEnabled\":false}"
        defaults.set(Data(json.utf8), forKey: "cpuWarning.rule.v1")
        let result = try CPUWarningPreferences(configuration: Configuration.bundledDefaults(), userDefaults: defaults).load()
        #expect(result.rule.enabled)
        #expect(result.rule.thresholdC == 90)
        #expect(!result.issues.isEmpty)
    }

    @Test(arguments: ["0", "301", "1.5", #""5""#])
    func durationRequiresAnIntegerWithinRange(durationJSON: String) throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let json = "{\"enabled\":true,\"thresholdC\":91,\"durationSeconds\":\(durationJSON),\"systemNotificationsEnabled\":false}"
        defaults.set(Data(json.utf8), forKey: "cpuWarning.rule.v1")
        let result = try CPUWarningPreferences(configuration: Configuration.bundledDefaults(), userDefaults: defaults).load()
        #expect(result.rule.thresholdC == 91)
        #expect(result.rule.durationSeconds == 5)
        #expect(result.issues.map(\.field) == ["durationSeconds"])
    }

    @Test func malformedOrUnexpectedStoredValueReportsAnIssue() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = try CPUWarningPreferences(configuration: Configuration.bundledDefaults(), userDefaults: defaults)
        defaults.set(Data("broken JSON".utf8), forKey: "cpuWarning.rule.v1")
        #expect(preferences.load().rule.enabled)
        #expect(!preferences.load().issues.isEmpty)
        defaults.set("unexpected stored type", forKey: "cpuWarning.rule.v1")
        #expect(preferences.load().rule.thresholdC == 90)
        #expect(!preferences.load().issues.isEmpty)
    }

    @Test func saveFailureAndReadbackMismatchAreVisible() throws {
        let configuration = try Configuration.bundledDefaults()
        let store = FailingPreferenceStore()
        let preferences = try CPUWarningPreferences(configuration: configuration, store: store)
        let rule = try CPUWarningRule(enabled: true, thresholdC: 95, durationSeconds: 3,
            systemNotificationsEnabled: false)
        #expect(throws: PreferenceStoreError.writeFailed) { try preferences.save(rule) }
        store.throwOnWrite = false
        #expect(throws: CPUWarningPreferencesError.writeVerificationFailed) { try preferences.save(rule) }
        #expect(preferences.load().rule.thresholdC == 90)
    }
}

@MainActor private func isolatedDefaults() -> (UserDefaults, String) {
    let suite = "CPUWarningPreferencesTests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: suite)!, suite)
}

private enum PreferenceStoreError: Error, Equatable { case writeFailed }

@MainActor private final class FailingPreferenceStore: CPUWarningPreferencesStore {
    var throwOnWrite = true
    func read() throws -> Data? { nil }
    func write(_ data: Data) throws {
        if throwOnWrite { throw PreferenceStoreError.writeFailed }
    }
}
