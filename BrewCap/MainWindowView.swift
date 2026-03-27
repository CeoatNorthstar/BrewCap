//
//  MainWindowView.swift
//  BrewCap
//
//  Copyright (c) 2026 NorthStars Industries. All rights reserved.
//

import SwiftUI
import ServiceManagement
import CoreImage.CIFilterBuiltins

// MARK: - Main Window

struct MainWindowView: View {
    @ObservedObject var batteryManager: BatteryManager
    @State private var showSetupAlert = false
    @State private var flashCopied = false
    @State private var showShareStats = false
    @State private var showShareApp = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: Battery overview
            VStack(spacing: 0) {
                batteryPanel
                    .frame(maxHeight: .infinity)
                chargingPanel
            }
            .frame(width: 280)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Right: Details + actions
            VStack(spacing: 0) {
                detailsPanel
                    .frame(maxHeight: .infinity)
                actionBar
            }
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 680, height: 440)
        .onReceive(batteryManager.$setupNeeded) { needed in
            if needed { showSetupAlert = true }
        }
        .alert("Admin Access Required", isPresented: $showSetupAlert) {
            Button("Grant Access") {
                batteryManager.runSetup { success in
                    if !success { batteryManager.sailingModeEnabled = false }
                }
            }
            Button("Cancel", role: .cancel) {
                batteryManager.sailingModeEnabled = false
                batteryManager.setupNeeded = false
            }
        } message: {
            Text("BrewCap needs one-time admin access to control charging via SMC.")
        }
        .overlay(alignment: .top) {
            if flashCopied {
                Text("Copied")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.green, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showShareStats) {
            ShareStatsSheet(batteryManager: batteryManager)
        }
        .sheet(isPresented: $showShareApp) {
            ShareAppSheet()
        }
    }

    // MARK: - Left: Battery Panel

    private var batteryPanel: some View {
        VStack(spacing: 20) {
            Spacer()

            // Big percentage
            Text("\(batteryManager.batteryLevel)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .overlay(alignment: .trailing) {
                    Text("%")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .offset(x: 28, y: -12)
                }

            // Progress bar
            ProgressView(value: Double(batteryManager.batteryLevel), total: 100)
                .tint(progressColor)
                .padding(.horizontal, 40)

            // Status
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if batteryManager.chargingInhibited {
                Text("Paused at \(Int(batteryManager.chargeLimit))%")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
        .padding()
    }

    private var progressColor: Color {
        if batteryManager.chargingInhibited { return .orange }
        if batteryManager.batteryLevel <= 20 { return .red }
        return .accentColor
    }

    private var statusText: String {
        if batteryManager.isPluggedIn {
            if batteryManager.chargingInhibited { return "Sailing Mode Active" }
            if batteryManager.isCharging { return "Charging \u{00B7} \(batteryManager.timeRemaining)" }
            return "Connected"
        }
        return "On Battery \u{00B7} \(batteryManager.timeRemaining)"
    }

    // MARK: - Left: Charging Panel

    private var chargingPanel: some View {
        VStack(spacing: 10) {
            Divider()

            HStack {
                Text("Sailing Mode")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Toggle("", isOn: $batteryManager.sailingModeEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if batteryManager.sailingModeEnabled {
                HStack(spacing: 8) {
                    Slider(value: $batteryManager.chargeLimit, in: 20...100, step: 5)
                    Text("\(Int(batteryManager.chargeLimit))%")
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 36, alignment: .trailing)
                }

                Picker("", selection: Binding(
                    get: { Int(batteryManager.chargeLimit) },
                    set: { batteryManager.setChargePreset($0) }
                )) {
                    Text("60%").tag(60)
                    Text("80%").tag(80)
                    Text("100%").tag(100)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Right: Details Panel

    private var detailsPanel: some View {
        ScrollView {
            VStack(spacing: 0) {
                detailSection("Battery") {
                    DetailRow(label: "Health", value: "\(batteryManager.healthPercent)%")
                    DetailRow(label: "Condition", value: batteryManager.batteryCondition)
                    DetailRow(label: "Cycles", value: "\(batteryManager.cycleCount)")
                    DetailRow(label: "Capacity", value: "\(batteryManager.maxCapacity) / \(batteryManager.designCapacity) mAh")
                }

                detailSection("Power") {
                    DetailRow(label: "Temperature", value: String(format: "%.1f\u{00B0}C", batteryManager.temperature))
                    DetailRow(label: "Power Draw", value: String(format: "%.1f W", batteryManager.powerDrawWatts))
                    DetailRow(label: "Time", value: batteryManager.timeRemaining)
                    if batteryManager.isPluggedIn {
                        DetailRow(label: "Adapter", value: "\(batteryManager.adapterName) \u{00B7} \(batteryManager.adapterWatts)W")
                    }
                    if batteryManager.isPluggedIn && batteryManager.isCharging {
                        DetailRow(label: "Charge Speed", value: batteryManager.chargeSpeed)
                    }
                    if !batteryManager.isPluggedIn && batteryManager.averageDrainPerHour > 0 {
                        DetailRow(label: "Drain Rate", value: "\(batteryManager.averageDrainPerHour)%/hr")
                    }
                }
            }
            .padding(20)
        }
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
                .padding(.top, 4)

            VStack(spacing: 0) {
                content()
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.bottom, 16)
        }
    }

    // MARK: - Bottom Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                openSettingsWindow()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Button {
                batteryManager.copyStatsToClipboard()
                showCopied()
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }

            Button {
                showShareStats = true
            } label: {
                Label("Share Stats", systemImage: "square.and.arrow.up")
            }

            Button {
                showShareApp = true
            } label: {
                Label("Share App", systemImage: "qrcode")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Helpers

    private func openSettingsWindow() {
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    private func showCopied() {
        withAnimation { flashCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { flashCopied = false }
        }
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.body)
        .padding(.vertical, 5)
    }
}

// MARK: - Share Stats Sheet

struct ShareStatsSheet: View {
    @ObservedObject var batteryManager: BatteryManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStyle: Int = Int.random(in: 0..<10)
    @State private var renderedImage: NSImage?

    private let cardStyles: [(Color, Color, String)] = [
        (.blue, .cyan, "bolt.fill"),
        (.purple, .pink, "battery.100.bolt"),
        (.green, .mint, "leaf.fill"),
        (.orange, .yellow, "sun.max.fill"),
        (.indigo, .blue, "moon.stars.fill"),
        (.red, .orange, "flame.fill"),
        (.teal, .green, "drop.fill"),
        (.pink, .purple, "heart.fill"),
        (.gray, .blue, "cloud.fill"),
        (.cyan, .teal, "wave.3.right"),
    ]

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Share Battery Stats")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            // Preview
            statsCard
                .frame(width: 400, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)

            // Style picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<10, id: \.self) { index in
                        let style = cardStyles[index]
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(colors: [style.0, style.1], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 22)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(.white.opacity(selectedStyle == index ? 1 : 0), lineWidth: 2)
                            )
                            .onTapGesture { selectedStyle = index }
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    if let image = renderCard() {
                        let picker = NSSharingServicePicker(items: [image])
                        if let window = NSApp.keyWindow, let contentView = window.contentView {
                            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
                        }
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    if let image = renderCard() {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([image])
                        dismiss()
                    }
                } label: {
                    Label("Copy Image", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var statsCard: some View {
        let style = cardStyles[selectedStyle]
        return ZStack {
            LinearGradient(colors: [style.0, style.1], startPoint: .topLeading, endPoint: .bottomTrailing)

            HStack(spacing: 24) {
                // Left: big percentage
                VStack(spacing: 4) {
                    Image(systemName: style.2)
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(batteryManager.batteryLevel)%")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(batteryManager.isPluggedIn ? "Charging" : "On Battery")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)

                // Right: stats
                VStack(alignment: .leading, spacing: 8) {
                    StatLine(label: "Health", value: "\(batteryManager.healthPercent)%")
                    StatLine(label: "Temp", value: String(format: "%.1f\u{00B0}C", batteryManager.temperature))
                    StatLine(label: "Cycles", value: "\(batteryManager.cycleCount)")
                    StatLine(label: "Power", value: String(format: "%.1f W", batteryManager.powerDrawWatts))
                    StatLine(label: "Condition", value: batteryManager.batteryCondition)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(28)

            // Watermark
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("BrewCap")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(12)
                }
            }
        }
    }

    @MainActor
    private func renderCard() -> NSImage? {
        let renderer = ImageRenderer(content: statsCard.frame(width: 800, height: 440))
        renderer.scale = 2.0
        guard let cgImage = renderer.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 800, height: 440))
    }
}

private struct StatLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .font(.callout)
    }
}

// MARK: - Share App Sheet

struct ShareAppSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let appURL = "https://brewcap.app"

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Share BrewCap")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            // QR Code
            if let qrImage = generateQRCode(from: appURL) {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text("brewcap.app")
                .font(.title3.weight(.semibold))

            Text("Scan the QR code or share the link to get BrewCap.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    let picker = NSSharingServicePicker(items: [appURL])
                    if let window = NSApp.keyWindow, let contentView = window.contentView {
                        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
                    }
                } label: {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appURL, forType: .string)
                } label: {
                    Label("Copy Link", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    private func generateQRCode(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        let scale = 10.0
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: transformed)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}

// MARK: - Settings Window View

struct SettingsView: View {
    @ObservedObject var batteryManager: BatteryManager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 8)

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    settingsSection("Alerts", icon: "bell.fill") {
                        settingsRow("Temperature Alert") {
                            HStack {
                                Slider(value: $batteryManager.tempAlertThreshold, in: 30...50, step: 1)
                                    .frame(width: 140)
                                Text("\(Int(batteryManager.tempAlertThreshold))\u{00B0}C")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }

                        settingsRow("Low Battery") {
                            HStack {
                                Slider(value: Binding(
                                    get: { Double(batteryManager.lowBatteryThreshold) },
                                    set: { batteryManager.lowBatteryThreshold = Int($0) }
                                ), in: 5...40, step: 5)
                                    .frame(width: 140)
                                Text("\(batteryManager.lowBatteryThreshold)%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }

                        settingsToggle("Full Charge Notification", isOn: $batteryManager.fullChargeNotification)
                    }

                    settingsSection("Sounds", icon: "speaker.wave.2.fill") {
                        settingsToggle("Sound Effects", isOn: $batteryManager.soundEffectsEnabled)
                        settingsToggle("Do Not Disturb", isOn: $batteryManager.doNotDisturb)
                        settingsToggle("Charge Complete Chime", isOn: $batteryManager.chargeChimeEnabled)
                    }

                    settingsSection("Menu Bar", icon: "menubar.rectangle") {
                        settingsRow("Display") {
                            Picker("", selection: $batteryManager.menuBarDisplayMode) {
                                Text("Percentage").tag(0)
                                Text("Time").tag(1)
                                Text("Watts").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 200)
                        }

                        settingsToggle("Show Value in Menu Bar", isOn: $batteryManager.showPercentageInMenuBar)

                        settingsRow("Refresh Interval") {
                            HStack {
                                Slider(value: $batteryManager.monitoringInterval, in: 5...60, step: 5)
                                    .frame(width: 140)
                                Text("\(Int(batteryManager.monitoringInterval))s")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }
                    }

                    settingsSection("Behavior", icon: "gearshape.fill") {
                        settingsToggle("Auto-pause Below 20%", isOn: $batteryManager.autoPauseLowBattery)
                        settingsToggle("Launch at Login", isOn: $launchAtLogin)
                    }

                    settingsSection("Travel Mode", icon: "airplane") {
                        settingsToggle("Charge to 100% Temporarily", isOn: $batteryManager.travelModeEnabled)

                        if !batteryManager.travelModeEnabled {
                            settingsRow("Duration") {
                                HStack {
                                    Slider(value: $batteryManager.travelModeDuration, in: 1...24, step: 1)
                                        .frame(width: 140)
                                    Text("\(Int(batteryManager.travelModeDuration))h")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .trailing)
                                }
                            }
                        }

                        if batteryManager.travelModeEnabled, let expiry = batteryManager.travelModeExpiry {
                            HStack {
                                Spacer()
                                Text("Reverts \(expiry, style: .relative)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    settingsSection("Data", icon: "externaldrive.fill") {
                        HStack(spacing: 12) {
                            Button("Export Settings\u{2026}") { exportSettings() }
                            Button("Import Settings\u{2026}") { importSettings() }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        HStack {
                            Button("Reset All Settings\u{2026}", role: .destructive) {
                                batteryManager.resetAllSettings()
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 520, height: 560)
        .onChange(of: launchAtLogin) { newValue in
            toggleLoginItem(newValue)
        }
    }

    // MARK: - Settings Helpers

    private func settingsSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
            Spacer()
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func settingsToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }

    private func toggleLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func exportSettings() {
        guard let data = batteryManager.exportSettingsJSON() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "BrewCap_Settings.json"
        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { result in
            if result == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
                _ = batteryManager.importSettingsJSON(data)
            }
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let openSettings = Notification.Name("brewcap.openSettings")
}
