//
//  popup.swift
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

internal class Popup: PopupWrapper {
    private let chartHistory = LineChartData(capacity: 180)
    private let dashboardHeight: CGFloat = 90
    private let chartHeight: CGFloat = 90 + Constants.Popup.separatorHeight
    private var detailsHeight: CGFloat { (isARM ? 22 * 4 : 22 * 7) + Constants.Popup.separatorHeight }
    private var amdFields: [NSTextField] = []
    private var amdHistory = TelemetryHistory()
    private var amdChart: TelemetryChartView?
    private var amdDeviceID: String?
    private var amdHistoryContainer: NSStackView?
    
    private let loadCache = PopupCache<GPU_Info>()
    private let processesCache = PopupCache<[TopProcess]>()
    private var processes: ProcessesView? = nil
    private var processesView: NSView? = nil
    
    private var numberOfProcesses: Int {
        #if arch(arm64)
        Store.shared.int(key: "\(self.title)_processes", defaultValue: 8)
        #else
        0
        #endif
    }
    private var processesHeight: CGFloat {
        (22*CGFloat(self.numberOfProcesses)) + (self.numberOfProcesses == 0 ? 0 : Constants.Popup.separatorHeight + 22)
    }
    
    private var usageCircle: PieChartView? = nil
    private var aneCircle: PieChartView? = nil
    private var memoryCircle: PieChartView? = nil
    
    private var chart: LineChartView? = nil
    private var lineChartHistory: Int = 180
    private var lineChartScale: Scale = .none
    private var lineChartFixedScale: Double = 1
    private var memoryLimit: Double = 0
    
