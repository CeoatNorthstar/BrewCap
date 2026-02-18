import Foundation
import IOKit.ps
import Combine
import UserNotifications

class BatteryManager: ObservableObject {
    @Published var batteryLevel: Int = 0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    @Published var temperature: Double = 0.0

    @Published var chargeLimit: Double {
        didSet {
            UserDefaults.standard.set(chargeLimit, forKey: "chargeLimit")
            if sailingModeEnabled && isPluggedIn {
                applyChargingControl()
            }
        }
    }

    @Published var sailingModeEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(sailingModeEnabled, forKey: "sailingModeEnabled")
            if sailingModeEnabled {
                handleSailingModeOn()
            } else {
                handleSailingModeOff()
            }
        }
    }

    @Published var chargingInhibited: Bool = false
    @Published var setupNeeded: Bool = false

    private var timer: Timer?
    private var hasNotifiedForCurrentCharge = false

    init() {
        let saved = UserDefaults.standard.double(forKey: "chargeLimit")
        self.chargeLimit = saved > 0 ? saved : 80.0

        // Read persisted value WITHOUT triggering didSet
        let savedSailing = UserDefaults.standard.bool(forKey: "sailingModeEnabled")

        refresh()
        startMonitoring()
        requestNotificationPermission()

        // Now set it (triggers didSet -> handleSailingModeOn if true)
        self.sailingModeEnabled = savedSailing

        // Re-check inhibit state on launch
        if sailingModeEnabled {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let inhibited = SMCClient.isChargingInhibited()
                DispatchQueue.main.async { self?.chargingInhibited = inhibited }
            }
        }
    }

    deinit { timer?.invalidate() }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let info = Self.readBatteryInfo()
        DispatchQueue.main.async {
            self.batteryLevel = info.level
            self.isCharging = info.isCharging
            self.isPluggedIn = info.isPluggedIn
            self.temperature = info.temperature

            if self.sailingModeEnabled {
                self.handleSailingCheck()
            } else {
                self.checkOneShotNotification()
            }
        }
    }

    // MARK: - Sailing Mode

    private func handleSailingModeOn() {
        // Check if one-time setup is done
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
            DispatchQueue.main.async {
                self?.chargingInhibited = false
            }
        }
    }

    /// Called from UI after setup completes
    func completeSetup() {
        setupNeeded = false
        applyChargingControl()
    }

    /// Run the one-time setup (password prompt)
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
            // Need to disable charging
            applyChargingControl()
        } else if !aboveLimit && chargingInhibited {
            // Below limit, re-enable charging
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let ok = SMCClient.enableCharging()
                DispatchQueue.main.async {
                    if ok { self?.chargingInhibited = false }
                }
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
                        self?.sendNotification(
                            title: "☕ BrewCap — Charging Paused",
                            body: "Battery at \(self?.batteryLevel ?? 0)%. Charging stopped at \(limit)% limit."
                        )
                    }
                }
            }
        }
    }

    // MARK: - One-Shot Notification (Sailing Mode OFF)

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

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - IOKit Battery Reading

    private static func readBatteryInfo() -> (level: Int, isCharging: Bool, isPluggedIn: Bool, temperature: Double) {
        var level = 0, isCharging = false, isPluggedIn = false, temperature = 0.0

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return (level, isCharging, isPluggedIn, temperature) }
        defer { IOObjectRelease(service) }

        if let cur = prop(service, "CurrentCapacity") as? Int,
           let max = prop(service, "MaxCapacity") as? Int, max > 0 {
            level = Int(Double(cur) / Double(max) * 100.0)
        }
        if let c = prop(service, "IsCharging") as? Bool { isCharging = c }
        if let e = prop(service, "ExternalConnected") as? Bool { isPluggedIn = e }
        if let t = prop(service, "Temperature") as? Int { temperature = Double(t) / 100.0 }

        return (level, isCharging, isPluggedIn, temperature)
    }

    private static func prop(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
