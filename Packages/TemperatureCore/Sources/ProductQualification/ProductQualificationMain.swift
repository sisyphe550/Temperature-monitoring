import Foundation
import SensorRuntime
import TemperatureCore

enum ProductQualificationCommand: String {
    case sources
    case schedules
    case lifecycle
    case endurance
}

struct ProductQualificationOptions {
    let command: ProductQualificationCommand
    let workerURL: URL
    let profileURL: URL
    let defaultsURL: URL?
    let appURL: URL?
    let outputURL: URL?
    let durationSeconds: Int
    let checkpointIntervalSeconds: Int
    let intervalsMS: [Int]
}

enum ProductQualificationMain {
    static func run() async {
        do {
            let options = try parseOptions()
            switch options.command {
            case .sources:
                let report = try await SourcesCollector.collect(
                    workerURL: options.workerURL,
                    profileURL: options.profileURL
                )
                let data = try JSONEncoder.pretty.encode(report)
                FileHandle.standardOutput.write(data)
                try FileHandle.standardOutput.write(contentsOf: Data("\n".utf8))
            case .schedules:
                guard let outputURL = options.outputURL else {
                    throw QualificationError.missingArgument("--output")
                }
                let report = try await SchedulesCollector.collect(
                    workerURL: options.workerURL,
                    profileURL: options.profileURL,
                    defaultsURL: options.defaultsURL,
                    durationSeconds: options.durationSeconds,
                    intervalsMS: options.intervalsMS,
                    outputDirectory: outputURL
                )
                let data = try JSONEncoder.pretty.encode(report)
                try data.write(to: outputURL.appendingPathComponent("schedules.json"))
                FileHandle.standardOutput.write(data)
                try FileHandle.standardOutput.write(contentsOf: Data("\n".utf8))
            case .lifecycle:
                guard let outputURL = options.outputURL else {
                    throw QualificationError.missingArgument("--output")
                }
                let report = try await LifecycleCollector.collect(
                    workerURL: options.workerURL,
                    profileURL: options.profileURL,
                    defaultsURL: options.defaultsURL,
                    appURL: options.appURL,
                    outputDirectory: outputURL
                )
                let data = try JSONEncoder.pretty.encode(report)
                try data.write(to: outputURL.appendingPathComponent("lifecycle.json"))
                FileHandle.standardOutput.write(data)
                try FileHandle.standardOutput.write(contentsOf: Data("\n".utf8))
            case .endurance:
                guard let outputURL = options.outputURL else {
                    throw QualificationError.missingArgument("--output")
                }
                let report = try await EnduranceCollector.collect(
                    workerURL: options.workerURL,
                    profileURL: options.profileURL,
                    defaultsURL: options.defaultsURL,
                    durationSeconds: options.durationSeconds,
                    checkpointIntervalSeconds: options.checkpointIntervalSeconds,
                    outputDirectory: outputURL
                )
                let data = try JSONEncoder.pretty.encode(report)
                try data.write(to: outputURL.appendingPathComponent("endurance.json"))
                FileHandle.standardOutput.write(data)
                try FileHandle.standardOutput.write(contentsOf: Data("\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("product-qualification: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func parseOptions() throws -> ProductQualificationOptions {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let commandRaw = arguments.first,
              let command = ProductQualificationCommand(rawValue: commandRaw) else {
            throw QualificationError.usage
        }
        arguments.removeFirst()

        var workerURL: URL?
        var profileURL: URL?
        var defaultsURL: URL?
        var appURL: URL?
        var outputURL: URL?
        var durationSeconds = 600
        var checkpointIntervalSeconds = 3600
        var intervalsMS = [50, 100, 200, 500, 1000]

        while !arguments.isEmpty {
            let flag = arguments.removeFirst()
            switch flag {
            case "--worker":
                workerURL = try requiredURL(from: &arguments, flag: flag)
            case "--profile":
                profileURL = try requiredURL(from: &arguments, flag: flag)
            case "--defaults":
                defaultsURL = try requiredURL(from: &arguments, flag: flag)
            case "--app":
                appURL = try requiredURL(from: &arguments, flag: flag)
            case "--output":
                outputURL = try requiredURL(from: &arguments, flag: flag)
            case "--duration-seconds":
                durationSeconds = try requiredInt(from: &arguments, flag: flag)
            case "--checkpoint-interval-seconds":
                checkpointIntervalSeconds = try requiredInt(from: &arguments, flag: flag)
            case "--intervals":
                intervalsMS = try requiredIntervals(from: &arguments, flag: flag)
            default:
                throw QualificationError.unknownArgument(flag)
            }
        }

        guard let workerURL, let profileURL else {
            throw QualificationError.usage
        }
        switch command {
        case .schedules where defaultsURL == nil || outputURL == nil:
            throw QualificationError.missingArgument("--defaults and --output")
        case .lifecycle where defaultsURL == nil || outputURL == nil:
            throw QualificationError.missingArgument("--defaults and --output")
        case .endurance where defaultsURL == nil || outputURL == nil:
            throw QualificationError.missingArgument("--defaults and --output")
        default:
            break
        }

        return ProductQualificationOptions(
            command: command,
            workerURL: workerURL,
            profileURL: profileURL,
            defaultsURL: defaultsURL,
            appURL: appURL,
            outputURL: outputURL,
            durationSeconds: durationSeconds,
            checkpointIntervalSeconds: checkpointIntervalSeconds,
            intervalsMS: intervalsMS
        )
    }

    private static func requiredURL(from arguments: inout [String], flag: String) throws -> URL {
        guard let value = arguments.first else {
            throw QualificationError.missingArgument(flag)
        }
        arguments.removeFirst()
        return URL(fileURLWithPath: value)
    }

    private static func requiredInt(from arguments: inout [String], flag: String) throws -> Int {
        guard let value = arguments.first, let parsed = Int(value), parsed > 0 else {
            throw QualificationError.invalidValue(flag)
        }
        arguments.removeFirst()
        return parsed
    }

    private static func requiredIntervals(from arguments: inout [String], flag: String) throws -> [Int] {
        guard let value = arguments.first else {
            throw QualificationError.missingArgument(flag)
        }
        arguments.removeFirst()
        let intervals = value.split(separator: ",").compactMap { Int($0) }
        guard intervals.count == value.split(separator: ",").count else {
            throw QualificationError.invalidValue(flag)
        }
        return intervals
    }
}

enum QualificationError: Error, CustomStringConvertible {
    case usage
    case missingArgument(String)
    case unknownArgument(String)
    case invalidValue(String)
    case hostModelMismatch(expected: String, actual: String)
    case cpuMembershipIncomplete(expected: Int, available: Int)

    var description: String {
        switch self {
        case .usage:
            return """
            usage: ProductQualification sources --worker PATH --profile PATH
                   ProductQualification schedules --worker PATH --profile PATH --defaults PATH --output DIR [--duration-seconds N] [--intervals 50,100,200,500,1000]
                   ProductQualification lifecycle --worker PATH --profile PATH --defaults PATH --output DIR [--app PATH]
                   ProductQualification endurance --worker PATH --profile PATH --defaults PATH --output DIR [--duration-seconds N] [--checkpoint-interval-seconds N]
            """
        case .missingArgument(let flag):
            return "missing value for \(flag)"
        case .unknownArgument(let flag):
            return "unknown argument \(flag)"
        case .invalidValue(let flag):
            return "invalid value for \(flag)"
        case .hostModelMismatch(let expected, let actual):
            return "host model \(actual) does not match profile model \(expected)"
        case .cpuMembershipIncomplete(let expected, let available):
            return "qualified CPU sources \(available)/\(expected)"
        }
    }
}

extension JSONEncoder {
    fileprivate static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
