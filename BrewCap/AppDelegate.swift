//
//  AppDelegate.swift
//  BrewCap
//
//  Copyright (c) 2026 NorthStars Industries. All rights reserved.
//

import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var mainWindow: NSWindow?
    var aboutWindow: NSWindow?
    var settingsWindow: NSWindow?
    let batteryManager = BatteryManager()
    var menuPopover: NSPopover?

    // Feature 27: Global Hotkey
    private var globalHotkeyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock at runtime (replaces LSUIElement so app stays in Launchpad/Spotlight)
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon()
        setupGlassMenu()

        // Update checker: set delegate, start periodic background checks
        UNUserNotificationCenter.current().delegate = self
        UpdateChecker.shared.startChecking()
        UpdateChecker.shared.$updateAvailable
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshMenuInfo() }
            .store(in: &cancellables)

        // Battery observers
        batteryManager.$batteryLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarIcon()
                self?.refreshMenuInfo()
            }
            .store(in: &cancellables)

        batteryManager.$isPluggedIn
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarIcon()
                self?.refreshMenuInfo()
            }
            .store(in: &cancellables)

        batteryManager.$chargingInhibited
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarIcon()
                self?.refreshMenuInfo()
            }
            .store(in: &cancellables)

        batteryManager.$showPercentageInMenuBar
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarIcon() }
            .store(in: &cancellables)

        batteryManager.$menuBarDisplayMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarIcon() }
            .store(in: &cancellables)

        // Feature 27: Register global hotkey
        registerGlobalHotkey()

        // Settings window notification
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsWindow),
                                               name: .openSettings, object: nil)
    }

    // MARK: - Feature 27: Global Hotkey

    private func registerGlobalHotkey() {
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 11 {
                DispatchQueue.main.async {
                    self?.batteryManager.sailingModeEnabled.toggle()
                    self?.refreshMenuInfo()
                }
            }
        }
    }

    // MARK: - Menu Bar Icon

    private func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        guard let image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "BrewCap")?
            .withSymbolConfiguration(config) else { return }

        button.image = image
        button.image?.isTemplate = true

        // Only tint red for critical low battery
        let level = batteryManager.batteryLevel
        if !batteryManager.isPluggedIn && level <= batteryManager.lowBatteryThreshold {
            button.contentTintColor = .systemRed
        } else {
            button.contentTintColor = nil
        }

        // Menu bar display modes
        let mode = batteryManager.menuBarDisplayMode
        if batteryManager.showPercentageInMenuBar || mode > 0 {
            switch mode {
            case 1:
                button.title = " \(batteryManager.timeRemaining)"
                button.imagePosition = .imageLeading
            case 2:
                button.title = " \(String(format: "%.1fW", batteryManager.powerDrawWatts))"
                button.imagePosition = .imageLeading
            default:
                button.title = " \(batteryManager.batteryLevel)%"
                button.imagePosition = .imageLeading
            }
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }

        // Tooltip
        var tip = "BrewCap — \(batteryManager.batteryLevel)%"
        if batteryManager.isPluggedIn {
            tip += " · \(batteryManager.isCharging ? "Charging" : "Plugged In")"
        }
        if batteryManager.sailingModeEnabled {
            tip += " · Limit \(Int(batteryManager.chargeLimit))%"
        }
        button.toolTip = tip
    }

    // MARK: - Glass Menu Setup
    
    private func setupGlassMenu() {
        if let button = statusItem.button {
            button.action = #selector(toggleGlassMenu)
            button.target = self
        }
        
        // Create popover
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 600)
        
        let menuView = GlassMenuView(
            batteryManager: batteryManager,
            updateChecker: UpdateChecker.shared,
            onOpenMain: { [weak self] in self?.openMainWindow() },
            onExportReport: { [weak self] in self?.exportReport() },
            onCopyStats: { [weak self] in self?.copyStats() },
            onShowAbout: { [weak self] in self?.showAbout() },
            onCheckUpdates: { [weak self] in self?.checkForUpdates() },
            onQuit: { [weak self] in self?.quitApp() },
            onClose: { [weak self] in self?.closeGlassMenu() },
            onUpgrade: { [weak self] in self?.openMainWindowToUpgrade() }
        )
        
        let hostingController = NSHostingController(rootView: menuView)
        popover.contentViewController = hostingController
        
        self.menuPopover = popover
    }
    
    @objc private func toggleGlassMenu() {
        guard let button = statusItem.button else { return }
        
        if let popover = menuPopover, popover.isShown {
            popover.performClose(nil)
        } else {
            menuPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    private func closeGlassMenu() {
        menuPopover?.performClose(nil)
    }
    
    // MARK: - Old Menu Setup (Keeping for reference, can be removed)
    
    private func setupMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // ── Status line
        let statusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusItem.tag = 100
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // ── Info rows
        let healthTempItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        healthTempItem.tag = 101
        healthTempItem.isEnabled = false
        menu.addItem(healthTempItem)

        let cyclesPowerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        cyclesPowerItem.tag = 102
        cyclesPowerItem.isEnabled = false
        menu.addItem(cyclesPowerItem)

        let timeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        timeItem.tag = 103
        timeItem.isEnabled = false
        menu.addItem(timeItem)

        let adapterItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        adapterItem.tag = 104
        adapterItem.isEnabled = false
        menu.addItem(adapterItem)

        menu.addItem(NSMenuItem.separator())

        // ── Sailing Mode toggle
        let sailingItem = NSMenuItem(title: "Sailing Mode", action: #selector(toggleSailingMode), keyEquivalent: "s")
        sailingItem.tag = 200
        sailingItem.keyEquivalentModifierMask = [.command]
        menu.addItem(sailingItem)

        // ── Show in Menu Bar toggle
        let percentItem = NSMenuItem(title: "Show in Menu Bar", action: #selector(togglePercentage), keyEquivalent: "")
        percentItem.tag = 201
        menu.addItem(percentItem)

        menu.addItem(NSMenuItem.separator())

        // ── Actions
        let openItem = NSMenuItem(title: "Open BrewCap\u{2026}", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.keyEquivalentModifierMask = [.command]
        menu.addItem(openItem)

        let exportItem = NSMenuItem(title: "Export Report\u{2026}", action: #selector(exportReport), keyEquivalent: "e")
        exportItem.keyEquivalentModifierMask = [.command]
        menu.addItem(exportItem)

        let copyItem = NSMenuItem(title: "Copy Stats", action: #selector(copyStats), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(copyItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About BrewCap", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(aboutItem)

        let updateItem = NSMenuItem(title: "Check for Updates\u{2026}", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.tag = 300
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit BrewCap", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        self.statusItem.menu = menu
        refreshMenuInfo()
    }

    private func refreshMenuInfo() {
        guard let menu = statusItem.menu else { return }

        let level = batteryManager.batteryLevel
        let plugged = batteryManager.isPluggedIn

        // Status line
        if let item = menu.item(withTag: 100) {
            var status = "Battery: \(level)%"
            if plugged {
                if batteryManager.chargingInhibited {
                    status += " — Paused"
                } else if batteryManager.isCharging {
                    status += " — Charging"
                } else {
                    status += " — Plugged In"
                }
            } else {
                status += " — On Battery"
            }
            item.title = status
        }

        // Health & Temp
        if let item = menu.item(withTag: 101) {
            item.title = "Health: \(batteryManager.healthPercent)%   Temp: \(String(format: "%.1f\u{00B0}C", batteryManager.temperature))"
        }

        // Cycles & Power
        if let item = menu.item(withTag: 102) {
            item.title = "Cycles: \(batteryManager.cycleCount)   Power: \(String(format: "%.1f W", batteryManager.powerDrawWatts))"
        }

        // Time
        if let item = menu.item(withTag: 103) {
            item.title = "Time: \(batteryManager.timeRemaining)"
        }

        // Adapter
        if let item = menu.item(withTag: 104) {
            if plugged {
                item.title = "Adapter: \(batteryManager.adapterName) (\(batteryManager.adapterWatts)W)"
                item.isHidden = false
            } else {
                item.isHidden = true
            }
        }

        // Sailing Mode
        if let item = menu.item(withTag: 200) {
            // Check if Pro license - use currentTier which is published
            let isPro = LicenseManager.shared.currentTier == .pro
            if isPro {
                item.state = batteryManager.sailingModeEnabled ? .on : .off
                if batteryManager.sailingModeEnabled {
                    item.title = "Sailing Mode — Limit: \(Int(batteryManager.chargeLimit))%"
                } else {
                    item.title = "Sailing Mode"
                }
            } else {
                item.state = .off
                item.title = "Sailing Mode (Pro)"
            }
        }

        // Show in Menu Bar
        if let item = menu.item(withTag: 201) {
            item.state = batteryManager.showPercentageInMenuBar ? .on : .off
        }

        // Update available
        if let item = menu.item(withTag: 300) {
            if UpdateChecker.shared.updateAvailable, let v = UpdateChecker.shared.latestVersion {
                item.title = "Update Available: v\(v)"
            } else {
                item.title = "Check for Updates\u{2026}"
            }
        }
    }

    // MARK: - Menu Actions

    @objc func toggleSailingMode() {
        // Check license before allowing toggle
        Task { @MainActor in
            if LicenseManager.shared.hasAccess(to: .sailingMode) {
                batteryManager.sailingModeEnabled.toggle()
            } else {
                // Open main window and go to upgrade tab
                openMainWindowToUpgrade()
            }
        }
    }
    
    private func openMainWindowToUpgrade() {
        // Close the popover first
        menuPopover?.close()
        
        // Open main window - the upgrade tab will be visible for free users
        openMainWindow()
        
        // Post notification to navigate to upgrade tab
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .navigateToUpgrade, object: nil)
        }
    }

    @objc func togglePercentage() {
        batteryManager.showPercentageInMenuBar.toggle()
        updateMenuBarIcon()
    }

    @objc func exportReport() {
        if let url = ReportGenerator.saveToDesktop(from: batteryManager) {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
        }
    }

    @objc func copyStats() {
        batteryManager.copyStatsToClipboard()
    }

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
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BrewCap"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("MainWindow")
        window.minSize = NSSize(width: 650, height: 450)

        self.mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

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
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "About BrewCap"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.aboutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(batteryManager: batteryManager)
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "BrewCap Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.settingsWindow = window
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

    @objc func checkForUpdates() {
        UpdateChecker.shared.checkForUpdate { available, _ in
            if available {
                UpdateChecker.shared.promptUpdate()
            } else {
                let alert = NSAlert()
                alert.messageText = "You\u{2019}re Up to Date"
                alert.informativeText = "BrewCap v\(UpdateChecker.shared.currentVersion) is the latest version."
                alert.alertStyle = .informational
                alert.icon = NSApp.applicationIconImage
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier.hasPrefix("brewcap.update.") {
            DispatchQueue.main.async { UpdateChecker.shared.promptUpdate() }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - NSWindowDelegate
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            let hasVisibleWindows = (self.mainWindow?.isVisible == true) || (self.aboutWindow?.isVisible == true) || (self.settingsWindow?.isVisible == true)
            if !hasVisibleWindows {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)

            Text("BrewCap")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)

            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.5"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
            Text("Version \(version) (\(build))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("Copyright \u{00A9} 2026 NorthStars Industries.\nAll rights reserved.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(width: 300)
        .floatingGlass(padding: 24, cornerRadius: 20)
        .padding(20)
        .glassWindowBackground()
    }
}
