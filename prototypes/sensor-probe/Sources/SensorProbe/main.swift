import Foundation
import Darwin
import CryptoKit
import ProbeCore

#if DEBUG
let buildConfiguration = "debug"
#else
let buildConfiguration = "release"
#endif

let help = """
Exploratory read-only sensor probe (not a production application).
sensor-probe [--intervals 50,100,200,500,1000] [--seconds 120] [--output NEW_DIRECTORY]
Defaults: CPU candidates 200 ms, 10 seconds; SSD 500 ms; Battery 1000 ms.
--seconds is per CPU setting (1...3600). Output directory must not already exist.
No root required by this tool. Missing sensors are recorded; no synthetic values.
Exit: 0 evidence recorded with a finite CPU candidate; 2 invocation/output error;
      3 evidence recorded but no finite CPU candidate was sampled.
"""

struct Capability: Codable {
    let provider: String
    let rawID: String
    let role: String
    let unitEvidence: String
    let physicalMapping: String
    let sourceUpdatedAt: String?
    let initialReading: Reading
}
struct Inventory: Codable {
    let schemaVersion: Int
    let startedAt: String
    let environment: [String: String]
    let diagnostics: [String: String]
    let sensors: [Capability]
}
struct PhaseResult: Codable {
    let cpuIntervalMS: Int
    let requestedSeconds: Int
    let elapsedSeconds: Double
    let expectedOpportunities: [String: UInt64]
    let startedBatches: [String: UInt64]
    let missedOpportunities: [String: UInt64]
    let readings: Int
    let finiteReadings: Int
    let finiteCPUCandidateReadings: Int
    let processCPUSeconds: Double
    let processCPUAveragePercentOfOneCore: Double
    let processMaxRSSBytes: Int64
}
struct Group {
    let name: String
    let periodNS: UInt64
    let sensors: [Sensor]
    var slot: UInt64 = 0
    var started: UInt64 = 0
}

func runCommand(_ executable: String, _ args: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "unavailable" }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    } catch { return "unavailable" }
}

func writeJSON<T: Encodable>(_ value: T, at url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: .atomic)
}

func resourceUsage() -> (cpu: Double, rss: Int64) {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    return (cpu, Int64(usage.ru_maxrss))
}

