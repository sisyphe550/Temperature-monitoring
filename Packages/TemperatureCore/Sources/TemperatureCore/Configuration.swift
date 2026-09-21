import Foundation

public enum ConfigurationError: Error, Equatable, Sendable {
    case unreadable(String)
    case invalidJSON
    case unsupportedContractVersion(Int)
    case missingField(String)
    case invalidValue(String)
}

public struct KindSeconds: Codable, Sendable, Equatable {
    public let cpuMain: Double
    public let cpuZone: Double
    public let ssd: Double
    public let battery: Double
}

public struct RetentionSeconds: Codable, Sendable, Equatable {
    public let raw: Int64
    public let ema: Int64
    public let oneSecond: Int64
    public let tenSeconds: Int64
    public let oneMinute: Int64
    public let trend: Int64

    enum CodingKeys: String, CodingKey {
        case raw, ema, trend
        case oneSecond = "1s"
        case tenSeconds = "10s"
        case oneMinute = "1m"
    }
}

public struct RuntimeConfiguration: Codable, Sendable, Equatable {
    public let contractVersion: Int
    public let minimumMacos: String
    public let product: String
    public let bundleID: String
    public let cpuIntervalsMS: [Int]
    public let cpuDefaultMS: Int
    public let ssdIntervalMS: Int
    public let batteryIntervalMS: Int
    public let uiPublishMS: Int
    public let emaTauSeconds: KindSeconds
    public let trendWindowSeconds: KindSeconds
    public let trendMinPoints: Int
    public let trendMinCoverageFraction: Double
    public let trendStableAbsCelsiusPerSecond: Double
    public let gapPeriodMultiplier: Int
    public let gapFloorMS: Int
    public let stalePeriodMultiplier: Int
    public let staleFloorMS: Int
    public let retentionSeconds: RetentionSeconds
    public let retentionTickSeconds: Int64
    public let retentionGraceSeconds: Int64
    public let ringCapacityPerSeries: Int
    public let maxActiveSeries: Int
    public let writerMaxRecords: Int
    public let writerPauseAtRecords: Int
    public let writerResumeBelowRecords: Int
    public let writerFlushRecords: Int
    public let writerFlushMS: Int
    public let writerMaxOldestAgeMS: Int
    public let sqliteBusyTimeoutMS: Int
    public let sqliteWalAutocheckpointPages: Int
    public let sqliteCacheKibPerConnection: Int
    public let sqliteMaxPageCount: Int
    public let dbSoftBytes: Int64
    public let dbHardBytes: Int64
    public let walSoftBytes: Int64
    public let walHardBytes: Int64
    public let historyMaxPointsPerSeries: Int
    public let historyMaxSeries: Int
    public let historyQueryTimeoutMS: Int
    public let sensorRetryMS: [Int]
    public let databaseRetryMS: [Int]
    public let processingRetryMS: [Int]
    public let uiRetryMS: [Int]
    public let workerReadDeadlineMS: Int
    public let workerDiscoverDeadlineMS: Int
    public let workerTerminateGraceMS: Int
    public let workerFrameLimitBytes: Int
    public let optionalRecoverySeconds: Int
    public let optionalRecoveryAttempts: Int
    public let shutdownBudgetMS: Int
    public let fatalDisplayMS: Int
    public let logRotateBytes: Int
    public let logFileCount: Int
    public let reportFileCount: Int
    public let reportFileLimitBytes: Int
    public let diagnosticsTTLDays: Int
    public let clockJumpMS: Int
    public let cpuMaxBatchSpanMS: Int
    public let writerReserveRecordsPerEvent: Int
    public let writerMaxPayloadBytes: Int
    public let discoveryMaxSources: Int

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case minimumMacos = "minimum_macos"
        case product
        case bundleID = "bundle_id"
        case cpuIntervalsMS = "cpu_intervals_ms"
        case cpuDefaultMS = "cpu_default_ms"
        case ssdIntervalMS = "ssd_interval_ms"
        case batteryIntervalMS = "battery_interval_ms"
        case uiPublishMS = "ui_publish_ms"
        case emaTauSeconds = "ema_tau_seconds"
        case trendWindowSeconds = "trend_window_seconds"
        case trendMinPoints = "trend_min_points"
        case trendMinCoverageFraction = "trend_min_coverage_fraction"
        case trendStableAbsCelsiusPerSecond = "trend_stable_abs_celsius_per_second"
        case gapPeriodMultiplier = "gap_period_multiplier"
        case gapFloorMS = "gap_floor_ms"
        case stalePeriodMultiplier = "stale_period_multiplier"
        case staleFloorMS = "stale_floor_ms"
        case retentionSeconds = "retention_seconds"
        case retentionTickSeconds = "retention_tick_seconds"
        case retentionGraceSeconds = "retention_grace_seconds"
        case ringCapacityPerSeries = "ring_capacity_per_series"
        case maxActiveSeries = "max_active_series"
        case writerMaxRecords = "writer_max_records"
        case writerPauseAtRecords = "writer_pause_at_records"
        case writerResumeBelowRecords = "writer_resume_below_records"
        case writerFlushRecords = "writer_flush_records"
        case writerFlushMS = "writer_flush_ms"
        case writerMaxOldestAgeMS = "writer_max_oldest_age_ms"
        case sqliteBusyTimeoutMS = "sqlite_busy_timeout_ms"
        case sqliteWalAutocheckpointPages = "sqlite_wal_autocheckpoint_pages"
        case sqliteCacheKibPerConnection = "sqlite_cache_kib_per_connection"
        case sqliteMaxPageCount = "sqlite_max_page_count"
        case dbSoftBytes = "db_soft_bytes"
        case dbHardBytes = "db_hard_bytes"
        case walSoftBytes = "wal_soft_bytes"
        case walHardBytes = "wal_hard_bytes"
        case historyMaxPointsPerSeries = "history_max_points_per_series"
        case historyMaxSeries = "history_max_series"
        case historyQueryTimeoutMS = "history_query_timeout_ms"
        case sensorRetryMS = "sensor_retry_ms"
        case databaseRetryMS = "database_retry_ms"
        case processingRetryMS = "processing_retry_ms"
        case uiRetryMS = "ui_retry_ms"
        case workerReadDeadlineMS = "worker_read_deadline_ms"
        case workerDiscoverDeadlineMS = "worker_discover_deadline_ms"
        case workerTerminateGraceMS = "worker_terminate_grace_ms"
        case workerFrameLimitBytes = "worker_frame_limit_bytes"
        case optionalRecoverySeconds = "optional_recovery_seconds"
        case optionalRecoveryAttempts = "optional_recovery_attempts"
        case shutdownBudgetMS = "shutdown_budget_ms"
        case fatalDisplayMS = "fatal_display_ms"
        case logRotateBytes = "log_rotate_bytes"
        case logFileCount = "log_file_count"
        case reportFileCount = "report_file_count"
        case reportFileLimitBytes = "report_file_limit_bytes"
        case diagnosticsTTLDays = "diagnostics_ttl_days"
        case clockJumpMS = "clock_jump_ms"
        case cpuMaxBatchSpanMS = "cpu_max_batch_span_ms"
        case writerReserveRecordsPerEvent = "writer_reserve_records_per_event"
        case writerMaxPayloadBytes = "writer_max_payload_bytes"
        case discoveryMaxSources = "discovery_max_sources"
    }
}

