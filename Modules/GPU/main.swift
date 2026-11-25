//
//  main.swift
//  GPU
//
//  Created by Serhiy Mytrovtsiy on 17/08/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

public typealias GPU_type = String
public enum GPU_types: GPU_type {
    case unknown = ""
    
    case integrated = "i"
    case external = "e"
    case discrete = "d"
}

public struct GPU_Info: Codable {
    public let id: String
    public let type: GPU_type
    
    public let IOClass: String
    public let model: String
    
    public var state: Bool = true
    
    public var utilization: Double? = nil
    public var renderUtilization: Double? = nil
    public var tilerUtilization: Double? = nil
    public var aneUtilization: Double? = nil
    
    public var fps: Double? = nil
    
    public var memory: Double? = nil
    public var memoryLimit: Double? = nil
    public var temperature: Double? = nil
    public var coreMHz: Double? = nil
    public var memoryMHz: Double? = nil
    public var fanRPM: Double? = nil
    public var driverWatts: Double? = nil

    static let amdMetrics = [
        ("Utilization", "$usage", "%"), ("Temperature", "$temperature", "°C"),
        ("Core clock", "$core", "MHz"), ("Memory clock", "$memclock", "MHz"),
        ("Fan speed", "$fan", "RPM"), ("Driver power", "$power", "W"), ("VRAM used", "$memory", "MiB")
    ]

    static var amdChartMetrics: [(String, String)] {
        amdMetrics.map { (localizedString($0.0), $0.2) }
    }

    var amdReadings: [Double?] {
        [self.utilization.map { $0 * 100 }, self.temperature, self.coreMHz,
         self.memoryMHz, self.fanRPM, self.driverWatts, self.memory.map { $0 / 1_048_576 }]
    }

    internal func text(for key: String) -> String? {
        switch key {
        case "$usage": return self.utilization.map { "\(Int(($0 * 100).rounded()))%" }
        case "$render": return self.renderUtilization.map { "\(Int(($0 * 100).rounded()))%" }
        case "$tiler": return self.tilerUtilization.map { "\(Int(($0 * 100).rounded()))%" }
        case "$ane": return self.aneUtilization.map { "\(Int(($0 * 100).rounded()))%" }
        case "$memory": return self.memory.map { Units(bytes: Int64($0)).getReadableMemory(style: .memory) }
        case "$fps": return self.fps.map { "\(Int($0.rounded()))" }
        case "$temperature": return self.temperature.map { Kit.temperature($0) }
        case "$core": return self.coreMHz.map { "\(Int($0.rounded())) MHz" }
        case "$memclock": return self.memoryMHz.map { "\(Int($0.rounded())) MHz" }
        case "$fan": return self.fanRPM.map { "\(Int($0.rounded())) RPM" }
        case "$power": return self.driverWatts.map { String(format: "%.1f W", $0) }
        default: return nil
        }
    }
    
    init(id: String, type: GPU_type, IOClass: String, model: String, utilization: Double? = nil, render: Double? = nil, tiler: Double? = nil) {
        self.id = id
        self.type = type
        self.IOClass = IOClass
        self.model = model
        self.utilization = utilization
        self.renderUtilization = render
        self.tilerUtilization = tiler
    }
    
    public func remote() -> String {
        var id = self.id
        if self.id.isEmpty {
            id = "0"
        }
        return "\(id),1,\(self.utilization ?? 0),\(self.renderUtilization ?? 0),\(self.tilerUtilization ?? 0),,"
    }
}

public class GPUs: Codable, RemoteType {
    private var queue: DispatchQueue = DispatchQueue(label: "eu.exelban.Stats.GPU.SynchronizedArray")
    
    private var _list: [GPU_Info] = []
    public var list: [GPU_Info] {
        get { self.queue.sync { self._list } }
        set { self.queue.sync { self._list = newValue } }
    }
    
    enum CodingKeys: String, CodingKey {
        case list
    }
    
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.list = try container.decode(Array<GPU_Info>.self, forKey: CodingKeys.list)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.list, forKey: .list)
    }
    
    init() {}
    
    internal func active() -> [GPU_Info] {
        return self.list.filter { $0.state && ($0.utilization != nil || $0.IOClass == "AMD") }
            .sorted { ($0.utilization ?? -1) > ($1.utilization ?? -1) }
    }
    
    public func remote() -> String? {
        let list = self.list
        var string = "\(list.count)"
        for v in list {
            string += ",\(v.remote())"
        }
        string += "$"
        return string
    }
}

public class GPU: Module {
    private let popupView: Popup
    private let settingsView: Settings
    private let portalView: Portal
    private let notificationsView: Notifications
    private let previewView: Preview
    
