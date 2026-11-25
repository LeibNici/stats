//
//  main.swift
//  CPU
//
//  Created by Serhiy Mytrovtsiy on 09/04/2020.
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal let cpuDefaultText = isARM ? "$usage" : "$usage · $frequency · $temperature · $power"

public struct CPU_Load: Codable, RemoteType {
    public var totalUsage: Double = 0
    var usagePerCore: [Double] = []
    var logicalUsage: [Double?]? = nil
    var usageECores: Double? = nil
    var usagePCores: Double? = nil
    var usageSCores: Double? = nil
    
    var systemLoad: Double = 0
    var userLoad: Double = 0
    var idleLoad: Double = 0
    
    public func remote() -> String? {
        var string = "1,1,\((self.totalUsage * 10000).rounded() / 10000),\(self.usagePerCore.count)"
        for c in self.usagePerCore {
            string += ",\((c * 10000).rounded() / 10000)"
        }
        string += "$"
        return string
    }
}

public struct CPU_Frequency: Codable {
    var value: Double? = nil
    var eCore: Double? = nil
    var pCore: Double? = nil
    var sCore: Double? = nil
}

public struct IntelCPUDetails: Codable {
    var averageMHz: Double?
    var coreThreadMHz: [[Double]] = []
    var packageWatts: Double?
    var powerFromSMC: Bool = false
    var temperature: Double?
    var scheduler: Int?
    var cpus: Int?
    var speed: Int?
    var headroomMHz: Double?
    var limitReasons: [String] = []
    var frequencyDate: Date?

    static let metrics = [
        ("Average frequency", "MHz"), ("CPU temperature", "°C"), ("CPU package power", "W"),
        ("Scheduler limit", "%"), ("Speed limit", "%"), ("Available logical CPUs", ""),
        ("Frequency headroom limited", "MHz")
    ]

    static let logicalCount = Int(sysctlByName("hw.logicalcpu"))
    static let physicalCount = Int(sysctlByName("hw.physicalcpu"))

    static func threadName(_ id: Int) -> String { "\(localizedString("Logical thread")) \(id + 1)" }
    static func coreThreadName(_ core: Int, _ thread: Int) -> String {
        "\(localizedString("Physical core")) \(core) · \(localizedString("SMT")) \(thread + 1)"
    }

    static var chartMetrics: [(String, String)] {
        let threads = physicalCount > 0 ? logicalCount / physicalCount : 0
        var items = metrics.map { (localizedString($0.0), $0.1) }
        for core in 0..<physicalCount {
            for thread in 0..<threads {
                items.append((coreThreadName(core, thread), "MHz"))
            }
        }
        for thread in 0..<logicalCount {
            items.append((threadName(thread), "%"))
        }
        return items
    }

    var values: [Double?] {
        [self.averageMHz, self.temperature, self.packageWatts, self.scheduler.map(Double.init),
         self.speed.map(Double.init), self.cpus.map(Double.init), self.headroomMHz]
    }

    var formattedValues: [String?] {
        let average = self.averageMHz.map { "\(Int($0.rounded())) MHz" }
        return [average ?? (self.frequencyDate == nil ? localizedString("Awaiting sampling") : nil),
         self.temperature.map { Kit.temperature($0) },
         self.packageWatts.map { String(format: "%.1f W", $0) },
         self.scheduler.map { "\($0)%" }, self.speed.map { "\($0)%" },
         self.cpus.map { "\($0)" }, self.headroomMHz.map { "\(Int($0.rounded())) MHz" }]
    }

    var formattedReasons: String? {
        self.limitReasons.isEmpty ? nil : self.limitReasons.joined(separator: ", ")
    }

    func formattedCore(_ index: Int) -> String? {
        guard self.coreThreadMHz.indices.contains(index), !self.coreThreadMHz[index].isEmpty else { return nil }
        let threads = self.coreThreadMHz[index]
        return threads.map { String(format: "%.1f", $0) }.joined(separator: " / ") + " MHz"
    }

}

public struct CPU_AverageLoad: Codable, RemoteType {
    var load1: Double = 0
    var load5: Double = 0
    var load15: Double = 0
    
    public func remote() -> String? {
        let string = "1,1,\(self.load1),\(self.load5),\(self.load15)$"
        return string
    }
}