public struct SensorProfile: Codable, Sendable, Equatable {
    public let profileVersion: Int
    public let profileID: String
    public let model: String
    public let observedOS: String
    public let observedOSBuild: String
    public let supportStatus: String
    public let cpuProvider: String
    public let cpuKeys: [String]
    public let cpuFormula: String
    public let cpuDisplayName: String
    public let cpuSemanticEvidence: String
    public let cpuMembership: String
    public let batteryProviderPriority: [String]
    public let ssdProvider: String
    public let ssdSemantic: String
    public let automaticHIDFallback: Bool
    public let automaticUnknownModelProfile: Bool
    public let diagnosticOnlyKeys: [String]
    public let expectedSMCEncoding: String
    public let expectedSMCSizeBytes: Int
    public let genericDecoderEncodings: [String]

    enum CodingKeys: String, CodingKey {
        case profileVersion = "profile_version"
        case profileID = "profile_id"
        case model
        case observedOS = "observed_os"
        case observedOSBuild = "observed_os_build"
        case supportStatus = "support_status"
        case cpuProvider = "cpu_provider"
        case cpuKeys = "cpu_keys"
        case cpuFormula = "cpu_formula"
        case cpuDisplayName = "cpu_display_name"
        case cpuSemanticEvidence = "cpu_semantic_evidence"
        case cpuMembership = "cpu_membership"
        case batteryProviderPriority = "battery_provider_priority"
        case ssdProvider = "ssd_provider"
        case ssdSemantic = "ssd_semantic"
        case automaticHIDFallback = "automatic_hid_fallback"
        case automaticUnknownModelProfile = "automatic_unknown_model_profile"
        case diagnosticOnlyKeys = "diagnostic_only_keys"
        case expectedSMCEncoding = "expected_smc_encoding"
        case expectedSMCSizeBytes = "expected_smc_size_bytes"
        case genericDecoderEncodings = "generic_decoder_encodings"
    }
}