func run(_ options: Options) throws -> Int32 {
    let directory = URL(fileURLWithPath: options.output, isDirectory: true)
    guard !FileManager.default.fileExists(atPath: directory.path) else {
        throw NSError(domain: "SensorProbe", code: 2, userInfo: [NSLocalizedDescriptionKey: "Output already exists; choose a new directory"])
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let hardware = Hardware()
    let initial = hardware.sensors.map { sensor in
        Capability(provider: sensor.provider, rawID: sensor.id, role: sensor.role, unitEvidence: sensor.unitEvidence,
                   physicalMapping: sensor.role.hasSuffix("candidate") || sensor.role == "unmapped" ? "unverified" : "provider_defined; device identity session_local",
                   sourceUpdatedAt: nil, initialReading: sensor.read())
    }
    let inventory = Inventory(schemaVersion: 1, startedAt: ISO8601DateFormatter().string(from: Date()), environment: [
        "model": runCommand("/usr/sbin/sysctl", ["-n", "hw.model"]),
        "chip": runCommand("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]),
        "physicalCPUCount": runCommand("/usr/sbin/sysctl", ["-n", "hw.physicalcpu"]),
        "memoryBytes": runCommand("/usr/sbin/sysctl", ["-n", "hw.memsize"]),
        "macOS": runCommand("/usr/bin/sw_vers", ["-productVersion"]),
        "build": runCommand("/usr/bin/sw_vers", ["-buildVersion"]),
        "swift": runCommand("/usr/bin/xcrun", ["swift", "--version"]),
        "sdk": runCommand("/usr/bin/xcrun", ["--show-sdk-version"]),
        "uid": String(getuid()), "euid": String(geteuid()),
        "binarySHA256": try Bundle.main.executableURL.map { url in
            SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        } ?? "unavailable",
        "gitRevision": runCommand("/usr/bin/git", ["rev-parse", "HEAD"]),
        "gitWorktreeStatus": runCommand("/usr/bin/git", ["status", "--porcelain"]),
        "thermalState": String(ProcessInfo.processInfo.thermalState.rawValue),
        "sourceFreshness": "unknown; no source timestamp claimed",
        "configuration": buildConfiguration
    ], diagnostics: hardware.diagnostics, sensors: initial)
    try writeJSON(inventory, at: directory.appendingPathComponent("capabilities.json"))

    let samplesURL = directory.appendingPathComponent("sampling-results.csv")
    let timingURL = directory.appendingPathComponent("timing.csv")
    try Data("cpu_interval_ms,group,slot,scheduled_ns,read_start_ns,read_end_ns,wall_time,provider,raw_id,raw_type,raw_value,celsius,status,source_updated_at,retry_count\n".utf8).write(to: samplesURL)
    try Data("cpu_interval_ms,group,slot,scheduled_ns,batch_start_ns,batch_end_ns,lateness_ns,readings,finite_readings\n".utf8).write(to: timingURL)
    let samples = try FileHandle(forWritingTo: samplesURL)
    let timing = try FileHandle(forWritingTo: timingURL)
    defer { try? samples.close(); try? timing.close() }
    try samples.seekToEnd(); try timing.seekToEnd()
    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var results: [PhaseResult] = []
    for interval in options.intervals {
        let candidates = hardware.sensors.filter { $0.role == "cpu_candidate" }
        var groups = [Group(name: "cpu_candidates", periodNS: UInt64(interval) * 1_000_000, sensors: candidates),
                      Group(name: "ssd", periodNS: 500_000_000, sensors: hardware.sensors.filter { $0.role == "ssd" || $0.role == "ssd_candidate" }),
                      Group(name: "battery", periodNS: 1_000_000_000, sensors: hardware.sensors.filter { $0.role == "battery" || $0.role == "battery_candidate" })]
            .filter { !$0.sensors.isEmpty }
        let duration = UInt64(options.seconds) * 1_000_000_000
        let before = resourceUsage()
        let start = DispatchTime.now().uptimeNanoseconds
        var readingCount = 0, finiteCount = 0, cpuFiniteCount = 0
        while let index = groups.indices.filter({ groups[$0].slot * groups[$0].periodNS < duration })
            .min(by: { groups[$0].slot * groups[$0].periodNS < groups[$1].slot * groups[$1].periodNS }) {
            let scheduled = groups[index].slot * groups[index].periodNS
            let now = DispatchTime.now().uptimeNanoseconds - start
            if now >= duration { break }
            if now < scheduled { Thread.sleep(forTimeInterval: Double(scheduled - now) / 1e9) }
            let began = DispatchTime.now().uptimeNanoseconds - start
            if began >= duration { break }
            var rows = "", batchFinite = 0
            for sensor in groups[index].sensors {
                let readStart = DispatchTime.now().uptimeNanoseconds - start
                let wall = dateFormatter.string(from: Date())
                let reading = sensor.read()
                let readEnd = DispatchTime.now().uptimeNanoseconds - start
                if reading.celsius != nil { batchFinite += 1 }
                let fields = [String(interval), groups[index].name, String(groups[index].slot), String(scheduled),
                              String(readStart), String(readEnd), wall, sensor.provider, sensor.id,
                              reading.rawType, reading.rawValue, reading.celsius.map { String($0) } ?? "", reading.status, "", "0"]
                rows += fields.map(csvField).joined(separator: ",") + "\n"
            }
            let ended = DispatchTime.now().uptimeNanoseconds - start
            try samples.write(contentsOf: Data(rows.utf8))
            let batch = [String(interval), groups[index].name, String(groups[index].slot), String(scheduled),
                         String(began), String(ended), String(began - scheduled), String(groups[index].sensors.count), String(batchFinite)]
            try timing.write(contentsOf: Data((batch.joined(separator: ",") + "\n").utf8))
            readingCount += groups[index].sensors.count
            finiteCount += batchFinite
            if groups[index].name == "cpu_candidates" { cpuFiniteCount += batchFinite }
            groups[index].started += 1
            groups[index].slot = Schedule.nextSlot(current: groups[index].slot,
                                                   finishedNS: DispatchTime.now().uptimeNanoseconds - start,
                                                   periodNS: groups[index].periodNS)
        }
        // Keep the observation window complete even after its last scheduled
        // batch, so resource rates and --seconds use the same duration.
        let afterLastBatch = DispatchTime.now().uptimeNanoseconds - start
        if !groups.isEmpty && afterLastBatch < duration {
            Thread.sleep(forTimeInterval: Double(duration - afterLastBatch) / 1e9)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        let after = resourceUsage()
        let expected = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, (duration + $0.periodNS - 1) / $0.periodNS) })
        let started = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0.started) })
        let missed = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, expected[$0.name]! - $0.started) })
        results.append(PhaseResult(cpuIntervalMS: interval, requestedSeconds: options.seconds, elapsedSeconds: elapsed,
                                   expectedOpportunities: expected, startedBatches: started, missedOpportunities: missed,
                                   readings: readingCount, finiteReadings: finiteCount, finiteCPUCandidateReadings: cpuFiniteCount,
                                   processCPUSeconds: after.cpu - before.cpu,
                                   processCPUAveragePercentOfOneCore: (after.cpu - before.cpu) / max(elapsed, 0.001) * 100,
                                   processMaxRSSBytes: after.rss))
        try writeJSON(results, at: directory.appendingPathComponent("summary.json"))
        print("CPU setting \(interval) ms: \(readingCount) readings, \(finiteCount) finite; missed opportunities \(missed)")
    }
    try samples.synchronize(); try timing.synchronize()
    return results.contains { $0.finiteCPUCandidateReadings > 0 } ? 0 : 3
}

if CommandLine.arguments.dropFirst().contains("--help") {
    print(help)
} else {
    do {
        let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
        exit(try run(options))
    } catch {
        FileHandle.standardError.write(Data("sensor-probe: \(error.localizedDescription)\n\(help)\n".utf8))
        exit(2)
    }
}