public class CPU: Module {
    private let popupView: Popup
    private let settingsView: Settings
    private let portalView: Portal
    private let notificationsView: Notifications
    private let previewView: Preview
    
    private var loadReader: LoadReader? = nil
    private var processReader: ProcessReader? = nil
    private var temperatureReader: TemperatureReader? = nil
    private var frequencyReader: FrequencyReader? = nil
    private var intelReader: IntelCPUReader? = nil
    private var averageLoadReader: AverageLoadReader? = nil
    
    #if arch(x86_64)
    private let intelDetailsLock = NSLock()
    private var intelDetails = IntelCPUDetails()
    #endif

    private var usagePerCoreState: Bool {
        Store.shared.bool(key: "\(self.config.name)_usagePerCore", defaultValue: false)
    }
    private var splitValueState: Bool {
        Store.shared.bool(key: "\(self.config.name)_splitValue", defaultValue: false)
    }
    private var groupByClustersState: Bool {
        Store.shared.bool(key: "\(self.config.name)_clustersGroup", defaultValue: false)
    }
    private var systemColor: NSColor {
        let color = SColor.secondRed
        let key = Store.shared.string(key: "\(self.config.name)_systemColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    private var userColor: NSColor {
        let color = SColor.secondBlue
        let key = Store.shared.string(key: "\(self.config.name)_userColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    
    private var eCoresColor: NSColor {
        let color = SColor.teal
        let key = Store.shared.string(key: "\(self.config.name)_eCoresColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    private var pCoresColor: NSColor {
        let color = SColor.indigo
        let key = Store.shared.string(key: "\(self.config.name)_pCoresColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    private var sCoresColor: NSColor {
        let color = SColor.orange
        let key = Store.shared.string(key: "\(self.config.name)_sCoresColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    
    private var systemWidgetsUpdatesState: Bool {
        self.userDefaults?.bool(forKey: "systemWidgetsUpdates_state") ?? false
    }
    
    public init() {
        let intelHistory = TelemetryHistory()
        self.settingsView = Settings(.CPU)
        self.popupView = Popup(.CPU, intelHistory: intelHistory)
        self.portalView = Portal(.CPU, height: 120)
        self.notificationsView = Notifications(.CPU)
        self.previewView = Preview(.CPU, intelHistory: intelHistory)
        
        super.init(
            moduleType: .CPU,
            popup: self.popupView,
            settings: self.settingsView,
            portal: self.portalView,
            notifications: self.notificationsView,
            preview: self.previewView
        )
        guard self.available else { return }
        
        self.loadReader = LoadReader(.CPU) { [weak self] value in
            self?.loadCallback(value)
        }
        self.processReader = ProcessReader(.CPU) { [weak self] value in
            self?.popupView.processCallback(value)
            self?.previewView.processCallback(value)
        }
        self.averageLoadReader = AverageLoadReader(.CPU, popup: true) { [weak self] value in
            self?.popupView.averageCallback(value)
            self?.previewView.averageCallback(value)
        }
        #if arch(x86_64)
        self.intelReader = IntelCPUReader(.CPU) { [weak self] value in
            guard let self, let value, self.enabled else { return }
            self.intelDetailsLock.lock()
            self.intelDetails = value
            self.intelDetailsLock.unlock()
            self.popupView.intelCallback(value)
            self.previewView.intelCallback(value)
        }
        #else
        self.temperatureReader = TemperatureReader(.CPU, popup: true) { [weak self] value in
            self?.popupView.temperatureCallback(value)
        }
        self.frequencyReader = FrequencyReader(.CPU) { [weak self] value in
            self?.popupView.frequencyCallback(value)
            self?.previewView.frequencyCallback(value)
        }
        #endif
        
        self.settingsView.callback = { [weak self] in
            self?.loadReader?.read()
        }
        self.settingsView.callbackWhenUpdateNumberOfProcesses = { [weak self] in
            guard let self else { return }
            self.popupView.numberOfProcessesUpdated()
            self.previewView.numberOfProcessesUpdated()
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.processReader?.read()
            }
        }
        self.settingsView.setInterval = { [weak self] value in
            self?.loadReader?.setInterval(value)
            self?.intelReader?.setInterval(value)
        }
        self.settingsView.setTopInterval = { [weak self] value in
            self?.processReader?.setInterval(value)
        }
        
        self.setReaders([
            self.loadReader,
            self.processReader,
            self.temperatureReader,
            self.frequencyReader,
            self.intelReader,
            self.averageLoadReader
        ])
    }
    
    private func loadCallback(_ raw: CPU_Load?) {
        guard let value = raw, self.enabled else { return }
        
        self.popupView.loadCallback(value)
        self.portalView.callback(value)
        self.notificationsView.loadCallback(value)
        self.previewView.loadCallback(value)
        self.summaryCallback(value.totalUsage)
        
        self.menuBar.widgets.filter{ $0.isActive }.forEach { [self] (w: SWidget) in
            switch w.item {
            case let widget as Mini: widget.setValue(value.totalUsage)
            case let widget as LineChart: widget.setValue(value.totalUsage)
            case let widget as BarChart:
                var val: [[ColorValue]] = [[ColorValue(value.totalUsage)]]
                let cores = SystemKit.shared.device.info.cpu?.cores ?? []
                
                if self.usagePerCoreState {
                    if widget.colorState == .cluster {
                        val = []
                        for (i, v) in value.usagePerCore.enumerated() {
                            let core = cores.first(where: {$0.id == i })
                            let color = core?.type == .efficiency ? self.eCoresColor : core?.type == .super ? self.sCoresColor : self.pCoresColor
                            val.append([ColorValue(v, color: color)])
                        }
                    } else {
                        val = value.usagePerCore.map({ [ColorValue($0)] })
                    }
                } else if self.splitValueState {
                    val = [[
                        ColorValue(value.systemLoad, color: self.systemColor),
                        ColorValue(value.userLoad, color: self.userColor)
                    ]]
                } else if self.groupByClustersState {
                    var clusters: [[ColorValue]] = []
                    var clustersPlain: [[ColorValue]] = []
                    
                    if let e = value.usageECores {
                        clusters.append([ColorValue(e, color: self.eCoresColor)])
                        clustersPlain.append([ColorValue(e)])
                    }
                    if let p = value.usagePCores {
                        clusters.append([ColorValue(p, color: self.pCoresColor)])
                        clustersPlain.append([ColorValue(p)])
                    }
                    if let s = value.usageSCores {
                        clusters.append([ColorValue(s, color: self.sCoresColor)])
                        clustersPlain.append([ColorValue(s)])
                    }
                    
                    if !clusters.isEmpty {
                        val = widget.colorState == .cluster ? clusters : clustersPlain
                    }
                }
                widget.setValue(val)
            case let widget as PieChart:
                widget.setValue([
                    ColorValue(value.systemLoad, color: self.systemColor),
                    ColorValue(value.userLoad, color: self.userColor)
                ])
            case let widget as Tachometer:
                widget.setValue([
                    ColorValue(value.systemLoad, color: self.systemColor),
                    ColorValue(value.userLoad, color: self.userColor)
                ])
            case let widget as TextWidget:
                let template = Store.shared.string(key: "CPU_textWidgetValue", defaultValue: cpuDefaultText)
                let usage = "\(Int((value.totalUsage * 100).rounded()))%"
                #if arch(x86_64)
                self.intelDetailsLock.lock()
                let details = self.intelDetails
                self.intelDetailsLock.unlock()
                let metrics: [String: String?] = [
                    "$usage": usage,
                    "$frequency": details.averageMHz.map { "\(Int($0.rounded())) MHz" },
                    "$temperature": details.temperature.map { temperature($0) },
                    "$power": details.packageWatts.map { String(format: "%.1f W", $0) },
                    "$limit": details.speed.map { "\($0)%" }
                ]
                var text = template
                for (key, replacement) in metrics {
                    text = text.replacingOccurrences(of: key, with: replacement ?? "—")
                }
                widget.setValue(text)
                #else
                widget.setValue(template.replacingOccurrences(of: "$usage", with: usage))
                #endif
            default: break
            }
        }
        
        if self.systemWidgetsUpdatesState {
            SystemWidgetUpdates.shared.update(value, key: "CPU@LoadReader", kinds: [CPU_entry.kind, "UnitedWidget"], defaults: self.userDefaults)
        }
    }
}