public enum Configuration {
    public static func load(from url: URL) throws -> RuntimeConfiguration {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigurationError.unreadable(url.path)
        }
        return try decodeConfiguration(data)
    }

    public static func loadProfile(from url: URL) throws -> SensorProfile {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigurationError.unreadable(url.path)
        }
        return try decodeProfile(data)
    }

    public static func bundledDefaults() throws -> RuntimeConfiguration {
        guard let url = Bundle.module.url(forResource: "defaults-v1", withExtension: "json") else {
            throw ConfigurationError.unreadable("bundled defaults-v1.json")
        }
        return try load(from: url)
    }

    public static func bundledProfile() throws -> SensorProfile {
        guard let url = Bundle.module.url(forResource: "first-profile-v1", withExtension: "json") else {
            throw ConfigurationError.unreadable("bundled first-profile-v1.json")
        }
        return try loadProfile(from: url)
    }

    static func decodeConfiguration(_ data: Data) throws -> RuntimeConfiguration {
        let decoder = JSONDecoder()
        let configuration: RuntimeConfiguration
        do {
            configuration = try decoder.decode(RuntimeConfiguration.self, from: data)
        } catch DecodingError.keyNotFound(let key, _) {
            throw ConfigurationError.missingField(key.stringValue)
        } catch DecodingError.valueNotFound(_, let context) {
            throw ConfigurationError.missingField(context.codingPath.last?.stringValue ?? "value")
        } catch DecodingError.dataCorrupted {
            throw ConfigurationError.invalidJSON
        } catch {
            throw ConfigurationError.invalidJSON
        }
        try validate(configuration)
        return configuration
    }

    static func decodeProfile(_ data: Data) throws -> SensorProfile {
        let decoder = JSONDecoder()
        let profile: SensorProfile
        do {
            profile = try decoder.decode(SensorProfile.self, from: data)
        } catch DecodingError.keyNotFound(let key, _) {
            throw ConfigurationError.missingField(key.stringValue)
        } catch DecodingError.dataCorrupted {
            throw ConfigurationError.invalidJSON
        } catch {
            throw ConfigurationError.invalidJSON
        }
        try validate(profile)
        return profile
    }

    static func validate(_ configuration: RuntimeConfiguration) throws {
        guard configuration.contractVersion == 2 else {
            throw ConfigurationError.unsupportedContractVersion(configuration.contractVersion)
        }
        let intervals = [50, 100, 200, 500, 1000]
        guard configuration.cpuIntervalsMS == intervals else {
            throw ConfigurationError.invalidValue("cpu_intervals_ms")
        }
        guard configuration.cpuDefaultMS == 200 else {
            throw ConfigurationError.invalidValue("cpu_default_ms")
        }
        let taus = [
            configuration.emaTauSeconds.cpuMain,
            configuration.emaTauSeconds.cpuZone,
            configuration.emaTauSeconds.ssd,
            configuration.emaTauSeconds.battery,
        ]
        guard taus.allSatisfy({ $0 > 0 }) else {
            throw ConfigurationError.invalidValue("ema_tau_seconds")
        }
        let retention = configuration.retentionSeconds
        guard retention.raw > 0,
              retention.ema > 0,
              retention.raw <= retention.oneSecond,
              retention.oneSecond <= retention.tenSeconds,
              retention.tenSeconds <= retention.oneMinute
        else {
            throw ConfigurationError.invalidValue("retention_seconds")
        }
        guard configuration.writerResumeBelowRecords < configuration.writerPauseAtRecords,
              configuration.writerPauseAtRecords < configuration.writerMaxRecords
        else {
            throw ConfigurationError.invalidValue("writer watermarks")
        }
        guard configuration.writerReserveRecordsPerEvent <= configuration.writerFlushRecords else {
            throw ConfigurationError.invalidValue("writer_reserve_records_per_event")
        }
        guard configuration.ringCapacityPerSeries > 0,
              configuration.maxActiveSeries > 0,
              configuration.dbSoftBytes > 0,
              configuration.dbHardBytes > configuration.dbSoftBytes
        else {
            throw ConfigurationError.invalidValue("capacity")
        }
    }

    static func validate(_ profile: SensorProfile) throws {
        let expected = [
            "Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05",
            "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
        ]
        guard profile.profileID == "Mac16,13-m4-v1",
              profile.model == "Mac16,13",
              profile.cpuKeys == expected,
              Set(profile.cpuKeys).count == 12,
              profile.cpuFormula == "max",
              profile.expectedSMCEncoding == "flt ",
              profile.expectedSMCSizeBytes == 4,
              profile.automaticUnknownModelProfile == false
        else {
            throw ConfigurationError.invalidValue("sensor profile")
        }
    }
}
