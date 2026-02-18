import AppKit
import Combine
import SwiftUI
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var mainWindow: NSWindow?
    var aboutWindow: NSWindow?
    let batteryManager = BatteryManager()

    // Feature 27: Global Hotkey
    private var globalHotkeyMonitor: Any?

    // Feature 47: Pulse timer
    private var pulseTimer: Timer?
    private var pulsePhase: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock at runtime (replaces LSUIElement so app stays in Launchpad/Spotlight)
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon()
        setupMenu()

        // Battery level observer
        batteryManager.$batteryLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarIcon()
                self?.refreshMenuInfo()
            }
            .store(in: &cancellables)

        // Plugged in observer
        batteryManager.$isPluggedIn
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarIcon()
                self?.refreshMenuInfo()
            }
            .store(in: &cancellables)

        // Charging inhibited observer
        batteryManager.$chargingInhibited
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarIcon()
                self?.refreshMenuInfo()
            }
            .store(in: &cancellables)

        // Feature 23/43: Display mode observer
        batteryManager.$showPercentageInMenuBar
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarIcon()
            }
            .store(in: &cancellables)

        batteryManager.$menuBarDisplayMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarIcon()
            }
            .store(in: &cancellables)

        // Feature 47: Low battery pulse
        startPulseMonitor()

        // Feature 27: Register global hotkey ⌘⇧B
        registerGlobalHotkey()
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Feature 27: Global Hotkey

    private func registerGlobalHotkey() {
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ⌘⇧B
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 11 { // 'B'
                DispatchQueue.main.async {
                    self?.batteryManager.sailingModeEnabled.toggle()
                    self?.refreshMenuInfo()
                }
            }
        }
    }

    // MARK: - Feature 47: Low Battery Pulse

    private func startPulseMonitor() {
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.batteryManager.batteryLevel <= self.batteryManager.lowBatteryThreshold && !self.batteryManager.isPluggedIn {
                self.pulsePhase.toggle()
                self.updateMenuBarIcon()
            }
        }
    }

    // MARK: - Dynamic Menu Bar Icon

    private func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }

        let symbolName = "cup.and.saucer.fill"
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        guard let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: "BrewCap")?
            .withSymbolConfiguration(config) else { return }

        // Feature 44: Color-tinted icon
        let level = batteryManager.batteryLevel
        if !batteryManager.isPluggedIn {
            // Feature 47: Pulse on low battery
            if level <= batteryManager.lowBatteryThreshold {
                button.image = baseImage
                button.contentTintColor = pulsePhase ? .systemRed : .secondaryLabelColor
            } else if level <= 50 {
                button.image = baseImage
                button.contentTintColor = .systemYellow
            } else {
                button.image = baseImage
                button.contentTintColor = nil
            }
        } else if batteryManager.chargingInhibited {
            button.image = baseImage
            button.contentTintColor = .systemOrange
        } else if level >= Int(batteryManager.chargeLimit) {
            button.image = baseImage
            button.contentTintColor = .systemOrange
        } else {
            button.image = baseImage
            button.contentTintColor = .systemGreen
        }

        // Feature 43: Menu bar display modes (0=%, 1=time, 2=watts)
        let mode = batteryManager.menuBarDisplayMode
        if batteryManager.showPercentageInMenuBar || mode > 0 {
            switch mode {
            case 1: // Time remaining
                button.title = " \(batteryManager.timeRemaining)"
                button.imagePosition = .imageLeading
            case 2: // Power draw
                button.title = " \(String(format: "%.1fW", batteryManager.powerDrawWatts))"
                button.imagePosition = .imageLeading
            default: // Percentage
                button.title = " \(batteryManager.batteryLevel)%"
                button.imagePosition = .imageLeading
            }
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }

        // Feature 45: Rich tooltip
        var tooltip = "BrewCap — \(batteryManager.batteryLevel)%"
        tooltip += "\nHealth: \(batteryManager.healthPercent)%"
        tooltip += "\nTemp: \(String(format: "%.1f°C", batteryManager.temperature))"
        if batteryManager.isPluggedIn {
            tooltip += "\nPower: \(String(format: "%.1fW", batteryManager.powerDrawWatts))"
            tooltip += "\nAdapter: \(batteryManager.adapterName)"
        } else {
            tooltip += "\nTime: \(batteryManager.timeRemaining)"
        }
        if batteryManager.sailingModeEnabled {
            tooltip += "\nSailing Mode: ✓ (Limit: \(Int(batteryManager.chargeLimit))%)"
        }
        button.toolTip = tooltip

        // Feature 48: Notification badge dot
        if batteryManager.hasPendingAlert {
            button.title = (button.title.isEmpty ? "" : button.title) + " •"
        }
    }

    // MARK: - Menu Setup

    private func setupMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // ── Title
        let titleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = makeAttributedTitle("BrewCap", systemImage: "cup.and.saucer.fill", bold: true, size: 13)
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // ── Battery Stats
        let batteryItem = NSMenuItem(title: "Battery: ---", action: nil, keyEquivalent: "")
        batteryItem.tag = 100
        batteryItem.isEnabled = false
        menu.addItem(batteryItem)

        let chargingStatusItem = NSMenuItem(title: "Status: ---", action: nil, keyEquivalent: "")
        chargingStatusItem.tag = 101
        chargingStatusItem.isEnabled = false
        menu.addItem(chargingStatusItem)

        let tempItem = NSMenuItem(title: "Temp: ---", action: nil, keyEquivalent: "")
        tempItem.tag = 102
        tempItem.isEnabled = false
        menu.addItem(tempItem)

        let limitItem = NSMenuItem(title: "Limit: ---", action: nil, keyEquivalent: "")
        limitItem.tag = 103
        limitItem.isEnabled = false
        menu.addItem(limitItem)

        let healthItem = NSMenuItem(title: "Health: ---", action: nil, keyEquivalent: "")
        healthItem.tag = 105
        healthItem.isEnabled = false
        menu.addItem(healthItem)

        let timeItem = NSMenuItem(title: "Time: ---", action: nil, keyEquivalent: "")
        timeItem.tag = 106
        timeItem.isEnabled = false
        menu.addItem(timeItem)

        let adapterItem = NSMenuItem(title: "Adapter: ---", action: nil, keyEquivalent: "")
        adapterItem.tag = 107
        adapterItem.isEnabled = false
        menu.addItem(adapterItem)

        // Feature 31: Power draw
        let powerItem = NSMenuItem(title: "Power: ---", action: nil, keyEquivalent: "")
        powerItem.tag = 109
        powerItem.isEnabled = false
        menu.addItem(powerItem)

        menu.addItem(NSMenuItem.separator())

        // ── Sailing Mode
        let sailingItem = NSMenuItem(title: "Sailing Mode", action: #selector(toggleSailingMode), keyEquivalent: "s")
        sailingItem.tag = 104
        sailingItem.keyEquivalentModifierMask = [.command]
        menu.addItem(sailingItem)

        // Percentage toggle
        let percentItem = NSMenuItem(title: "Show % in Menu Bar", action: #selector(togglePercentage), keyEquivalent: "")
        percentItem.tag = 108
        menu.addItem(percentItem)

        // Feature 43: Cycle display mode
        let cycleItem = NSMenuItem(title: "Cycle Display Mode", action: #selector(cycleDisplayMode), keyEquivalent: "d")
        cycleItem.keyEquivalentModifierMask = [.command]
        menu.addItem(cycleItem)

        menu.addItem(NSMenuItem.separator())

        // ── Actions
        let openItem = NSMenuItem(title: "Open BrewCap…", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.keyEquivalentModifierMask = [.command]
        openItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        menu.addItem(openItem)

        // Feature 21: Export Report
        let exportItem = NSMenuItem(title: "Export Report…", action: #selector(exportReport), keyEquivalent: "e")
        exportItem.keyEquivalentModifierMask = [.command]
        exportItem.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        menu.addItem(exportItem)

        // Feature 50: Copy stats
        let copyItem = NSMenuItem(title: "Copy Stats", action: #selector(copyStats), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = [.command, .shift]
        copyItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        menu.addItem(copyItem)

        // About
        let aboutItem = NSMenuItem(title: "About BrewCap", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit BrewCap", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        menu.addItem(quitItem)

        menu.addItem(NSMenuItem.separator())

        let versionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let versionStr = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        versionItem.attributedTitle = NSAttributedString(
            string: "v\(versionStr)  ·  ⌘⇧B sailing  ·  ⌘D display",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        self.statusItem.menu = menu
        refreshMenuInfo()
    }

    private func refreshMenuInfo() {
        guard let menu = statusItem.menu else { return }

        // Battery percentage
        if let batteryItem = menu.item(withTag: 100) {
            batteryItem.image = menuImage(systemName: "battery.\(batteryIconLevel)", tint: batteryColor)
            batteryItem.title = "  Battery     \(batteryManager.batteryLevel)%"
        }

        // Charging status
        if let statusMenuItem = menu.item(withTag: 101) {
            if batteryManager.isPluggedIn {
                if batteryManager.chargingInhibited {
                    statusMenuItem.image = menuImage(systemName: "pause.circle.fill", tint: .systemOrange)
                    statusMenuItem.title = "  Status     Paused"
                } else if batteryManager.isCharging {
                    statusMenuItem.image = menuImage(systemName: "bolt.fill", tint: .systemGreen)
                    statusMenuItem.title = "  Status     Charging"
                } else {
                    statusMenuItem.image = menuImage(systemName: "powerplug.fill", tint: .systemGreen)
                    statusMenuItem.title = "  Status     Plugged In"
                }
            } else {
                statusMenuItem.image = menuImage(systemName: "powerplug", tint: .secondaryLabelColor)
                statusMenuItem.title = "  Status     On Battery"
            }
        }

        // Temperature
        if let tempItem = menu.item(withTag: 102) {
            let tempColor: NSColor = batteryManager.temperature >= 40 ? .systemRed :
                                     batteryManager.temperature >= 35 ? .systemOrange : .secondaryLabelColor
            tempItem.image = menuImage(systemName: "thermometer.medium", tint: tempColor)
            tempItem.title = "  Temp        \(String(format: "%.1f°C", batteryManager.temperature))"
        }

        // Limit
        if let limitItem = menu.item(withTag: 103) {
            limitItem.image = menuImage(systemName: "gauge.with.needle", tint: .secondaryLabelColor)
            limitItem.title = "  Limit        \(Int(batteryManager.chargeLimit))%"
        }

        // Sailing mode
        if let sailingItem = menu.item(withTag: 104) {
            if batteryManager.sailingModeEnabled {
                sailingItem.image = menuImage(systemName: "sailboat.fill", tint: .systemBlue)
                sailingItem.title = "  Sailing Mode — On"
            } else {
                sailingItem.image = menuImage(systemName: "sailboat", tint: .secondaryLabelColor)
                sailingItem.title = "  Sailing Mode — Off"
            }
        }

        // Health
        if let healthItem = menu.item(withTag: 105) {
            let hColor: NSColor = batteryManager.healthPercent >= 80 ? .systemGreen :
                                  batteryManager.healthPercent >= 60 ? .systemOrange : .systemRed
            healthItem.image = menuImage(systemName: "heart.fill", tint: hColor)
            healthItem.title = "  Health      \(batteryManager.healthPercent)%"
        }

        // Time remaining
        if let timeItem = menu.item(withTag: 106) {
            timeItem.image = menuImage(systemName: "clock", tint: .secondaryLabelColor)
            timeItem.title = "  Time        \(batteryManager.timeRemaining)"
        }

        // Adapter
        if let adapterItem = menu.item(withTag: 107) {
            if batteryManager.isPluggedIn {
                adapterItem.image = menuImage(systemName: "power.dotted", tint: .systemGreen)
                adapterItem.title = "  Adapter    \(batteryManager.adapterName) (\(batteryManager.adapterWatts)W)"
            } else {
                adapterItem.image = menuImage(systemName: "power.dotted", tint: .secondaryLabelColor)
                adapterItem.title = "  Adapter    Not Connected"
            }
        }

        // Feature 31: Power draw
        if let powerItem = menu.item(withTag: 109) {
            let draw = batteryManager.powerDrawWatts
            powerItem.image = menuImage(systemName: "bolt.circle", tint: draw > 15 ? .systemOrange : .secondaryLabelColor)
            powerItem.title = "  Power       \(String(format: "%.1f W", draw))  ·  \(batteryManager.usageIntensity)"
        }

        // Percentage toggle
        if let percentItem = menu.item(withTag: 108) {
            percentItem.state = batteryManager.showPercentageInMenuBar ? .on : .off
        }

        statusItem.button?.toolTip = "BrewCap — \(batteryManager.batteryLevel)%"
    }

    @objc func toggleSailingMode() {
        batteryManager.sailingModeEnabled.toggle()
        refreshMenuInfo()
    }

    @objc func togglePercentage() {
        batteryManager.showPercentageInMenuBar.toggle()
        updateMenuBarIcon()
        refreshMenuInfo()
    }

    // Feature 43: Cycle display mode
    @objc func cycleDisplayMode() {
        batteryManager.menuBarDisplayMode = (batteryManager.menuBarDisplayMode + 1) % 3
        updateMenuBarIcon()
    }

    @objc func exportReport() {
        if let url = ReportGenerator.saveToDesktop(from: batteryManager) {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
        }
    }

    // Feature 50: Copy stats
    @objc func copyStats() {
        batteryManager.copyStatsToClipboard()
    }

    // MARK: - Menu Helpers

    private var batteryIconLevel: String {
        let level = batteryManager.batteryLevel
        switch level {
        case 0..<13: return "0"
        case 13..<38: return "25"
        case 38..<63: return "50"
        case 63..<88: return "75"
        default: return "100"
        }
    }

    private var batteryColor: NSColor {
        let level = batteryManager.batteryLevel
        if level <= 20 { return .systemRed }
        if level <= 50 { return .systemOrange }
        return .systemGreen
    }

    private func menuImage(systemName: String, tint: NSColor) -> NSImage? {
        guard let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) else { return nil }

        let tinted = image.copy() as! NSImage
        tinted.lockFocus()
        tint.set()
        let rect = NSRect(origin: .zero, size: tinted.size)
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }

    private func makeAttributedTitle(_ text: String, systemImage: String, bold: Bool = false, size: CGFloat = 13) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: bold ? .bold : .regular)
        if let img = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            attachment.image = img
        }

        let result = NSMutableAttributedString(attachment: attachment)
        let font: NSFont = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        result.append(NSAttributedString(string: "  \(text)", attributes: [.font: font]))
        return result
    }

    // MARK: - Actions

    @objc func openMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = MainWindowView(batteryManager: batteryManager)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 740),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BrewCap"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Feature 24: About Window
    @objc func showAbout() {
        if let window = aboutWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutView = AboutView()
        let hostingView = NSHostingView(rootView: aboutView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About BrewCap"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.aboutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitApp() {
        if batteryManager.chargingInhibited {
            _ = SMCClient.enableCharging()
        }
        batteryManager.logEvent("BrewCap quit")
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - NSWindowDelegate
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // If no more visible app windows, hide from Dock again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            let hasVisibleWindows = (self.mainWindow?.isVisible == true) || (self.aboutWindow?.isVisible == true)
            if !hasVisibleWindows {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

// MARK: - About View
struct AboutView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Icon + Title
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.brown.opacity(0.3), Color.brown.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.brown, Color(red: 0.6, green: 0.4, blue: 0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                Text("BrewCap")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                Text("Version \(version) · Build \(build)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            Divider()
                .padding(.horizontal, 40)
                .padding(.vertical, 14)

            // Feature highlights
            VStack(spacing: 8) {
                aboutFeatureRow(icon: "bolt.shield.fill", color: .blue, text: "Hardware-level SMC charge control")
                aboutFeatureRow(icon: "chart.line.downtrend.xyaxis", color: .green, text: "Battery health & capacity tracking")
                aboutFeatureRow(icon: "bell.badge.fill", color: .orange, text: "Smart alerts & power analytics")
            }
            .padding(.horizontal, 24)

            Spacer()

            // Footer
            VStack(spacing: 6) {
                Link(destination: URL(string: "https://github.com/CeoatNorthstar/BrewCap")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 9))
                        Text("github.com/CeoatNorthstar/BrewCap")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.blue.opacity(0.8))
                }

                Text("© 2026 Northstar · Made with ☕")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }
            .padding(.bottom, 18)
        }
        .frame(width: 320, height: 320)
    }

    private func aboutFeatureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

