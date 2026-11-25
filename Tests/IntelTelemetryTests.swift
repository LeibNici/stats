import Foundation

@main
struct IntelTelemetryTests {
    static func main() {
        let average = IntelCPUSample.parse(
            "System Average frequency as fraction of nominal: 83.25% (1665.00 Mhz)",
            physical: 16, logical: 32
        )
        precondition(average.averageMHz == 1665)
        precondition(average.coreThreadMHz == Array(repeating: [], count: 16))
        precondition(average.packageWatts == nil && average.headroomMHz == nil && average.limitReasons.isEmpty)

        let wrongUnits = IntelCPUSample.parse(
            "System Average frequency as fraction of nominal: 83.25% (1.665 GHz)",
            physical: 16, logical: 32
        )
        precondition(wrongUnits.averageMHz == nil)

        let topology = """
        Intel energy model derived package power (CPUs+GT+SA): 17.97W
        Frequency headroom limited on average by 0 MHz
        CPU LIMIT VR_ICCMAX
        Core 0 C-state residency: 44.78%
        CPU Average frequency as fraction of nominal: 117.32% (2346.46 Mhz)
        CPU Average frequency as fraction of nominal: 98.01% (1960.21 Mhz)
        Core 1 C-state residency: 95.00%
        CPU Average frequency as fraction of nominal: 60.00% (1200.00 Mhz)
        **** Thermal pressure ****
        CPU Average frequency as fraction of nominal: 60.00% (1200.01 Mhz)
        """
        let grouped = IntelCPUSample.parse(topology, physical: 2, logical: 4)
        precondition(grouped.averageMHz == nil)
        precondition(grouped.coreThreadMHz == [[2346.46, 1960.21], []])
        precondition(grouped.packageWatts == 17.97 && grouped.headroomMHz == 0)
        precondition(grouped.limitReasons == ["VR_ICCMAX"])
        precondition(IntelCPUSample.parse(topology, physical: 2, logical: 3).coreThreadMHz == [[], []])

        let absent = AMDGPUStatistics(["Temperature(C)": true, "Total Power(W)": -1])
        precondition(absent.utilization == nil && absent.temperature == nil && absent.watts == nil)
        precondition(absent.fanRPM == nil && absent.memoryBytes == nil && absent.coreMHz == nil)

        let nodes: [(id: UInt64, stats: [String: Any])] = [
            (9, ["GPU Activity(%)": 0, "Device Utilization %": 13, "Temperature(C)": 51,
                 "Core Clock(MHz)": 1366, "Memory Clock(MHz)": 300, "Fan Speed(RPM)": 895,
                 "inUseVidMemoryBytes": 118_594_765]),
            (8, ["GPU Activity(%)": 0, "Device Utilization %": 0, "Temperature(C)": 51,
                 "Core Clock(MHz)": 1366, "Memory Clock(MHz)": 300, "Fan Speed(RPM)": 896,
                 "inUseVidMemoryBytes": 118_594_765]),
            (10, ["GPU Activity(%)": 0, "Total Power(W)": 121, "inUseVidMemoryBytes": 118_594_765])
        ]
        let merged = AMDGPUStatistics.merge(nodes)
        precondition(merged.utilization == 0 && merged.memoryBytes == 118_594_765)
        precondition(merged.coreMHz == 1366 && merged.memoryMHz == 300)
        precondition(merged.temperature == 51 && merged.fanRPM == 896 && merged.watts == 121)
        precondition(AMDGPUStatistics.merge(nodes.reversed()).fanRPM == 896)
        precondition(AMDGPUStatistics(["GPU Activity(%)": 73]).utilization == 0.73)
        precondition(AMDGPUStatistics(["Device Utilization %": 125]).utilization == 1)
        precondition(AMDGPUStatistics.memoryCapacity(8192) == 8_589_934_592)
        precondition(AMDGPUStatistics.memoryCapacity(Data([0x00, 0x20, 0x00, 0x00])) == 8_589_934_592)
        precondition(AMDGPUStatistics.memoryCapacity(Data([0x20])) == nil)
        precondition(AMDGPUStatistics.memoryCapacity(0) == nil)
        print("Intel telemetry tests passed")
    }
}
