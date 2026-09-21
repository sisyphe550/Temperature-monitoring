import Foundation

public enum IdentifierError: Error, Sendable, Equatable {
    case nonCanonicalUUID(String)
    case emptyMetricID
    case invalidMetricID(String)
}

public struct TaggedUUID<Tag>: Codable, Sendable, Hashable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard
            let uuid = UUID(uuidString: rawValue),
            uuid.uuidString.lowercased() == rawValue
        else {
            throw IdentifierError.nonCanonicalUUID(rawValue)
        }
        self.rawValue = rawValue
    }

    public init(_ uuid: UUID) {
        self.rawValue = uuid.uuidString.lowercased()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum SessionIDTag: Sendable {}
public enum SourceIDTag: Sendable {}
public enum SeriesIDTag: Sendable {}
public enum RequestIDTag: Sendable {}
public enum BatchIDTag: Sendable {}
public enum GapIDTag: Sendable {}
public enum WatermarkEventIDTag: Sendable {}

public typealias SessionID = TaggedUUID<SessionIDTag>
public typealias SourceID = TaggedUUID<SourceIDTag>
public typealias SeriesID = TaggedUUID<SeriesIDTag>
public typealias RequestID = TaggedUUID<RequestIDTag>
public typealias BatchID = TaggedUUID<BatchIDTag>
public typealias GapID = TaggedUUID<GapIDTag>
public typealias WatermarkEventID = TaggedUUID<WatermarkEventIDTag>

public struct MetricID: Codable, Sendable, Hashable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard !rawValue.isEmpty else {
            throw IdentifierError.emptyMetricID
        }
        guard rawValue.range(of: #"^[a-z][a-z0-9]*(?:\.[a-z0-9]+)*$"#, options: .regularExpression) != nil else {
            throw IdentifierError.invalidMetricID(rawValue)
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct Timestamp: Codable, Sendable, Equatable {
    public let elapsedNS: Int64
    public let wallUnixNS: Int64

    public init(elapsedNS: Int64, wallUnixNS: Int64) {
        self.elapsedNS = elapsedNS
        self.wallUnixNS = wallUnixNS
    }
}

public struct SessionMetadata: Codable, Sendable, Equatable {
    public let sessionID: SessionID
    public let startedWallUnixNS: Int64
    public let model: String
    public let osBuild: String
    public let appVersion: String

    public init(
        sessionID: SessionID,
        startedWallUnixNS: Int64,
        model: String,
        osBuild: String,
        appVersion: String
    ) {
        self.sessionID = sessionID
        self.startedWallUnixNS = startedWallUnixNS
        self.model = model
        self.osBuild = osBuild
        self.appVersion = appVersion
    }
}
