//
//  BatteryManager.swift
//  BrewCap
//
//  Copyright (c) 2026 NorthStars Industries. All rights reserved.
//

import Foundation
import AppKit
import IOKit.ps
import Combine
import UserNotifications

class BatteryManager: ObservableObject {
    // MARK: - Core Battery Data (Features 1–12)

    @Published var batteryLevel: Int = 0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    @Published var temperature: Double = 0.0

    @Published var healthPercent: Int = 100       // Feature 1
    @Published var cycleCount: Int = 0            // Feature 2
    @Published var designCapacity: Int = 0        // Feature 3
    @Published var maxCapacity: Int = 0           // Feature 4
    @Published var adapterWatts: Int = 0          // Feature 5
    @Published var adapterName: String = "None"   // Feature 6
    @Published var timeRemaining: String = "—"    // Feature 7
    @Published var amperage: Int = 0              // Feature 8
    @Published var voltage: Double = 0.0          // Feature 9
    @Published var batteryCondition: String = "Unknown" // Feature 10
    @Published var serialNumber: String = "—"     // Feature 11
    @Published var manufactureDate: String = "—"  // Feature 12

    // MARK: - Sailing Mode

    @Published var chargeLimit: Double {
        didSet {
            UserDefaults.standard.set(chargeLimit, forKey: "chargeLimit")
            if sailingModeEnabled && isPluggedIn { applyChargingControl() }
        }
    }

