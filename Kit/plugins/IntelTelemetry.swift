import Foundation
import CoreFoundation

public struct IntelCPUSample {
    public let averageMHz: Double?
    public let coreThreadMHz: [[Double]]
    public let packageWatts: Double?
    public let headroomMHz: Double?
    public let limitReasons: [String]

    public static func parse(_ text: String, physical: Int, logical: Int) -> IntelCPUSample {
        var average: Double?
        var power: Double?
        var headroom: Double?
        var reasons: [String] = []
        var groups: [Int: [Double]] = [:]
        var currentCore: Int?
        for line in text.split(separator: "\n") {
            if line.hasPrefix("System Average frequency"), let start = line.lastIndex(of: "("), line.hasSuffix(")") {
                average = number(line[line.index(after: start)...].dropLast(), unit: "MHz")
            } else if line.hasPrefix("Intel energy model derived package power"), let colon = line.lastIndex(of: ":") {
                power = number(line[line.index(after: colon)...], unit: "W")
            } else if line.hasPrefix("Frequency headroom limited on average by ") {
                headroom = number(line.dropFirst("Frequency headroom limited on average by ".count), unit: "MHz")
            } else if line.hasPrefix("CPU LIMIT ") {
                reasons.append(String(line.dropFirst("CPU LIMIT ".count)))
            } else if line.hasPrefix("Core "), line.contains(" C-state residency:"),
                      let id = line.split(separator: " ").dropFirst().first.flatMap({ Int($0) }) {
                currentCore = id

            } else if line.hasPrefix("CPU Average frequency"), let id = currentCore,
                      let start = line.lastIndex(of: "("), line.hasSuffix(")"), let mhz = number(line[line.index(after: start)...].dropLast(), unit: "MHz") {
                groups[id, default: []].append(mhz)
            } else if line.hasPrefix("****") {
                currentCore = nil
            }
        }
        let validTopology = physical > 0 && logical >= physical && logical % physical == 0
        let threads = validTopology ? logical / physical : 0
        let cores: [[Double]] = (0..<max(0, physical)).map { id in
            guard threads > 0, let values = groups[id], values.count == threads,
                  values.allSatisfy({ $0 > 0 }) else { return [] }
            return values
        }
        return IntelCPUSample(averageMHz: average.flatMap { $0 > 0 ? $0 : nil }, coreThreadMHz: cores,
                              packageWatts: power, headroomMHz: headroom, limitReasons: reasons)
    }

    private static func number(_ value: Substring, unit: String) -> Double? {
        let text = value.trimmingCharacters(in: .whitespaces)
        guard text.lowercased().hasSuffix(unit.lowercased()),
              let number = Double(text.dropLast(unit.count).trimmingCharacters(in: .whitespaces)),
              number.isFinite, number >= 0, number < Double(Int.max) else { return nil }
        return number
    }
}

public struct AMDGPUStatistics {
    public let utilization: Double?
    public let temperature: Double?
    public let coreMHz: Double?
    public let memoryMHz: Double?
    public let fanRPM: Double?
    public let watts: Double?
    public let memoryBytes: Double?

    public init(_ stats: [String: Any]) {
        self.utilization = (Self.number(stats["GPU Activity(%)"]) ?? Self.number(stats["Device Utilization %"]))
            .map { min($0, 100) / 100 }
        self.temperature = Self.number(stats["Temperature(C)"])
        self.coreMHz = Self.number(stats["Core Clock(MHz)"])
        self.memoryMHz = Self.number(stats["Memory Clock(MHz)"])
        self.fanRPM = Self.number(stats["Fan Speed(RPM)"])
        self.watts = Self.number(stats["Total Power(W)"])
        self.memoryBytes = Self.number(stats["inUseVidMemoryBytes"])
    }

    public static func memoryCapacity(_ value: Any?) -> Double? {
        if let data = value as? Data, data.count == 4 || data.count == 8 {
            let mb = data.enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << ($1.offset * 8)) }
            return mb > 0 ? Double(mb) * 1_048_576 : nil
        }
        guard let mb = number(value), mb > 0 else { return nil }
        return mb * 1_048_576
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let n = value.doubleValue
        return n.isFinite && n >= 0 && n < Double(Int64.max) ? n : nil
    }

    // Prefer the most complete node, then the stable registry ID. Each field is taken once.
    public static func merge(_ nodes: [(id: UInt64, stats: [String: Any])]) -> AMDGPUStatistics {
        let ranked = nodes.sorted { lhs, rhs in
            let left = AMDGPUStatistics(lhs.stats).fieldCount
            let right = AMDGPUStatistics(rhs.stats).fieldCount
            return left == right ? lhs.id < rhs.id : left > right
        }
        var merged: [String: Any] = [:]
        for node in ranked {
            for (key, value) in node.stats where merged[key] == nil && Self.number(value) != nil {
                merged[key] = value
            }
        }
        return AMDGPUStatistics(merged)
    }

    private var fieldCount: Int {
        [utilization, temperature, coreMHz, memoryMHz, fanRPM, watts, memoryBytes].compactMap { $0 }.count
    }
}
