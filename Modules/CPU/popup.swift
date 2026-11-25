//
//  popup.swift
//  CPU
//
//  Created by Serhiy Mytrovtsiy on 15/04/2020.
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
    private let chartHeight: CGFloat = 120 + Constants.Popup.separatorHeight + Constants.Popup.spacing*2
    private var detailsHeight: CGFloat {
        get {
            var count: CGFloat = isARM ? 4 : 11
            if SystemKit.shared.device.info.cpu?.eCores != nil {
                count += 1
            }
            if SystemKit.shared.device.info.cpu?.sCores != nil {
                count += 1
            }
            if SystemKit.shared.device.info.cpu?.pCores != nil {
                count += 1
            }
            return (22*count) + Constants.Popup.separatorHeight
        }
    }
    private let averageHeight: CGFloat = (22*3) + Constants.Popup.separatorHeight
    private var frequencyHeight: CGFloat {
        get {
            var count: CGFloat = 1
            if SystemKit.shared.device.info.cpu?.eCores != nil {
                count += 1
            }
            if SystemKit.shared.device.info.cpu?.sCores != nil {
                count += 1
            }
            if SystemKit.shared.device.info.cpu?.pCores != nil {
                count += 1
            }
            return (22*count) + Constants.Popup.separatorHeight
        }
    }
    private let processHeight: CGFloat = 22
    
    private var systemField: NSTextField? = nil
    private var userField: NSTextField? = nil
    private var idleField: NSTextField? = nil
    private var eCoresField: NSTextField? = nil
    private var pCoresField: NSTextField? = nil
    private var sCoresField: NSTextField? = nil
    private var uptimeField: NSTextField? = nil
    private var average1Field: NSTextField? = nil
    private var average5Field: NSTextField? = nil
    private var average15Field: NSTextField? = nil
    private var coresFreqField: NSTextField? = nil
    private var eCoresFreqField: NSTextField? = nil
    private var pCoresFreqField: NSTextField? = nil
    private var sCoresFreqField: NSTextField? = nil
    private var eCoresFreqColorView: NSView? = nil
    private var pCoresFreqColorView: NSView? = nil
    private var sCoresFreqColorView: NSView? = nil
    
    private var systemColorView: NSView? = nil
    private var userColorView: NSView? = nil
    private var idleColorView: NSView? = nil
    private var eCoresColorView: NSView? = nil
    private var pCoresColorView: NSView? = nil
    private var sCoresColorView: NSView? = nil
    
    private var chartPrefSection: PreferencesSection? = nil
    private var sliderView: NSView? = nil
    
    private var lineChart: LineChartView? = nil
    private var columnChart: ColumnChartView? = nil
    private var circle: PieChartView? = nil
    private var temperatureCircle: PieChartView? = nil
    private var frequencyCircle: PieChartView? = nil
    
    private let processCache = PopupCache<[TopProcess]>()
    private let loadCache = PopupCache<CPU_Load>()
    private let temperatureCache = PopupCache<Double>()
    private let frequencyCache = PopupCache<CPU_Frequency>()
    private let intelCache = PopupCache<IntelCPUDetails>()
    private let intelHistory: TelemetryHistory
    private var intelChart: TelemetryChartView?
    private var intelFields: [String: NSTextField] = [:]
    private var intelCoreText: NSTextField?
    private var lastFrequencyDate: Date?

    private let averageCache = PopupCache<CPU_AverageLoad>()
    
    private var processes: ProcessesView? = nil
    private var maxFreq: Double = 0
    private var lineChartHistory: Int = 180
    private var lineChartScale: Scale = .none
    private var lineChartFixedScale: Double = 1
    
    private var systemColorState: SColor = .secondRed
    private var systemColor: NSColor { self.systemColorState.additional as? NSColor ?? NSColor.systemRed }
    private var userColorState: SColor = .secondBlue
    private var userColor: NSColor { self.userColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var idleColorState: SColor = .lightGray
    private var idleColor: NSColor { self.idleColorState.additional as? NSColor ?? NSColor.lightGray }
    private var chartColorState: SColor = .systemAccent
    private var chartColor: NSColor { self.chartColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var eCoresColorState: SColor = .teal
    private var eCoresColor: NSColor { self.eCoresColorState.additional as? NSColor ?? NSColor.systemTeal }
    private var pCoresColorState: SColor = .indigo
    private var pCoresColor: NSColor { self.pCoresColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var sCoresColorState: SColor = .orange
    private var sCoresColor: NSColor { self.sCoresColorState.additional as? NSColor ?? NSColor.systemOrange }
    
    private var processesView: NSView? = nil
    
    private var numberOfProcesses: Int {
        Store.shared.int(key: "\(self.title)_processes", defaultValue: 8)
    }
    private var processesHeight: CGFloat {
        (self.processHeight*CGFloat(self.numberOfProcesses)) + (self.numberOfProcesses == 0 ? 0 : Constants.Popup.separatorHeight + 22)
    }
    private var uptimeValue: String {
        let form = DateComponentsFormatter()
        form.maximumUnitCount = 2
        form.unitsStyle = .full
        form.allowedUnits = [.day, .hour, .minute]
        var value = localizedString("Unknown")
        if let bootDate = SystemKit.shared.device.bootDate {
            if let duration = form.string(from: bootDate, to: Date()) {
                value = duration
            }
        }
        return value
    }
    
    public init(_ module: ModuleType, intelHistory: TelemetryHistory) {
        self.intelHistory = intelHistory
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        
        self.spacing = 0
        self.orientation = .vertical
        
        self.systemColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_systemColor", defaultValue: self.systemColorState.key))
        self.userColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_userColor", defaultValue: self.userColorState.key))
        self.idleColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_idleColor", defaultValue: self.idleColorState.key))
        self.chartColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_chartColor", defaultValue: self.chartColorState.key))
        self.eCoresColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_eCoresColor", defaultValue: self.eCoresColorState.key))
        self.pCoresColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_pCoresColor", defaultValue: self.pCoresColorState.key))
        self.sCoresColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_sCoresColor", defaultValue: self.sCoresColorState.key))
        self.lineChartHistory = Store.shared.int(key: "\(self.title)_lineChartHistory", defaultValue: self.lineChartHistory)
        self.chartHistory.resize(self.lineChartHistory)
        self.lineChartScale = Scale.fromString(Store.shared.string(key: "\(self.title)_lineChartScale", defaultValue: self.lineChartScale.key))
        self.lineChartFixedScale = Double(Store.shared.int(key: "\(self.title)_lineChartFixedScale", defaultValue: 100)) / 100
    }
    
    public override func loadContent() {
        self.addArrangedSubview(self.initDashboard())
        self.addArrangedSubview(self.initChart())
        self.addArrangedSubview(self.initDetails())
        self.addArrangedSubview(self.initAverage())
        self.addArrangedSubview(self.initProcesses())
        if isARM {
            self.replay(self.frequencyCache, render: self.renderFrequency)
        } else {
            self.insertArrangedSubview(self.initIntelFrequency(), at: 4)
        }
        
        self.recalculateHeight()
    }
    
    public override func unloadContent() {
        self.systemField = nil
        self.userField = nil
        self.idleField = nil
        self.intelFields.removeAll()
        self.intelCoreText = nil
        self.intelChart = nil
        self.eCoresField = nil
        self.pCoresField = nil
        self.sCoresField = nil
        self.uptimeField = nil
        self.average1Field = nil
        self.average5Field = nil
        self.average15Field = nil
        self.coresFreqField = nil
        self.eCoresFreqField = nil
        self.pCoresFreqField = nil
        self.sCoresFreqField = nil
        self.eCoresFreqColorView = nil
        self.pCoresFreqColorView = nil
        self.sCoresFreqColorView = nil
        self.systemColorView = nil
        self.userColorView = nil
        self.idleColorView = nil
        self.eCoresColorView = nil
        self.pCoresColorView = nil
        self.sCoresColorView = nil
        self.lineChart = nil
        self.columnChart = nil
        self.circle = nil
        self.temperatureCircle = nil
        self.frequencyCircle = nil
        self.processes = nil
        self.processesView = nil
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func updateLayer() {
        self.lineChart?.display()
    }
    
    public override func appear() {
        self.uptimeField?.stringValue = self.uptimeValue
        self.replay(self.loadCache, render: self.renderLoad)
        self.replay(self.temperatureCache, render: self.renderTemperature)
        self.replay(self.frequencyCache, render: self.renderFrequency)
        self.replay(self.intelCache, render: self.renderIntel)
        self.replay(self.averageCache, render: self.renderAverage)
        self.replay(self.processCache, render: self.renderProcesses)
    }
    
    public override func disappear() {
        self.processes?.setLock(false)
    }
    
    private func recalculateHeight() {
        var h: CGFloat = 0
        self.arrangedSubviews.forEach { v in
            if let v = v as? NSStackView {
                h += v.arrangedSubviews.map({ $0.bounds.height + v.spacing }).reduce(0, +)
            } else {
                h += v.bounds.height
            }
        }
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
        let temperature = NSView(frame: NSRect(x: (usageX - 50)/2, y: (view.frame.height - 50)/2 - 3, width: 50, height: 50))
        let frequency = NSView(frame: NSRect(x: (usageX+usageSize) + (usageX - 50)/2, y: 0, width: 50, height: self.dashboardHeight))
        
        self.circle = PieChartView(frame: NSRect(x: 0, y: 0, width: usage.frame.width, height: usage.frame.height), segments: [], drawValue: true)
        self.circle!.toolTip = localizedString("CPU usage")
        usage.addSubview(self.circle!)
        
        self.temperatureCircle = PieChartView(frame: NSRect(x: 0, y: 0, width: temperature.frame.width, height: temperature.frame.height))
        self.temperatureCircle!.toolTip = localizedString("CPU temperature")
        (self.temperatureCircle! as NSView).isHidden = true
        temperature.addSubview(self.temperatureCircle!)
        
        self.frequencyCircle = PieChartView(frame: NSRect(x: 0, y: 0, width: frequency.frame.width, height: frequency.frame.height))
        self.frequencyCircle!.toolTip = localizedString("CPU frequency")
        (self.frequencyCircle! as NSView).isHidden = true
        frequency.addSubview(self.frequencyCircle!)
        
        view.addSubview(temperature)
        view.addSubview(usage)
        view.addSubview(frequency)
        
        return view
    }
    
    private func initChart() -> NSView {
        let view: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.chartHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        view.orientation = .vertical
        view.spacing = Constants.Popup.spacing
        
        let separator = separatorView(localizedString("Usage history"), origin: NSPoint(x: 0, y: 0), width: self.frame.width)
        
        let lineChartContainer: NSView = {
            let box: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 70))
            box.heightAnchor.constraint(equalToConstant: box.frame.height).isActive = true
            box.wantsLayer = true
            box.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
            box.layer?.cornerRadius = Constants.Popup.radius
            
            let chartFrame = NSRect(x: 1, y: 0, width: box.frame.width - 2, height: box.frame.height)
            self.lineChart = LineChartView(frame: chartFrame, scale: self.lineChartScale, fixedScale: self.lineChartFixedScale, history: self.chartHistory)
            self.lineChart?.setColor(self.chartColor)
            box.addSubview(self.lineChart!)
            
            return box
        }()
        
        view.addArrangedSubview(separator)
        view.addArrangedSubview(lineChartContainer)
        
        if let cores = isARM ? SystemKit.shared.device.info.cpu?.logicalCores.map(Int.init) : IntelCPUDetails.logicalCount, cores > 0 {
            let barChartContainer: NSView = {
                let box: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 50))
                box.heightAnchor.constraint(equalToConstant: box.frame.height).isActive = true
                box.wantsLayer = true
                box.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
                box.layer?.cornerRadius = 3
                
                let chart = ColumnChartView(frame: NSRect(
                    x: Constants.Popup.spacing,
                    y: Constants.Popup.spacing,
                    width: view.frame.width - (Constants.Popup.spacing*2),
                    height: box.frame.height - (Constants.Popup.spacing*2)
                ), num: cores)
                self.columnChart = chart
                
                box.addSubview(chart)
                
                return box
            }()
            if !isARM {
                view.addArrangedSubview(separatorView(localizedString("Logical thread usage"), origin: .zero, width: self.frame.width))
            }
            view.addArrangedSubview(barChartContainer)
        }
        
        return view
    }
    
    private func initDetails() -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.detailsHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        let separator = separatorView(localizedString("Details"), origin: NSPoint(
            x: 0,
            y: self.detailsHeight-Constants.Popup.separatorHeight
        ), width: self.frame.width)
        let container: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: separator.frame.origin.y))
        container.orientation = .vertical
        container.spacing = 0
        
        (self.systemColorView, _, self.systemField) = popupWithColorRow(container, color: self.systemColor, title: "\(localizedString("System")):", value: "")
        (self.userColorView, _, self.userField) = popupWithColorRow(container, color: self.userColor, title: "\(localizedString("User")):", value: "")
        (self.idleColorView, _, self.idleField) = popupWithColorRow(container, color: self.idleColor.withAlphaComponent(0.5), title: "\(localizedString("Idle")):", value: "")
        
        if !isARM {
            for (name, _) in IntelCPUDetails.metrics.dropFirst() {
                self.intelFields[name] = popupRow(container, title: localizedString(name), value: localizedString("Unavailable")).1
            }
            self.intelFields["Reported limit reasons"] = popupRow(
                container, title: localizedString("Reported limit reasons"), value: localizedString("Unavailable")
            ).1
        }

        if SystemKit.shared.device.info.cpu?.eCores != nil {
            (self.eCoresColorView, _, self.eCoresField) = popupWithColorRow(container, color: self.eCoresColor, title: "\(localizedString("Efficiency cores")):", value: "")
        }
        if SystemKit.shared.device.info.cpu?.pCores != nil {
            (self.pCoresColorView, _, self.pCoresField) = popupWithColorRow(container, color: self.pCoresColor, title: "\(localizedString("Performance cores")):", value: "")
        }
        if SystemKit.shared.device.info.cpu?.sCores != nil {
            (self.sCoresColorView, _, self.sCoresField) = popupWithColorRow(container, color: self.sCoresColor, title: "\(localizedString("Super cores")):", value: "")
        }
        
        self.uptimeField = popupRow(container, title: "\(localizedString("Uptime")):", value: self.uptimeValue).1
        self.uptimeField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        
        view.addSubview(separator)
        view.addSubview(container)
        
        return view
    }
    
    private func initAverage() -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.averageHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        let separator = separatorView(localizedString("Average load"), origin: NSPoint(x: 0, y: self.averageHeight-Constants.Popup.separatorHeight), width: self.frame.width)
        let container: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: separator.frame.origin.y))
        container.orientation = .vertical
        container.spacing = 0
        
        self.average1Field = popupRow(container, title: "\(localizedString("1 minute")):", value: "").1
        self.average5Field = popupRow(container, title: "\(localizedString("5 minutes")):", value: "").1
        self.average15Field = popupRow(container, title: "\(localizedString("15 minutes")):", value: "").1
        
        view.addSubview(separator)
        view.addSubview(container)
        
        return view
    }
    
    private func initIntelFrequency() -> NSView {
        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 0))
        view.orientation = .vertical
        view.spacing = 0
        view.addArrangedSubview(separatorView(localizedString("Frequency"), origin: .zero, width: self.frame.width))
        self.intelFields["Average frequency"] = popupRow(
            view, title: localizedString("Average frequency"), value: localizedString("Awaiting sampling")
        ).1
        view.addArrangedSubview(separatorView(localizedString("Physical cores · SMT frequency averages"), origin: .zero, width: self.frame.width))

        let scroller = NSScrollView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 72))
        scroller.heightAnchor.constraint(equalToConstant: 72).isActive = true
        scroller.hasVerticalScroller = true
        scroller.drawsBackground = false
        let text = NSTextField(wrappingLabelWithString: localizedString("Unavailable"))
        text.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let document = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width - 12, height: 72))
        document.addSubview(text)
        text.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 7),
            text.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor),
            text.topAnchor.constraint(equalTo: document.topAnchor, constant: 3)
        ])
        scroller.documentView = document
        self.intelCoreText = text
        view.addArrangedSubview(scroller)

        let chart = TelemetryChartView(width: self.frame.width, metrics: IntelCPUDetails.chartMetrics, history: self.intelHistory)
        self.intelChart = chart
        view.addArrangedSubview(chart)
        return view
    }

    private func initFrequency() -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.frequencyHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        let separator = separatorView(localizedString("Frequency"), origin: NSPoint(x: 0, y: self.frequencyHeight-Constants.Popup.separatorHeight), width: self.frame.width)
        let container: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: separator.frame.origin.y))
        container.orientation = .vertical
        container.spacing = 0
        
        self.coresFreqField = popupRow(container, title: "\(localizedString("All cores")):", value: "").1
        
        if isARM {
            if SystemKit.shared.device.info.cpu?.eCores != nil {
                (self.eCoresFreqColorView, _, self.eCoresFreqField) = popupWithColorRow(container, color: self.eCoresColor, title: "\(localizedString("Efficiency cores")):", value: "")
            }
            if SystemKit.shared.device.info.cpu?.pCores != nil {
                (self.pCoresFreqColorView, _, self.pCoresFreqField) = popupWithColorRow(container, color: self.pCoresColor, title: "\(localizedString("Performance cores")):", value: "")
            }
            if SystemKit.shared.device.info.cpu?.sCores != nil {
                (self.sCoresFreqColorView, _, self.sCoresFreqField) = popupWithColorRow(container, color: self.sCoresColor, title: "\(localizedString("Super cores")):", value: "")
            }
        }
        
        view.addSubview(separator)
        view.addSubview(container)
        
        return view
    }
    
    private func initProcesses() -> NSView {
        if self.numberOfProcesses == 0 {
            let v = NSView()
            self.processesView = v
            return v
        }
        
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.processesHeight))
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
    
    public func loadCallback(_ value: CPU_Load) {
        let date = Date()
        self.apply(value, to: self.loadCache, render: self.renderLoad)
        DispatchQueue.main.async {
            let sample = DoubleValue(value.totalUsage, at: date)
            self.chartHistory.append(sample)
            self.lineChart?.historyUpdated()
            if let logical = value.logicalUsage {
                for (index, usage) in logical.enumerated() {
                    self.intelHistory.append(IntelCPUDetails.threadName(index), usage.map { $0 * 100 }, at: date)
                }
                self.intelChart?.historyUpdated()
            }
        }
    }
    
    private func renderLoad(_ value: CPU_Load) {
        self.systemField?.stringValue = "\(Int(value.systemLoad.rounded(toPlaces: 2) * 100))%"
        self.userField?.stringValue = "\(Int(value.userLoad.rounded(toPlaces: 2) * 100))%"
        self.idleField?.stringValue = "\(Int(value.idleLoad.rounded(toPlaces: 2) * 100))%"
        
        self.circle?.toolTip = "\(localizedString("CPU usage")): \(Int(value.totalUsage.rounded(toPlaces: 2) * 100))%"
        self.circle?.setValue(value.totalUsage)
        self.circle?.setSegments([
            ColorValue(value.systemLoad, color: self.systemColor),
            ColorValue(value.userLoad, color: self.userColor)
        ])
        self.circle?.setNonActiveSegmentColor(self.idleColor)
        self.circle?.display()
        
        if let field = self.eCoresField, let usage = value.usageECores {
            field.stringValue = "\(Int(usage * 100))%"
        }
        if let field = self.pCoresField, let usage = value.usagePCores {
            field.stringValue = "\(Int(usage * 100))%"
        }
        if let field = self.sCoresField, let usage = value.usageSCores {
            field.stringValue = "\(Int(usage * 100))%"
        }
        
        var usagePerCore: [ColorValue] = []
        if let cores = SystemKit.shared.device.info.cpu?.cores, !cores.isEmpty {
            for i in 0..<value.usagePerCore.count {
                let core = cores.first(where: { $0.id == i })
                let color = core?.type == .efficiency ? self.eCoresColor : core?.type == .super ? self.sCoresColor : self.pCoresColor
                usagePerCore.append(ColorValue(value.usagePerCore[i], color: color))
            }
        } else {
            for i in 0..<value.usagePerCore.count {
                usagePerCore.append(ColorValue(value.usagePerCore[i], color: NSColor.systemBlue))
            }
        }
        if isARM {
            self.columnChart?.setValues(usagePerCore)
        } else {
            let logical = value.logicalUsage ?? [Double?](repeating: nil, count: IntelCPUDetails.logicalCount)
            self.columnChart?.setOptionalValues(logical, label: localizedString("Logical thread"))
        }
        self.columnChart?.display()
        
        self.lineChart?.display()
    }
    
    public func temperatureCallback(_ value: Double?) {
        guard let value else { return }
        self.apply(value, to: self.temperatureCache, render: self.renderTemperature)
    }
    
    private func renderTemperature(_ value: Double) {
        if let view = self.temperatureCircle, (view as NSView).isHidden {
            view.isHidden = false
        }
        
        self.temperatureCircle?.toolTip = "\(localizedString("CPU temperature")): \(temperature(value))"
        self.temperatureCircle?.setValue(value/100)
        self.temperatureCircle?.setText(temperature(value))
        self.temperatureCircle?.display()
    }
    
    public func frequencyCallback(_ value: CPU_Frequency?) {
        guard let value else { return }
        self.apply(value, to: self.frequencyCache, render: self.renderFrequency)
    }
    
    private func renderFrequency(_ value: CPU_Frequency) {
        if self.coresFreqField == nil {
            self.insertArrangedSubview(self.initFrequency(), at: 4)
            self.recalculateHeight()
        }
        if let view = self.frequencyCircle, (view as NSView).isHidden {
            view.isHidden = false
        }
        
        if let v = value.value {
            if v > self.maxFreq {
                self.maxFreq = v
            }
            
            self.coresFreqField?.stringValue = "\(Int(v)) MHz"
            if let circle = self.frequencyCircle {
                circle.setValue((100*v)/self.maxFreq)
                circle.setText("\((v/1000).rounded(toPlaces: 2))")
                circle.toolTip = "\(localizedString("CPU frequency")): \(Int(v)) MHz - \(((100*v)/self.maxFreq).rounded(toPlaces: 2))%"
                circle.display()
            }
        }
        
        if let v = value.eCore {
            self.eCoresFreqField?.stringValue = "\(Int(v)) MHz"
        }
        if let v = value.pCore {
            self.pCoresFreqField?.stringValue = "\(Int(v)) MHz"
        }
        if let v = value.sCore {
            self.sCoresFreqField?.stringValue = "\(Int(v)) MHz"
        }
    }
    
    public func processCallback(_ list: [TopProcess]?) {
        guard let list else { return }
        self.apply(list, to: self.processCache, render: self.renderProcesses)
    }
    
    private func renderProcesses(_ list: [TopProcess]) {
        if list.count != self.processes?.count { self.processes?.clear() }
        
        for i in 0..<list.count {
            let process = list[i]
            self.processes?.set(i, process, ["\(process.usage)%"])
        }
    }
    
    public func numberOfProcessesUpdated() {
        if self.processes?.count == self.numberOfProcesses { return }
        
        DispatchQueue.main.async(execute: {
            guard self.contentLoaded else { return }
            self.processesView?.removeFromSuperview()
            self.processesView = nil
            self.processes = nil
            self.addArrangedSubview(self.initProcesses())
            self.processCache.initialized = false
            self.recalculateHeight()
        })
    }
    
    public func intelCallback(_ value: IntelCPUDetails) {
        self.apply(value, to: self.intelCache, render: self.renderIntel)
        DispatchQueue.main.async {
            let date = Date()
            let sampled = value.frequencyDate != nil && value.frequencyDate != self.lastFrequencyDate
            for (index, reading) in value.values.enumerated() {
                if (index == 0 || index == 6) && !sampled { continue }
                self.intelHistory.append(localizedString(IntelCPUDetails.metrics[index].0), reading, at: date)
            }
            if sampled {
                self.lastFrequencyDate = value.frequencyDate
                for (core, threads) in value.coreThreadMHz.enumerated() {
                    for (thread, mhz) in threads.enumerated() {
                        self.intelHistory.append(IntelCPUDetails.coreThreadName(core, thread), mhz, at: date)
                    }
                }
            }
            self.intelChart?.historyUpdated()
        }
    }

    private func renderIntel(_ value: IntelCPUDetails) {
        let unavailable = localizedString("Unavailable")
        let values = value.formattedValues
        for (index, metric) in IntelCPUDetails.metrics.enumerated() {
            self.intelFields[metric.0]?.stringValue = values[index] ?? unavailable
        }
        let reasons = value.formattedReasons
        self.intelFields["Reported limit reasons"]?.stringValue = reasons ?? unavailable
        self.intelFields["Reported limit reasons"]?.toolTip = reasons
        self.intelFields["CPU package power"]?.toolTip = value.packageWatts.map { _ in
            value.powerFromSMC ? "SMC PCPT" : "powermetrics"
        }
        if let temp = value.temperature {
            self.renderTemperature(temp)
        } else {
            self.temperatureCircle?.isHidden = true
        }
        self.frequencyCircle?.isHidden = value.averageMHz == nil
        if let mhz = value.averageMHz {
            self.frequencyCircle?.setText(String(format: "%.2f GHz", mhz / 1000))
            self.frequencyCircle?.toolTip = values[0]
        }

        let coreText = (0..<IntelCPUDetails.physicalCount).map { index in
            "\(localizedString("Core")) \(index)   \(value.formattedCore(index) ?? unavailable)"
        }.joined(separator: "\n")
        self.intelCoreText?.stringValue = coreText.isEmpty ? unavailable : coreText
        if let text = self.intelCoreText, let document = text.superview {
            let width = max(1, document.bounds.width - 10)
            let size = text.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 1000)) ?? .zero
            document.setFrameSize(NSSize(width: document.frame.width, height: max(72, size.height + 6)))
        }
    }

    public func averageCallback(_ value: CPU_AverageLoad?) {
        guard let value else { return }
        self.apply(value, to: self.averageCache, render: self.renderAverage)
    }
    
    private func renderAverage(_ value: CPU_AverageLoad) {
        self.average1Field?.stringValue = "\(value.load1)"
        self.average5Field?.stringValue = "\(value.load5)"
        self.average15Field?.stringValue = "\(value.load15)"
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
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("System color"), component: self.colorSelectView(
                action: #selector(self.toggleSystemColor),
                items: SColor.allColors,
                selected: self.systemColorState.key
            )),
            PreferencesRow(localizedString("User color"), component: self.colorSelectView(
                action: #selector(self.toggleUserColor),
                items: SColor.allColors,
                selected: self.userColorState.key
            )),
            PreferencesRow(localizedString("Idle color"), component: self.colorSelectView(
                action: #selector(self.toggleIdleColor),
                items: SColor.allColors,
                selected: self.idleColorState.key
            ))
        ]))
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Efficiency cores color"), component: self.colorSelectView(
                action: #selector(self.toggleECoresColor),
                items: SColor.allColors,
                selected: self.eCoresColorState.key
            )),
            PreferencesRow(localizedString("Performance cores color"), component: self.colorSelectView(
                action: #selector(self.togglePCoresColor),
                items: SColor.allColors,
                selected: self.pCoresColorState.key
            )),
            PreferencesRow(localizedString("Super cores color"), component: self.colorSelectView(
                action: #selector(self.toggleSCoresColor),
                items: SColor.allColors,
                selected: self.sCoresColorState.key
            ))
        ]))
        
        self.sliderView = self.sliderView(
            action: #selector(self.toggleLineChartFixedScale),
            value: Int(self.lineChartFixedScale * 100),
            initialValue: "\(Int(self.lineChartFixedScale * 100)) %"
        )
        self.chartPrefSection = PreferencesSection([
            PreferencesRow(localizedString("Chart color"), component: self.colorSelectView(
                action: #selector(self.toggleChartColor),
                items: SColor.allColors,
                selected: self.chartColorState.key
            )),
            PreferencesRow(localizedString("Chart history"), component: self.selectView(
                action: #selector(self.toggleLineChartHistory),
                items: LineChartHistory,
                selected: "\(self.lineChartHistory)"
            )),
            PreferencesRow(localizedString("Main chart scaling"), component: self.selectView(
                action: #selector(self.toggleLineChartScale),
                items: Scale.allCases,
                selected: self.lineChartScale.key
            )),
            PreferencesRow(localizedString("Scale value"), component: self.sliderView!)
        ])
        view.addArrangedSubview(self.chartPrefSection!)
        self.chartPrefSection?.setRowVisibility(3, newState: self.lineChartScale == .fixed)
        
        return view
    }
    
    @objc private func toggleSystemColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.systemColorState = SColor.fromString(key, defaultValue: self.systemColorState)
        Store.shared.set(key: "\(self.title)_systemColor", value: self.systemColorState.key)
        self.systemColorView?.layer?.backgroundColor = (self.systemColorState.additional as? NSColor)?.cgColor
    }
    @objc private func toggleUserColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.userColorState = SColor.fromString(key, defaultValue: self.userColorState)
        Store.shared.set(key: "\(self.title)_userColor", value: self.userColorState.key)
        self.userColorView?.layer?.backgroundColor = (self.userColorState.additional as? NSColor)?.cgColor
    }
    @objc private func toggleIdleColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.idleColorState = SColor.fromString(key, defaultValue: self.idleColorState)
        Store.shared.set(key: "\(self.title)_idleColor", value: self.idleColorState.key)
        self.idleColorView?.layer?.backgroundColor = (self.idleColorState.additional as? NSColor)?.cgColor
    }
    @objc private func toggleChartColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.chartColorState = SColor.fromString(key, defaultValue: self.chartColorState)
        Store.shared.set(key: "\(self.title)_chartColor", value: self.chartColorState.key)
        if let color = self.chartColorState.additional as? NSColor {
            self.lineChart?.setColor(color)
        }
    }
    @objc private func toggleECoresColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.eCoresColorState = SColor.fromString(key, defaultValue: self.eCoresColorState)
        Store.shared.set(key: "\(self.title)_eCoresColor", value: self.eCoresColorState.key)
        if let color = (self.eCoresColorState.additional as? NSColor) {
            self.eCoresColorView?.layer?.backgroundColor = color.cgColor
            self.eCoresFreqColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func togglePCoresColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.pCoresColorState = SColor.fromString(key, defaultValue: self.pCoresColorState)
        Store.shared.set(key: "\(self.title)_pCoresColor", value: self.pCoresColorState.key)
        if let color = (self.pCoresColorState.additional as? NSColor) {
            self.pCoresColorView?.layer?.backgroundColor = color.cgColor
            self.pCoresFreqColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleSCoresColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.sCoresColorState = SColor.fromString(key, defaultValue: self.sCoresColorState)
        Store.shared.set(key: "\(self.title)_sCoresColor", value: self.sCoresColorState.key)
        if let color = (self.sCoresColorState.additional as? NSColor) {
            self.sCoresColorView?.layer?.backgroundColor = color.cgColor
            self.sCoresFreqColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleLineChartHistory(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.lineChartHistory = value
        self.chartHistory.resize(value)
        Store.shared.set(key: "\(self.title)_lineChartHistory", value: value)
        self.lineChart?.reinit(self.lineChartHistory)
    }
    @objc private func toggleLineChartScale(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let value = Scale.allCases.first(where: { $0.key == key }) else { return }
        self.chartPrefSection?.setRowVisibility(3, newState: value == .fixed)
        self.lineChartScale = value
        self.lineChart?.setScale(self.lineChartScale, fixedScale: self.lineChartFixedScale)
        Store.shared.set(key: "\(self.title)_lineChartScale", value: key)
        self.display()
    }
    @objc private func toggleLineChartFixedScale(_ sender: NSSlider) {
        let value = Int(sender.doubleValue)
        
        if let field = self.sliderView?.subviews.first(where: { $0 is NSTextField }), let view = field as? NSTextField {
            view.stringValue = "\(value) %"
        }
        
        self.lineChartFixedScale = sender.doubleValue / 100
        self.lineChart?.setScale(self.lineChartScale, fixedScale: self.lineChartFixedScale)
        Store.shared.set(key: "\(self.title)_lineChartFixedScale", value: value)
    }
}
