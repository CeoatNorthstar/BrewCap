import AppKit
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var mainWindow: NSWindow?
    let batteryManager = BatteryManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateMenuBarIcon()

        // Build the dropdown menu
        setupMenu()

        // Observe battery updates to refresh the icon, menu, and tooltip
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
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Dynamic Menu Bar Icon

    private func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }

        let symbolName = "cup.and.saucer.fill"
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        guard let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: "BrewCap")?
            .withSymbolConfiguration(config) else { return }

        if !batteryManager.isPluggedIn {
            button.image = baseImage
            button.contentTintColor = nil
        } else if batteryManager.chargingInhibited {
            // Charging paused by SMC → orange
            button.image = baseImage
            button.contentTintColor = .systemOrange
        } else if batteryManager.batteryLevel >= Int(batteryManager.chargeLimit) {
            button.image = baseImage
            button.contentTintColor = .systemOrange
        } else {
            button.image = baseImage
            button.contentTintColor = .systemGreen
        }

        button.toolTip = "BrewCap — \(batteryManager.batteryLevel)%"
    }

    // MARK: - Menu Setup

    private func setupMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // ── Title ──────────────────────────
        let titleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = makeAttributedTitle(
            "BrewCap",
            systemImage: "cup.and.saucer.fill",
            bold: true,
            size: 13
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // ── Battery Stats ──────────────────
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

        menu.addItem(NSMenuItem.separator())

        // ── Sailing Mode ───────────────────
        let sailingItem = NSMenuItem(
            title: "  Sailing Mode: Off",
            action: #selector(toggleSailingMode),
            keyEquivalent: "s"
        )
        sailingItem.keyEquivalentModifierMask = [.command]
        sailingItem.tag = 104
        menu.addItem(sailingItem)

        menu.addItem(NSMenuItem.separator())

        // ── Actions ────────────────────────
        let openItem = NSMenuItem(
            title: "Open BrewCap…",
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        )
        openItem.keyEquivalentModifierMask = [.command]
        openItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        menu.addItem(openItem)

        let quitItem = NSMenuItem(
            title: "Quit BrewCap",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        menu.addItem(quitItem)

        menu.addItem(NSMenuItem.separator())

        // ── Version Footer ─────────────────
        let versionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let versionStr = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        versionItem.attributedTitle = NSAttributedString(
            string: "v\(versionStr)",
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
            batteryItem.image = menuImage(
                systemName: "battery.\(batteryIconLevel)",
                tint: batteryColor
            )
            batteryItem.title = "  Battery   \(batteryManager.batteryLevel)%"
        }

        // Charging status
        if let statusMenuItem = menu.item(withTag: 101) {
            if batteryManager.chargingInhibited {
                statusMenuItem.image = menuImage(systemName: "pause.circle.fill", tint: .systemOrange)
                statusMenuItem.title = "  Status     Paused"
            } else if batteryManager.isCharging {
                statusMenuItem.image = menuImage(systemName: "bolt.fill", tint: .systemGreen)
                statusMenuItem.title = "  Status     Charging"
            } else if batteryManager.isPluggedIn {
                statusMenuItem.image = menuImage(systemName: "powerplug.fill", tint: .systemOrange)
                statusMenuItem.title = "  Status     Plugged In"
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
            tempItem.title = "  Temp      \(String(format: "%.1f°C", batteryManager.temperature))"
        }

        // Charge limit
        if let limitItem = menu.item(withTag: 103) {
            limitItem.image = menuImage(systemName: "gauge.with.needle", tint: .systemBlue)
            limitItem.title = "  Limit       \(Int(batteryManager.chargeLimit))%"
        }

        // Sailing mode
        if let sailingItem = menu.item(withTag: 104) {
            if batteryManager.sailingModeEnabled && batteryManager.chargingInhibited {
                sailingItem.image = menuImage(systemName: "pause.circle.fill", tint: .systemOrange)
                sailingItem.title = "  Sailing Mode — Paused ⚡"
            } else if batteryManager.sailingModeEnabled {
                sailingItem.image = menuImage(systemName: "sailboat.fill", tint: .systemBlue)
                sailingItem.title = "  Sailing Mode — Active"
            } else {
                sailingItem.image = menuImage(systemName: "sailboat", tint: .secondaryLabelColor)
                sailingItem.title = "  Sailing Mode — Off"
            }
        }

        // Update tooltip
        statusItem.button?.toolTip = "BrewCap — \(batteryManager.batteryLevel)%"
    }

    @objc func toggleSailingMode() {
        batteryManager.sailingModeEnabled.toggle()
        refreshMenuInfo()
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
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = MainWindowView(batteryManager: batteryManager)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 600),
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
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitApp() {
        // Re-enable charging on quit to be safe
        if batteryManager.chargingInhibited {
            _ = SMCClient.enableCharging()
        }
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - NSWindowDelegate
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Window closes, app keeps running in the menu bar
    }
}