    private var utilizationField: NSTextField? = nil
    private var aneField: NSTextField? = nil
    private var memoryField: NSTextField? = nil
    private var fpsField: NSTextField? = nil
    
    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        
        self.orientation = .vertical
        self.distribution = .fill
        self.spacing = 0
    }
    
    public override func loadContent() {
        self.addArrangedSubview(self.initDashboard())
        if isARM { self.addArrangedSubview(self.initChart()) }
        self.addArrangedSubview(self.initDetails())
        self.addArrangedSubview(self.initProcesses())
        if !isARM {
            let container = NSStackView()
            container.orientation = .vertical
            self.amdHistoryContainer = container
            self.addArrangedSubview(container)
            self.installAMDChart()
        }
        
        self.recalculateHeight()
    }
    
    public override func unloadContent() {
        self.processes = nil
        self.processesView = nil
        self.usageCircle = nil
        self.aneCircle = nil
        self.memoryCircle = nil
        self.chart = nil
        self.utilizationField = nil
        self.aneField = nil
        self.memoryField = nil
        self.fpsField = nil
        self.amdFields.removeAll()
        self.amdChart = nil
        self.amdHistoryContainer = nil
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func updateLayer() {
        self.chart?.display()
    }
    
    public override func appear() {
        self.replay(self.loadCache, render: self.renderLoad)
        self.replay(self.processesCache, render: self.renderProcesses)
    }
    
    public override func disappear() {
        self.processes?.setLock(false)
    }
    
    private func recalculateHeight() {
        let h = self.dashboardHeight + self.detailsHeight + self.processesHeight + (isARM ? self.chartHeight : 96)
        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }
    
    private func initDashboard() -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.dashboardHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        
        let usageSize = self.dashboardHeight-20
        let usageX = (view.frame.width - usageSize)/2
        
        let usage = NSView(frame: NSRect(x: usageX, y: (view.frame.height - usageSize)/2, width: usageSize, height: usageSize))
        let render = NSView(frame: NSRect(x: (usageX - 50)/2, y: (view.frame.height - 50)/2 - 3, width: 50, height: 50))
        let tiler = NSView(frame: NSRect(x: (usageX+usageSize) + (usageX - 50)/2, y: 0, width: 50, height: self.dashboardHeight))
        
        self.usageCircle = PieChartView(frame: NSRect(x: 0, y: 0, width: usage.frame.width, height: usage.frame.height), drawValue: true)
        self.usageCircle!.toolTip = localizedString("Utilization")
        usage.addSubview(self.usageCircle!)
        
        if isARM {
            self.aneCircle = PieChartView(frame: render.bounds, drawValue: true)
            self.aneCircle!.toolTip = localizedString("ANE utilization")
            render.addSubview(self.aneCircle!)
        } else {
            self.usageCircle?.isHidden = true
            self.memoryCircle?.isHidden = true
        }
        
        self.memoryCircle = PieChartView(frame: NSRect(x: 0, y: 0, width: tiler.frame.width, height: tiler.frame.height), drawValue: true)
        self.memoryCircle!.toolTip = localizedString("Memory usage")
        self.memoryCircle?.isHidden = !isARM
        tiler.addSubview(self.memoryCircle!)
        
        view.addSubview(render)
        view.addSubview(usage)
        view.addSubview(tiler)
        
        return view
    }
    
    private func initChart() -> NSView  {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.chartHeight))
        view.heightAnchor.constraint(equalToConstant: 90 + Constants.Popup.separatorHeight).isActive = true
        let separator = separatorView(localizedString("Usage history"), origin: NSPoint(x: 0, y: self.chartHeight-Constants.Popup.separatorHeight), width: self.frame.width)
        let container: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: separator.frame.origin.y))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
        container.layer?.cornerRadius = Constants.Popup.radius
        
        let chartFrame = NSRect(x: 1, y: 0, width: view.frame.width - 2, height: container.frame.height)
        self.chart = LineChartView(frame: chartFrame, scale: self.lineChartScale, fixedScale: self.lineChartFixedScale, history: self.chartHistory)
        container.addSubview(self.chart!)
        
        view.addSubview(separator)
        view.addSubview(container)
        
        return view
    }
    
    private func initDetails() -> NSView  {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.detailsHeight))
        view.heightAnchor.constraint(equalToConstant: self.detailsHeight).isActive = true
        let separator = separatorView(localizedString("Details"), origin: NSPoint(x: 0, y: self.detailsHeight-Constants.Popup.separatorHeight), width: self.frame.width)
        let container: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: separator.frame.origin.y))
        container.orientation = .vertical
        container.spacing = 0
        
        if isARM {
            self.utilizationField = popupRow(container, title: localizedString("Utilization"), value: "").1
            self.aneField = popupRow(container, title: localizedString("ANE utilization"), value: "").1
            self.memoryField = popupRow(container, title: localizedString("Memory usage"), value: "").1
            self.fpsField = popupRow(container, title: "FPS", value: "").1
        } else {
            self.amdFields = GPU_Info.amdMetrics.map {
                popupRow(container, title: localizedString($0.0), value: localizedString("Unavailable")).1
            }
        }

        view.addSubview(separator)
        view.addSubview(container)
        
        return view
    }
    
    private func initProcesses() -> NSView {
        if self.numberOfProcesses == 0 {
            let v = NSView()
            v.heightAnchor.constraint(equalToConstant: 0).isActive = true
            self.processesView = v
            return v
        }
        
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.processesHeight))
        view.heightAnchor.constraint(equalToConstant: self.processesHeight).isActive = true
        let separator = separatorView(localizedString("Top processes"), origin: NSPoint(x: 0, y: self.processesHeight-Constants.Popup.separatorHeight), width: self.frame.width)
        let container: ProcessesView = ProcessesView(
            frame: NSRect(x: 0, y: 0, width: self.frame.width, height: separator.frame.origin.y),
            values: [(localizedString("Usage"), nil)],
            n: self.numberOfProcesses
        )
        self.processes = container
        
        view.addSubview(separator)
        view.addSubview(container)
        
        self.processesView = view
        return view
    }
    
    // MARK: - Callback
    
    public func processCallback(_ list: [TopProcess]?) {
        guard let list else { return }
        self.apply(list, to: self.processesCache, render: self.renderProcesses)
    }
    
    private func renderProcesses(_ list: [TopProcess]) {
        guard let view = self.processes else { return }
        
        for i in 0..<view.count {
            if list.indices.contains(i) {
                let process = list[i]
                view.set(i, process, [String(format: "%.1f%%", process.usage)])
            } else {
                view.set(i, nil, [])
            }
        }
    }
    
    public func numberOfProcessesUpdated() {
        guard self.contentLoaded else { return }
        if self.processes?.count == self.numberOfProcesses { return }
        
        self.processesView?.removeFromSuperview()
        self.processesView = nil
        self.processes = nil
        self.addArrangedSubview(self.initProcesses())
        self.replay(self.processesCache, render: self.renderProcesses)
        self.recalculateHeight()
    }
    
    private func installAMDChart() {
        guard let container = self.amdHistoryContainer else { return }
        self.amdChart?.removeFromSuperview()
        let chart = TelemetryChartView(width: self.frame.width, metrics: GPU_Info.amdChartMetrics, history: self.amdHistory)
        self.amdChart = chart
        container.addArrangedSubview(chart)
    }

    public func loadCallback(_ value: GPU_Info) {
        let date = Date()
        self.apply(value, to: self.loadCache, render: self.renderLoad)
        DispatchQueue.main.async {
            if !isARM {
                if !value.id.isEmpty, self.amdDeviceID != value.id {
                    self.amdDeviceID = value.id
                    self.amdHistory = TelemetryHistory()
                    self.installAMDChart()
                }
                for (metric, reading) in zip(GPU_Info.amdMetrics, value.amdReadings) {
                    self.amdHistory.append(localizedString(metric.0), reading, at: date)
                }
                self.amdChart?.historyUpdated()
            } else if let utilization = value.utilization {
                let sample = DoubleValue(utilization, at: date)
                self.chartHistory.append(sample)
                self.chart?.historyUpdated()
            }
        }
    }
    
    private func renderLoad(_ value: GPU_Info) {
        if !isARM {
            self.usageCircle?.isHidden = value.utilization == nil
            for (index, metric) in GPU_Info.amdMetrics.enumerated() where self.amdFields.indices.contains(index) {
                self.amdFields[index].stringValue = value.text(for: metric.1) ?? localizedString("Unavailable")
            }
            if let bytes = value.memory, let limit = value.memoryLimit, limit > 0 {
                self.memoryCircle?.isHidden = false
                self.memoryCircle?.setValue(min(bytes / limit, 1))
                self.memoryCircle?.toolTip = value.text(for: "$memory")
            } else {
                self.memoryCircle?.isHidden = true
            }
        }
        if let utilization = value.utilization {
            self.usageCircle?.toolTip = "\(localizedString("GPU utilization")): \(Int(utilization.rounded(toPlaces: 2) * 100))%"
            self.usageCircle?.setValue(utilization)
            self.usageCircle?.display()
            self.utilizationField?.stringValue = "\(Int(utilization*100))%"
        }
        if let utilization = value.aneUtilization {
            self.aneCircle?.toolTip = "\(localizedString("ANE utilization")): \(Int(utilization.rounded(toPlaces: 2) * 100))%"
            self.aneCircle?.setValue(utilization)
            self.aneCircle?.display()
            self.aneField?.stringValue = "\(Int(utilization*100))%"
        }
        if isARM, let v = value.memory {
            let str = Units(bytes: Int64(v)).getReadableMemory(style: .memory)
            self.memoryField?.stringValue = str
            
            if let limit = value.memoryLimit, limit != 0 {
                self.memoryLimit = limit
            } else if v > self.memoryLimit {
                self.memoryLimit = v
            }
            
            if let circle = self.memoryCircle {
                circle.setValue((100*v)/self.memoryLimit)
                circle.toolTip = "\(localizedString("Memory usage")): \(str)%"
                circle.display()
            }
        }
        self.aneCircle?.isHidden = value.aneUtilization == nil
        if value.aneUtilization == nil { self.aneField?.stringValue = localizedString("Unavailable") }
        if let fps = value.fps {
            self.fpsField?.stringValue = "\(Int(fps.rounded()))"
        } else {
            self.fpsField?.stringValue = localizedString("Unavailable")
        }
        
        self.chart?.display()
    }
    
    // MARK: - Settings
    
    public override func settings() -> NSView? {
        let view = SettingsContainerView()
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Keyboard shortcut"), component: KeyboardShartcutView(
                callback: self.setKeyboardShortcut,
                value: self.keyboardShortcut
            ))
        ]))
        
        return view
    }
}
