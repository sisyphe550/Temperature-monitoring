import Foundation
import TemperatureCore

public struct CPUWarningPreferencesIssue: Sendable, Equatable {
    public let field: String
    public let reason: String
}

public struct CPUWarningPreferencesLoadResult: Sendable, Equatable {
    public let rule: CPUWarningRule
    public let issues: [CPUWarningPreferencesIssue]
}

public enum CPUWarningPreferencesError: Error, Sendable, Equatable {
    case invalidStoredType
    case writeVerificationFailed
}

@MainActor public protocol CPUWarningPreferencesStore: AnyObject {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

/// Persists only the four mutable rule fields. Readback confirms process-visible
/// storage, not synchronous physical disk durability of UserDefaults.
@MainActor public final class CPUWarningPreferences {
    private let defaults: CPUWarningRule
    private let store: any CPUWarningPreferencesStore

    public convenience init(configuration: RuntimeConfiguration, userDefaults: UserDefaults = .standard,
        key: String = "cpuWarning.rule.v1") throws {
        try self.init(configuration: configuration, store: UserDefaultsCPUWarningStore(defaults: userDefaults, key: key))
    }

    public init(configuration: RuntimeConfiguration, store: any CPUWarningPreferencesStore) throws {
        defaults = try configuration.cpuWarningRule
        self.store = store
    }

    public func load() -> CPUWarningPreferencesLoadResult {
        do {
            guard let data = try store.read() else {
                return CPUWarningPreferencesLoadResult(rule: defaults, issues: [])
            }
            let saved = try JSONDecoder().decode(SavedFields.self, from: data)
            var issues = saved.issues
            let threshold: Double
            if let value = saved.thresholdC,
                (try? CPUWarningRule(enabled: defaults.enabled, thresholdC: value,
                    durationSeconds: defaults.durationSeconds,
                    systemNotificationsEnabled: defaults.systemNotificationsEnabled)) != nil {
                threshold = value
            } else {
                threshold = defaults.thresholdC
                if saved.thresholdC != nil { issues.append(issue("thresholdC", "温度必须为5至120°C的有限数，已使用默认值")) }
            }
            let duration: Int
            if let value = saved.durationSeconds,
                (try? CPUWarningRule(enabled: defaults.enabled, thresholdC: defaults.thresholdC,
                    durationSeconds: value, systemNotificationsEnabled: defaults.systemNotificationsEnabled)) != nil {
                duration = value
            } else {
                duration = defaults.durationSeconds
                if saved.durationSeconds != nil { issues.append(issue("durationSeconds", "持续时间必须为1至300整数秒，已使用默认值")) }
            }
            let rule = try CPUWarningRule(enabled: saved.enabled ?? defaults.enabled, thresholdC: threshold,
                durationSeconds: duration, systemNotificationsEnabled: saved.systemNotificationsEnabled ?? defaults.systemNotificationsEnabled)
            return CPUWarningPreferencesLoadResult(rule: rule, issues: issues)
        } catch {
            return CPUWarningPreferencesLoadResult(rule: defaults,
                issues: [issue("rule", "保存规则无法读取或解析，已使用默认值：\(error)")])
        }
    }

    public func save(_ rule: CPUWarningRule) throws {
        let validated = try CPUWarningRule(enabled: rule.enabled, thresholdC: rule.thresholdC,
            durationSeconds: rule.durationSeconds, systemNotificationsEnabled: rule.systemNotificationsEnabled)
        let data = try JSONEncoder().encode(validated)
        try store.write(data)
        guard try store.read() == data else { throw CPUWarningPreferencesError.writeVerificationFailed }
    }

    private func issue(_ field: String, _ reason: String) -> CPUWarningPreferencesIssue {
        CPUWarningPreferencesIssue(field: field, reason: reason)
    }
}

private struct SavedFields: Decodable {
    let enabled: Bool?
    let thresholdC: Double?
    let durationSeconds: Int?
    let systemNotificationsEnabled: Bool?
    let issues: [CPUWarningPreferencesIssue]
    private enum CodingKeys: String, CodingKey { case enabled, thresholdC, durationSeconds, systemNotificationsEnabled }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var issues: [CPUWarningPreferencesIssue] = []
        enabled = Self.read(Bool.self, key: .enabled, container: container, issues: &issues)
        thresholdC = Self.read(Double.self, key: .thresholdC, container: container, issues: &issues)
        durationSeconds = Self.read(Int.self, key: .durationSeconds, container: container, issues: &issues)
        systemNotificationsEnabled = Self.read(Bool.self, key: .systemNotificationsEnabled, container: container, issues: &issues)
        self.issues = issues
    }

    private static func read<T: Decodable>(_ type: T.Type, key: CodingKeys,
        container: KeyedDecodingContainer<CodingKeys>, issues: inout [CPUWarningPreferencesIssue]) -> T? {
        do { return try container.decode(type, forKey: key) }
        catch {
            issues.append(CPUWarningPreferencesIssue(field: key.stringValue,
                reason: "保存字段缺失或类型无效，已使用默认值"))
            return nil
        }
    }
}

@MainActor private final class UserDefaultsCPUWarningStore: CPUWarningPreferencesStore {
    let defaults: UserDefaults
    let key: String
    init(defaults: UserDefaults, key: String) { self.defaults = defaults; self.key = key }
    func read() throws -> Data? {
        guard let value = defaults.object(forKey: key) else { return nil }
        guard let data = value as? Data else { throw CPUWarningPreferencesError.invalidStoredType }
        return data
    }
    func write(_ data: Data) throws { defaults.set(data, forKey: key) }
}