    private var infoReader: InfoReader? = nil
    private var processReader: ProcessReader? = nil
    
    private var selectedGPU: String = ""
    
    private var showType: Bool {
        Store.shared.bool(key: "\(self.config.name)_showType", defaultValue: false)
    }
    
    private var systemWidgetsUpdatesState: Bool {
        self.userDefaults?.bool(forKey: "systemWidgetsUpdates_state") ?? false
    }
    
    private var textValue: String {
        Store.shared.string(key: "\(self.name)_textWidgetValue", defaultValue: gpuDefaultText)
    }
    
    public init() {
        self.popupView = Popup(.GPU)
        self.settingsView = Settings(.GPU)
        self.portalView = Portal(.GPU, height: 70)
        self.notificationsView = Notifications(.GPU)
        self.previewView = Preview(.GPU)
        
        super.init(
            moduleType: .GPU,
            popup: self.popupView,
            settings: self.settingsView,
            portal: self.portalView,
            notifications: self.notificationsView,
            preview: self.previewView,
        )
        guard self.available else { return }
        
        self.infoReader = InfoReader(.GPU) { [weak self] value in
            self?.infoCallback(value)
        }
        #if arch(arm64)
        self.processReader = ProcessReader(.GPU) { [weak self] value in
            self?.popupView.processCallback(value)
            self?.previewView.processCallback(value)
        }
        #endif
        self.selectedGPU = Store.shared.string(key: "\(self.config.name)_gpu", defaultValue: self.selectedGPU)
        
        self.settingsView.selectedGPUHandler = { [weak self] value in
            self?.selectedGPU = value
            self?.infoReader?.read()
        }
        self.settingsView.setInterval = { [weak self] value in
            self?.infoReader?.setInterval(value)
        }
        self.settingsView.callback = { [weak self] in
            self?.infoReader?.read()
        }
        self.settingsView.callbackWhenUpdateNumberOfProcesses = { [weak self] in
            guard let self else { return }
            self.popupView.numberOfProcessesUpdated()
            self.previewView.numberOfProcessesUpdated()
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.processReader?.read()
            }
        }
        self.settingsView.setTopInterval = { [weak self] value in
            self?.processReader?.setInterval(value)
        }
        
        self.setReaders([self.infoReader, self.processReader])
    }
    
    private func infoCallback(_ raw: GPUs?) {
        guard self.enabled else { return }
        guard let value = raw else {
            self.summaryCallback(nil)
            return
        }
        
        self.settingsView.setList(value)
        
        let activeGPUs = value.active()
        let selectedGPU = activeGPUs.first { $0.model == self.selectedGPU } ?? activeGPUs.first
        let utilization = selectedGPU?.utilization
        self.summaryCallback(utilization)

        if let selectedGPU {
            self.popupView.loadCallback(selectedGPU)
            self.portalView.callback(selectedGPU)
            self.previewView.loadCallback(selectedGPU)
        } else if !isARM {
            let unavailable = GPU_Info(id: "", type: "", IOClass: "", model: "")
            self.popupView.loadCallback(unavailable)
            self.previewView.loadCallback(unavailable)
        }
        if let utilization { self.notificationsView.usageCallback(utilization) }

        self.menuBar.widgets.filter { $0.isActive }.forEach { w in
            if let widget = w.item as? TextWidget {
                let text = self.textValue
                var rendered = text
                for pair in TextWidget.parseText(text).sorted(by: { $0.key.count > $1.key.count }) {
                    let key = pair.value.isEmpty ? pair.key : "\(pair.key).\(pair.value)"
                    let replacement = selectedGPU?.text(for: pair.key) ?? "—"
                    rendered = rendered.replacingOccurrences(of: key, with: replacement)
                }
                widget.setValue(rendered)
                return
            }
            guard let selectedGPU, let utilization else { return }
            switch w.item {
            case let widget as Mini:
                widget.setValue(utilization)
                widget.setTitle(self.showType ? "\(selectedGPU.type)GPU" : nil)
            case let widget as LineChart: widget.setValue(utilization)
            case let widget as BarChart: widget.setValue([[ColorValue(utilization)]])
            case let widget as Tachometer: widget.setValue([ColorValue(utilization, color: NSColor.systemBlue)])
            default: break
            }
        }

        if self.systemWidgetsUpdatesState, let selectedGPU {
            SystemWidgetUpdates.shared.update(selectedGPU, key: "GPU@InfoReader", kinds: [GPU_entry.kind, "UnitedWidget"], defaults: self.userDefaults)
        }
    }
}