    @Published var sailingModeEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(sailingModeEnabled, forKey: "sailingModeEnabled")
            if sailingModeEnabled { handleSailingModeOn() } else { handleSailingModeOff() }
        }
    }

    @Published var chargingInhibited: Bool = false
    @Published var setupNeeded: Bool = false

    // MARK: - Alerts (Features 13–18)

    @Published var tempAlertThreshold: Double {
        didSet { UserDefaults.standard.set(tempAlertThreshold, forKey: "tempAlertThreshold") }
    }
    private var hasNotifiedTempAlert = false

    @Published var lowBatteryThreshold: Int {
        didSet { UserDefaults.standard.set(lowBatteryThreshold, forKey: "lowBatteryThreshold") }
    }
    private var hasNotifiedLowBattery = false

    @Published var fullChargeNotification: Bool {
        didSet { UserDefaults.standard.set(fullChargeNotification, forKey: "fullChargeNotification") }
    }
    private var hasNotifiedFullCharge = false
    private var hasNotifiedCriticalTemp = false

    @Published var soundEffectsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEffectsEnabled, forKey: "soundEffectsEnabled") }
    }

    @Published var doNotDisturb: Bool {
        didSet { UserDefaults.standard.set(doNotDisturb, forKey: "doNotDisturb") }
    }

    // MARK: - Session Tracking (19–20)

    @Published var sessionStartTime: Date?
    @Published var sessionStartLevel: Int = 0
    @Published var sessionDuration: String = "—"
    @Published var sessionDelta: Int = 0
    @Published var chargeHistory: [ChargeSession] = []
    private var sessionTimer: Timer?

    // MARK: - Feature 29: Configurable Monitoring

    @Published var monitoringInterval: Double {
        didSet {
            UserDefaults.standard.set(monitoringInterval, forKey: "monitoringInterval")
            startMonitoring()
        }
    }

    // MARK: - Feature 23: Menu Bar Percentage

    @Published var showPercentageInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showPercentageInMenuBar, forKey: "showPercentageInMenuBar") }
    }

    // MARK: - Feature 31: Power Draw (watts)

    @Published var powerDrawWatts: Double = 0.0

    // MARK: - Feature 32: Estimated Time to Full

    @Published var estimatedTimeToFull: String = "—"

    // MARK: - Feature 33: Capacity Fade Tracking

    @Published var capacitySnapshots: [CapacitySnapshot] = []

    // MARK: - Feature 34: Usage Intensity

    @Published var usageIntensity: String = "—"

    // MARK: - Feature 35: Average Drain per Hour

    @Published var averageDrainPerHour: Int = 0
    private var drainSamples: [(date: Date, level: Int)] = []

    // MARK: - Feature 36: Battery Age

    @Published var batteryAgeYears: Double = 0.0

    // MARK: - Feature 37: Travel Mode

    @Published var travelModeEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(travelModeEnabled, forKey: "travelModeEnabled")
            if travelModeEnabled {
                savedChargeLimit = chargeLimit
                chargeLimit = 100
                travelModeExpiry = Date().addingTimeInterval(travelModeDuration * 3600)
                logEvent("Travel Mode enabled — limit raised to 100% for \(Int(travelModeDuration))h")
            } else {
                if let saved = savedChargeLimit { chargeLimit = saved }
                travelModeExpiry = nil
                logEvent("Travel Mode disabled — limit restored to \(Int(chargeLimit))%")
            }
        }
    }
    @Published var travelModeDuration: Double = 8.0 // hours
    @Published var travelModeExpiry: Date?
    private var savedChargeLimit: Double?

    // MARK: - Feature 39: Charge Speed

    @Published var chargeSpeed: String = "—"

    // MARK: - Feature 40: Auto-pause below 20%

    @Published var autoPauseLowBattery: Bool {
        didSet { UserDefaults.standard.set(autoPauseLowBattery, forKey: "autoPauseLowBattery") }
    }

    // MARK: - Feature 41: Charge Complete Chime

    @Published var chargeChimeEnabled: Bool {
        didSet { UserDefaults.standard.set(chargeChimeEnabled, forKey: "chargeChimeEnabled") }
    }
    private var hasPlayedChargeChime = false

    // MARK: - Feature 42: Estimated Replacement Date

    @Published var estimatedReplacementDate: String = "—"

    // MARK: - Feature 43: Menu Bar Display Mode

    @Published var menuBarDisplayMode: Int {
        didSet { UserDefaults.standard.set(menuBarDisplayMode, forKey: "menuBarDisplayMode") }
    }

    // MARK: - Feature 48: Notification Badge

    @Published var hasPendingAlert: Bool = false

    // MARK: - Feature 52: Battery Event Log

    @Published var eventLog: [BatteryEvent] = []

    // MARK: - Feature 54: Daily Battery Snapshots

    private var snapshotTimer: Timer?

    // MARK: - Feature 57: Reduce Motion

    @Published var reduceMotion: Bool {
        didSet { UserDefaults.standard.set(reduceMotion, forKey: "reduceMotion") }
    }

    // MARK: - Private

    private var timer: Timer?
    private var hasNotifiedForCurrentCharge = false

    // MARK: - Init

    init() {
        let saved = UserDefaults.standard.double(forKey: "chargeLimit")
        self.chargeLimit = saved > 0 ? saved : 80.0

        let savedTemp = UserDefaults.standard.double(forKey: "tempAlertThreshold")
        self.tempAlertThreshold = savedTemp > 0 ? savedTemp : 40.0

        let savedLow = UserDefaults.standard.integer(forKey: "lowBatteryThreshold")
        self.lowBatteryThreshold = savedLow > 0 ? savedLow : 20

        self.fullChargeNotification = UserDefaults.standard.bool(forKey: "fullChargeNotification")
        self.soundEffectsEnabled = UserDefaults.standard.object(forKey: "soundEffectsEnabled") as? Bool ?? true
        self.doNotDisturb = UserDefaults.standard.bool(forKey: "doNotDisturb")

        let savedInterval = UserDefaults.standard.double(forKey: "monitoringInterval")
        self.monitoringInterval = savedInterval > 0 ? savedInterval : 10.0

        self.showPercentageInMenuBar = UserDefaults.standard.object(forKey: "showPercentageInMenuBar") as? Bool ?? false

        // Feature 40
        self.autoPauseLowBattery = UserDefaults.standard.object(forKey: "autoPauseLowBattery") as? Bool ?? true

        // Feature 41
        self.chargeChimeEnabled = UserDefaults.standard.object(forKey: "chargeChimeEnabled") as? Bool ?? false

        // Feature 43
        self.menuBarDisplayMode = UserDefaults.standard.integer(forKey: "menuBarDisplayMode") // 0=%, 1=time, 2=watts

        // Feature 57
        self.reduceMotion = UserDefaults.standard.bool(forKey: "reduceMotion")

        // Load charge history
        if let data = UserDefaults.standard.data(forKey: "chargeHistory"),
           let history = try? JSONDecoder().decode([ChargeSession].self, from: data) {
            self.chargeHistory = history
        }

        // Feature 33: Load capacity snapshots
        if let data = UserDefaults.standard.data(forKey: "capacitySnapshots"),
           let snaps = try? JSONDecoder().decode([CapacitySnapshot].self, from: data) {
            self.capacitySnapshots = snaps
        }

        // Feature 52: Load event log
        if let data = UserDefaults.standard.data(forKey: "eventLog"),
           let log = try? JSONDecoder().decode([BatteryEvent].self, from: data) {
            self.eventLog = Array(log.prefix(100))
        }

        // Feature 37: Check travel mode expiry
        self.travelModeEnabled = UserDefaults.standard.bool(forKey: "travelModeEnabled")
        if travelModeEnabled {
            if let expiry = UserDefaults.standard.object(forKey: "travelModeExpiry") as? Date {
                if Date() > expiry {
                    self.travelModeEnabled = false
                } else {
                    self.travelModeExpiry = expiry
                }
            }
        }

        let savedSailing = UserDefaults.standard.bool(forKey: "sailingModeEnabled")

        refresh()
        startMonitoring()
        requestNotificationPermission()
        registerSleepWakeNotifications()
        startSnapshotTimer() // Feature 54

        self.sailingModeEnabled = savedSailing

        if sailingModeEnabled {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let inhibited = SMCClient.isChargingInhibited()
                DispatchQueue.main.async { self?.chargingInhibited = inhibited }
            }
        }

        logEvent("BrewCap launched")
    }

    deinit {
        timer?.invalidate()
        sessionTimer?.invalidate()
        snapshotTimer?.invalidate()
    }

    // MARK: - Monitoring

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let info = Self.readFullBatteryInfo()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let wasPluggedIn = self.isPluggedIn

            self.batteryLevel = info.level
            self.isCharging = info.isCharging
            self.isPluggedIn = info.isPluggedIn
            self.temperature = info.temperature
            self.cycleCount = info.cycleCount
            self.designCapacity = info.designCapacity
            self.maxCapacity = info.maxCapacity
            self.healthPercent = info.designCapacity > 0 ? Int(Double(info.maxCapacity) / Double(info.designCapacity) * 100) : 100
            self.adapterWatts = info.adapterWatts
            self.adapterName = info.adapterName
            self.amperage = info.amperage
            self.voltage = info.voltage
            self.batteryCondition = info.condition
            self.serialNumber = info.serialNumber
            self.manufactureDate = info.manufactureDate
            self.timeRemaining = info.timeRemaining

            // Feature 31: Power draw
            self.powerDrawWatts = abs(Double(info.amperage)) * info.voltage / 1000.0

            // Feature 32: Estimated time to full
            self.updateTimeToFull()

            // Feature 34: Usage intensity
            self.updateUsageIntensity()

            // Feature 35: Drain rate tracking
            self.updateDrainRate()

            // Feature 36: Battery age
            if info.cycleCount > 0 {
                self.batteryAgeYears = Double(info.cycleCount) / 300.0 // ~300 cycles/year avg
            }

            // Feature 39: Charge speed
            self.updateChargeSpeed()

            // Feature 42: Replacement date
            self.updateReplacementDate()

            // Session tracking
            if self.isPluggedIn && !wasPluggedIn {
                self.startSession()
                self.logEvent("Charger connected — \(self.batteryLevel)%")
            } else if !self.isPluggedIn && wasPluggedIn {
                self.endSession()
                self.logEvent("Charger disconnected — \(self.batteryLevel)%")
            }
            self.updateSessionDuration()

            // Feature 37: Travel mode auto-revert
            if self.travelModeEnabled, let expiry = self.travelModeExpiry, Date() > expiry {
                self.travelModeEnabled = false
            }

            // Feature 40: Auto-pause Sailing below 20%
            if self.autoPauseLowBattery && self.sailingModeEnabled && self.batteryLevel < 20 && !self.isPluggedIn {
                self.sailingModeEnabled = false
                self.logEvent("Sailing Mode auto-disabled — battery below 20%")
                self.sendNotification(
                    title: "⚠️ BrewCap — Sailing Mode Paused",
                    body: "Battery below 20%. Sailing Mode disabled to preserve charge."
                )
            }

            // Feature 41: Charge chime
            if self.chargeChimeEnabled && self.isPluggedIn {
                let target = Int(self.chargeLimit)
                if self.batteryLevel >= target && !self.hasPlayedChargeChime {
                    self.hasPlayedChargeChime = true
                    NSSound(named: "Glass")?.play()
                }
            }
            if self.batteryLevel < Int(self.chargeLimit) - 5 { self.hasPlayedChargeChime = false }

            // Sailing mode
            if self.sailingModeEnabled {
                self.handleSailingCheck()
            } else {
                self.checkOneShotNotification()
            }

            // Alert checks
            self.checkTemperatureAlert()
            self.checkLowBatteryWarning()
            self.checkFullChargeNotification()
            self.checkCriticalTemperature()

            // Feature 48: Badge
            self.hasPendingAlert = self.temperature >= self.tempAlertThreshold ||
                                   (self.batteryLevel <= self.lowBatteryThreshold && !self.isPluggedIn)
        }
    }

    // MARK: - Feature 31-32: Computed Analytics

    private func updateTimeToFull() {
        guard isCharging, amperage > 0, maxCapacity > 0 else {
            estimatedTimeToFull = isPluggedIn ? timeRemaining : "—"
            return
        }
        let currentMah = Double(batteryLevel) / 100.0 * Double(maxCapacity)
        let remaining = Double(maxCapacity) - currentMah
        if remaining > 0 && amperage > 0 {
            let hours = remaining / Double(amperage)
            let hrs = Int(hours)
            let mins = Int((hours - Double(hrs)) * 60)
            estimatedTimeToFull = hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
        } else {
            estimatedTimeToFull = "—"
        }
    }

    // MARK: - Feature 34: Usage Intensity

    private func updateUsageIntensity() {
        let draw = powerDrawWatts
        if isPluggedIn {
            usageIntensity = "Charging"
        } else if draw > 15 {
            usageIntensity = "Heavy"
        } else if draw > 7 {
            usageIntensity = "Moderate"
        } else if draw > 0.5 {
            usageIntensity = "Light"
        } else {
            usageIntensity = "Idle"
        }
    }

    // MARK: - Feature 35: Average Drain Rate

    private func updateDrainRate() {
        guard !isPluggedIn else {
            drainSamples.removeAll()
            return
        }
        drainSamples.append((date: Date(), level: batteryLevel))
        // Keep last 30 minutes of samples
        let cutoff = Date().addingTimeInterval(-1800)
        drainSamples.removeAll { $0.date < cutoff }

        if drainSamples.count >= 2 {
            let first = drainSamples.first!
            let last = drainSamples.last!
            let elapsed = last.date.timeIntervalSince(first.date) / 3600.0
            if elapsed > 0.01 {
                averageDrainPerHour = Int(Double(first.level - last.level) / elapsed)
            }
        }
    }

    // MARK: - Feature 38: Charge Limit Presets

    func setChargePreset(_ preset: Int) {
        chargeLimit = Double(preset)
        logEvent("Charge limit preset set to \(preset)%")
    }

    // MARK: - Feature 39: Charge Speed

    private func updateChargeSpeed() {
        guard isPluggedIn else { chargeSpeed = "—"; return }
        if adapterWatts >= 60 {
            chargeSpeed = "Fast"
        } else if adapterWatts >= 30 {
            chargeSpeed = "Normal"
        } else if adapterWatts > 0 {
            chargeSpeed = "Slow"
        } else {
            chargeSpeed = "—"
        }
    }

    // MARK: - Feature 42: Estimated Replacement

    private func updateReplacementDate() {
        guard capacitySnapshots.count >= 2, designCapacity > 0 else {
            estimatedReplacementDate = "—"
            return
        }
        let first = capacitySnapshots.first!
        let last = capacitySnapshots.last!
        let daysBetween = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        guard daysBetween > 7, first.maxCapacity > last.maxCapacity else {
            estimatedReplacementDate = "—"
            return
        }
        let fadePerDay = Double(first.maxCapacity - last.maxCapacity) / Double(daysBetween)
        let threshold = Double(designCapacity) * 0.80
        let remaining = Double(last.maxCapacity) - threshold
        if remaining > 0 && fadePerDay > 0 {
            let daysLeft = Int(remaining / fadePerDay)
            let targetDate = Calendar.current.date(byAdding: .day, value: daysLeft, to: Date())!
            let f = DateFormatter()
            f.dateFormat = "MMM yyyy"
            estimatedReplacementDate = "~\(f.string(from: targetDate))"
        } else {
            estimatedReplacementDate = "—"
        }
    }

    // MARK: - Session Tracking (19)

    private func startSession() {
        sessionStartTime = Date()
        sessionStartLevel = batteryLevel
        sessionDelta = 0
        sessionDuration = "0m"
    }

    private func endSession() {
        guard let start = sessionStartTime else { return }
        let duration = Date().timeIntervalSince(start)
        let session = ChargeSession(
            startTime: start,
            endTime: Date(),
            startLevel: sessionStartLevel,
            endLevel: batteryLevel,
            durationMinutes: Int(duration / 60),
            adapterWatts: adapterWatts
        )
        chargeHistory.insert(session, at: 0)
        if chargeHistory.count > 20 { chargeHistory = Array(chargeHistory.prefix(20)) }
        saveChargeHistory()
        sessionStartTime = nil
    }

    private func updateSessionDuration() {
        guard let start = sessionStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let hrs = elapsed / 3600
        let mins = (elapsed % 3600) / 60
        sessionDuration = hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
        sessionDelta = batteryLevel - sessionStartLevel
    }

    private func saveChargeHistory() {
        if let data = try? JSONEncoder().encode(chargeHistory) {
            UserDefaults.standard.set(data, forKey: "chargeHistory")
        }
    }

    // MARK: - Alerts (13–16)

    private func checkTemperatureAlert() {
        if temperature >= tempAlertThreshold && !hasNotifiedTempAlert {
            hasNotifiedTempAlert = true
            logEvent("Temperature alert: \(String(format: "%.1f°C", temperature))")
            sendNotification(
                title: "🌡 BrewCap — High Temperature",
                body: "Battery temperature is \(String(format: "%.1f°C", temperature)). Threshold: \(Int(tempAlertThreshold))°C."
            )
        }
        if temperature < tempAlertThreshold - 2 { hasNotifiedTempAlert = false }
    }

    private func checkLowBatteryWarning() {
        if batteryLevel <= lowBatteryThreshold && !isPluggedIn && !hasNotifiedLowBattery {
            hasNotifiedLowBattery = true
            logEvent("Low battery warning: \(batteryLevel)%")
            sendNotification(
                title: "🪫 BrewCap — Low Battery",
                body: "Battery at \(batteryLevel)%. Consider plugging in your charger."
            )
        }
        if batteryLevel > lowBatteryThreshold + 5 || isPluggedIn { hasNotifiedLowBattery = false }
    }

    private func checkFullChargeNotification() {
        guard fullChargeNotification else { return }
        if batteryLevel >= 100 && isPluggedIn && !hasNotifiedFullCharge {
            hasNotifiedFullCharge = true
            logEvent("Battery fully charged")
            sendNotification(
                title: "🔋 BrewCap — Fully Charged",
                body: "Battery is at 100%. You can unplug your charger."
            )
        }
        if batteryLevel < 95 { hasNotifiedFullCharge = false }
    }

    private func checkCriticalTemperature() {
        if temperature >= 45 && !hasNotifiedCriticalTemp {
            hasNotifiedCriticalTemp = true
            logEvent("CRITICAL temperature: \(String(format: "%.1f°C", temperature))")
            sendNotification(
                title: "🔥 BrewCap — CRITICAL TEMPERATURE",
                body: "Battery at \(String(format: "%.1f°C", temperature))! This may damage your battery. Close intensive apps."
            )
        }
        if temperature < 42 { hasNotifiedCriticalTemp = false }
    }

    // MARK: - Feature 28: Sleep/Wake

    private func registerSleepWakeNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refresh()
            if self?.sailingModeEnabled == true {
                self?.applyChargingControl()
            }
        }
    }

    // MARK: - Feature 30: Reset All Settings

    func resetAllSettings() {
        let keys = ["chargeLimit", "sailingModeEnabled", "tempAlertThreshold",
                     "lowBatteryThreshold", "fullChargeNotification", "soundEffectsEnabled",
                     "doNotDisturb", "monitoringInterval", "showPercentageInMenuBar", "chargeHistory",
                     "autoPauseLowBattery", "chargeChimeEnabled", "menuBarDisplayMode",
                     "reduceMotion", "travelModeEnabled", "capacitySnapshots", "eventLog"]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }

        chargeLimit = 80.0
        sailingModeEnabled = false
        tempAlertThreshold = 40.0
        lowBatteryThreshold = 20
        fullChargeNotification = false
        soundEffectsEnabled = true
        doNotDisturb = false
        monitoringInterval = 10.0
        showPercentageInMenuBar = false
        chargeHistory = []
        autoPauseLowBattery = true
        chargeChimeEnabled = false
        menuBarDisplayMode = 0
        reduceMotion = false
        travelModeEnabled = false
        capacitySnapshots = []
        eventLog = []
        logEvent("All settings reset")
    }

    // MARK: - Sailing Mode

    private func handleSailingModeOn() {
        if !SMCClient.isSetupComplete {
            setupNeeded = true
            return
        }
        applyChargingControl()
    }

    private func handleSailingModeOff() {
        chargingInhibited = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = SMCClient.enableCharging()
            DispatchQueue.main.async { self?.chargingInhibited = false }
        }
    }

    func completeSetup() {
        setupNeeded = false
        applyChargingControl()
    }

    func runSetup(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let success = SMCClient.performOneTimeSetup()
            DispatchQueue.main.async {
                if success {
                    self.setupNeeded = false
                    self.applyChargingControl()
                }
                completion(success)
            }
        }
    }

    private func handleSailingCheck() {
        let limit = Int(chargeLimit)
        let aboveLimit = batteryLevel >= limit && isPluggedIn

        if aboveLimit && !chargingInhibited {
            applyChargingControl()
        } else if !aboveLimit && chargingInhibited {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let ok = SMCClient.enableCharging()
                DispatchQueue.main.async { if ok { self?.chargingInhibited = false } }
            }
        }
    }

    private func applyChargingControl() {
        guard SMCClient.isSetupComplete else { return }
        let limit = Int(chargeLimit)
        let aboveLimit = batteryLevel >= limit && isPluggedIn

        if aboveLimit {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let ok = SMCClient.disableCharging()
                DispatchQueue.main.async {
                    self?.chargingInhibited = ok
                    if ok {
                        self?.logEvent("Charging paused at \(self?.batteryLevel ?? 0)%")
                        self?.sendNotification(
                            title: "☕ BrewCap — Charging Paused",
                            body: "Battery at \(self?.batteryLevel ?? 0)%. Limit is \(limit)%."
                        )
                    }
                }
            }
        }
    }

    private func checkOneShotNotification() {
        let limit = Int(chargeLimit)
        if batteryLevel >= limit && isPluggedIn && !hasNotifiedForCurrentCharge {
            hasNotifiedForCurrentCharge = true
            sendNotification(
                title: "☕ BrewCap — Charge Limit Reached",
                body: "Battery at \(batteryLevel)%. Limit is \(limit)%. Please unplug your charger."
            )
        }
        if batteryLevel < limit || !isPluggedIn { hasNotifiedForCurrentCharge = false }
    }

    // MARK: - Feature 52: Event Log

    func logEvent(_ message: String) {
        let event = BatteryEvent(date: Date(), message: message)
        eventLog.insert(event, at: 0)
        if eventLog.count > 100 { eventLog = Array(eventLog.prefix(100)) }
        saveEventLog()
    }

    private func saveEventLog() {
        if let data = try? JSONEncoder().encode(eventLog) {
            UserDefaults.standard.set(data, forKey: "eventLog")
        }
    }

    // MARK: - Feature 33/54: Capacity Snapshots

    private func startSnapshotTimer() {
        // Take a snapshot every 12 hours
        takeCapacitySnapshotIfNeeded()
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 43200, repeats: true) { [weak self] _ in
            self?.takeCapacitySnapshotIfNeeded()
        }
    }

    private func takeCapacitySnapshotIfNeeded() {
        guard maxCapacity > 0, designCapacity > 0 else { return }
        // Only one snapshot per day
        if let last = capacitySnapshots.last {
            if Calendar.current.isDateInToday(last.date) { return }
        }
        let snap = CapacitySnapshot(date: Date(), maxCapacity: maxCapacity, designCapacity: designCapacity, cycleCount: cycleCount)
        capacitySnapshots.append(snap)
        if capacitySnapshots.count > 365 { capacitySnapshots = Array(capacitySnapshots.suffix(365)) }
        if let data = try? JSONEncoder().encode(capacitySnapshots) {
            UserDefaults.standard.set(data, forKey: "capacitySnapshots")
        }
    }

    // MARK: - Feature 49: CSV Export

    func exportChargeHistoryCSV() -> String {
        var csv = "Date,Start Level,End Level,Delta,Duration (min),Adapter Watts\n"
        for s in chargeHistory {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            csv += "\(f.string(from: s.startTime)),\(s.startLevel),\(s.endLevel),\(s.delta),\(s.durationMinutes),\(s.adapterWatts)\n"
        }
        return csv
    }

    // MARK: - Feature 50: Copy Stats to Clipboard

    func copyStatsToClipboard() {
        let stats = """
        BrewCap Battery Stats
        Level: \(batteryLevel)%
        Health: \(healthPercent)%
        Temperature: \(String(format: "%.1f°C", temperature))
        Cycles: \(cycleCount)
        Power: \(String(format: "%.1f W", powerDrawWatts))
        Condition: \(batteryCondition)
        Time: \(timeRemaining)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(stats, forType: .string)
        logEvent("Stats copied to clipboard")
    }

    // MARK: - Feature 53: Settings Export/Import

    func exportSettingsJSON() -> Data? {
        let settings: [String: Any] = [
            "chargeLimit": chargeLimit,
            "tempAlertThreshold": tempAlertThreshold,
            "lowBatteryThreshold": lowBatteryThreshold,
            "fullChargeNotification": fullChargeNotification,
            "soundEffectsEnabled": soundEffectsEnabled,
            "doNotDisturb": doNotDisturb,
            "monitoringInterval": monitoringInterval,
            "showPercentageInMenuBar": showPercentageInMenuBar,
            "autoPauseLowBattery": autoPauseLowBattery,
            "chargeChimeEnabled": chargeChimeEnabled,
            "menuBarDisplayMode": menuBarDisplayMode,
            "reduceMotion": reduceMotion
        ]
        return try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
    }

    func importSettingsJSON(_ data: Data) -> Bool {
        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if let v = settings["chargeLimit"] as? Double { chargeLimit = v }
        if let v = settings["tempAlertThreshold"] as? Double { tempAlertThreshold = v }
        if let v = settings["lowBatteryThreshold"] as? Int { lowBatteryThreshold = v }
        if let v = settings["fullChargeNotification"] as? Bool { fullChargeNotification = v }
        if let v = settings["soundEffectsEnabled"] as? Bool { soundEffectsEnabled = v }
        if let v = settings["doNotDisturb"] as? Bool { doNotDisturb = v }
        if let v = settings["monitoringInterval"] as? Double { monitoringInterval = v }
        if let v = settings["showPercentageInMenuBar"] as? Bool { showPercentageInMenuBar = v }
        if let v = settings["autoPauseLowBattery"] as? Bool { autoPauseLowBattery = v }
        if let v = settings["chargeChimeEnabled"] as? Bool { chargeChimeEnabled = v }
        if let v = settings["menuBarDisplayMode"] as? Int { menuBarDisplayMode = v }
        if let v = settings["reduceMotion"] as? Bool { reduceMotion = v }
        logEvent("Settings imported from JSON")
        return true
    }

    // MARK: - Notifications

    func sendNotification(title: String, body: String) {
        guard !doNotDisturb else { return }
        hasPendingAlert = true

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = soundEffectsEnabled ? .default : nil

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - IOKit Battery Reading

    struct BatteryInfo {
        var level = 0
        var isCharging = false
        var isPluggedIn = false
        var temperature = 0.0
        var cycleCount = 0
        var designCapacity = 0
        var maxCapacity = 0
        var adapterWatts = 0
        var adapterName = "None"
        var amperage = 0
        var voltage = 0.0
        var condition = "Unknown"
        var serialNumber = "—"
        var manufactureDate = "—"
        var timeRemaining = "—"
    }

    private static func readFullBatteryInfo() -> BatteryInfo {
        var info = BatteryInfo()

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return info }
        defer { IOObjectRelease(service) }

        // Core
        if let cur = prop(service, "CurrentCapacity") as? Int,
           let max = prop(service, "MaxCapacity") as? Int, max > 0 {
            info.level = Int(Double(cur) / Double(max) * 100.0)
        }
        if let c = prop(service, "IsCharging") as? Bool { info.isCharging = c }
        if let e = prop(service, "ExternalConnected") as? Bool { info.isPluggedIn = e }
        if let t = prop(service, "Temperature") as? Int { info.temperature = Double(t) / 100.0 }

        if let cc = prop(service, "CycleCount") as? Int { info.cycleCount = cc }

        if let dc = prop(service, "DesignCapacity") as? Int { info.designCapacity = dc }
        if let mc = prop(service, "AppleRawMaxCapacity") as? Int {
            info.maxCapacity = mc
        } else if let mc = prop(service, "MaxCapacity") as? Int {
            info.maxCapacity = mc
        }

        // Amperage: unsigned to signed
        if let a = prop(service, "Amperage") as? Int {
            if a > Int(Int16.max) {
                info.amperage = Int(Int16(bitPattern: UInt16(a & 0xFFFF)))
            } else {
                info.amperage = a
            }
        }
        if info.amperage == 0, let ia = prop(service, "InstantAmperage") as? Int {
            if ia > Int(Int16.max) {
                info.amperage = Int(Int16(bitPattern: UInt16(ia & 0xFFFF)))
            } else {
                info.amperage = ia
            }
        }

        if let v = prop(service, "Voltage") as? Int { info.voltage = Double(v) / 1000.0 }

        // Condition
        if let cond = prop(service, "BatteryInstalled") as? Bool {
            if cond {
                if let perm = prop(service, "PermanentFailureStatus") as? Int, perm != 0 {
                    info.condition = "Service Recommended"
                } else if info.maxCapacity > 0 && info.designCapacity > 0 {
                    let health = Double(info.maxCapacity) / Double(info.designCapacity) * 100
                    if health >= 80 { info.condition = "Normal" }
                    else if health >= 60 { info.condition = "Fair" }
                    else { info.condition = "Poor" }
                }
            }
        }

        if let sn = prop(service, "BatterySerialNumber") as? String { info.serialNumber = sn }
        else if let sn = prop(service, "Serial") as? String { info.serialNumber = sn }

        if let md = prop(service, "ManufactureDate") as? Int, md > 0 {
            if md <= 0xFFFF {
                let day = md & 0x1F
                let month = (md >> 5) & 0x0F
                let year = ((md >> 9) & 0x7F) + 1980
                info.manufactureDate = String(format: "%04d-%02d-%02d", year, month, day)
            } else {
                info.manufactureDate = "—"
            }
        }

        // Adapter
        if info.isPluggedIn {
            if let details = prop(service, "AdapterDetails") as? [String: Any] {
                if let watts = details["Watts"] as? Int { info.adapterWatts = watts }
                else if let watts = details["AdapterVoltage"] as? Int,
                        let amps = details["AdapterCurrent"] as? Int {
                    info.adapterWatts = Int(Double(watts) * Double(amps) / 1_000_000.0)
                }
                if let name = details["Name"] as? String, !name.isEmpty { info.adapterName = name }
                else if let mfg = details["Manufacturer"] as? String, !mfg.isEmpty { info.adapterName = mfg }
                else if info.adapterWatts > 0 { info.adapterName = "\(info.adapterWatts)W Adapter" }
                else { info.adapterName = "USB-C" }
            } else {
                if let ptd = prop(service, "PowerTelemetryData") as? [String: Any],
                   let sysLoad = ptd["SystemLoad"] as? Int, sysLoad > 0 {
                    info.adapterWatts = sysLoad / 1000
                }
                info.adapterName = "USB-C"
            }
        }

        // Time remaining
        if let tr = prop(service, "TimeRemaining") as? Int {
            if tr == 65535 {
                info.timeRemaining = "Calculating…"
            } else if tr > 0 {
                let hrs = tr / 60
                let mins = tr % 60
                if info.isCharging {
                    info.timeRemaining = hrs > 0 ? "\(hrs)h \(mins)m to full" : "\(mins)m to full"
                } else {
                    info.timeRemaining = hrs > 0 ? "\(hrs)h \(mins)m remaining" : "\(mins)m remaining"
                }
            } else {
                info.timeRemaining = info.isPluggedIn ? "On AC Power" : "—"
            }
        }

        return info
    }

    private static func prop(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}

// MARK: - Models

struct ChargeSession: Codable, Identifiable {
    var id = UUID()
    let startTime: Date
    let endTime: Date
    let startLevel: Int
    let endLevel: Int
    let durationMinutes: Int
    let adapterWatts: Int

    var delta: Int { endLevel - startLevel }

    var formattedDuration: String {
        let hrs = durationMinutes / 60
        let mins = durationMinutes % 60
        return hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: startTime)
    }
}

struct CapacitySnapshot: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let maxCapacity: Int
    let designCapacity: Int
    let cycleCount: Int

    var healthPercent: Int {
        guard designCapacity > 0 else { return 100 }
        return Int(Double(maxCapacity) / Double(designCapacity) * 100)
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

struct BatteryEvent: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let message: String

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
