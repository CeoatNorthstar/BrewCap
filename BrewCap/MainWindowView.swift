//
//  MainWindowView.swift
//  BrewCap
//
//  Copyright (c) 2026 NorthStars Industries. All rights reserved.
//

import SwiftUI
import ServiceManagement

struct MainWindowView: View {
    @ObservedObject var batteryManager: BatteryManager
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var selectedTab = 0
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingSeen")
    @State private var showShareSheet = false
    @State private var showImportPicker = false
    @State private var flashCopied = false

    private func toggleLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.top, 20)
                .padding(.bottom, 12)

            // Tab Picker
            Picker("", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Details").tag(1)
                Text("History").tag(2)
                Text("Settings").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Tab Content with Feature 55: transitions
            ScrollView {
                Group {
                    switch selectedTab {
                    case 0: overviewTab
                    case 1: detailsTab
                    case 2: historyTab
                    case 3: settingsTab
                    default: overviewTab
                    }
                }
                .transition(batteryManager.reduceMotion ? .identity : .opacity.combined(with: .move(edge: .trailing)))
                .animation(batteryManager.reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            // Footer
            footerView
        }
        .frame(width: 420, height: 740)
        .sheet(isPresented: $showOnboarding) { onboardingSheet }
        // Feature 60: Keyboard shortcuts
        .background(
            Group {
                Button("") { selectedTab = 0 }.keyboardShortcut("1", modifiers: .command)
                Button("") { selectedTab = 1 }.keyboardShortcut("2", modifiers: .command)
                Button("") { selectedTab = 2 }.keyboardShortcut("3", modifiers: .command)
                Button("") { selectedTab = 3 }.keyboardShortcut("4", modifiers: .command)
                Button("") { batteryManager.copyStatsToClipboard(); withAnimation { flashCopied = true }; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { flashCopied = false } }.keyboardShortcut("c", modifiers: [.command, .shift])
                Button("") { exportCSV() }.keyboardShortcut("e", modifiers: .command)
            }.frame(width: 0, height: 0).opacity(0)
        )
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.brown)
            Text("BrewCap")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Spacer()
            if flashCopied {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            batteryRingView
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine) // Feature 58
        .accessibilityLabel("BrewCap, battery at \(batteryManager.batteryLevel) percent")
    }

    private var batteryRingView: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(batteryManager.batteryLevel) / 100)
                .stroke(batteryRingColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(batteryManager.reduceMotion ? nil : .easeInOut(duration: 0.6), value: batteryManager.batteryLevel)
            VStack(spacing: 0) {
                Text("\(batteryManager.batteryLevel)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("%")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityLabel("Battery level \(batteryManager.batteryLevel) percent") // Feature 58
    }

    private var batteryRingColor: Color {
        if batteryManager.chargingInhibited { return .orange }
        if batteryManager.batteryLevel <= 20 { return .red }
        if batteryManager.batteryLevel <= 50 { return .orange }
        return .green
    }

    // MARK: - Tab 0: Overview

    private var overviewTab: some View {
        VStack(spacing: 14) {
            // Battery Stats Row
            HStack(spacing: 0) {
                StatItem(icon: "battery.\(batteryIconLevel)", label: "Charge", value: "\(batteryManager.batteryLevel)%", color: batteryColor)
                Divider().frame(height: 30)
                StatItem(icon: "bolt.fill", label: "Status", value: batteryManager.isPluggedIn ? (batteryManager.chargingInhibited ? "Paused" : "Charging") : "Battery", color: batteryManager.isPluggedIn ? .green : .secondary)
                Divider().frame(height: 30)
                StatItem(icon: "heart.fill", label: "Health", value: "\(batteryManager.healthPercent)%", color: healthColor)
            }
            .cardStyle()

            // Charge Limit + Feature 38: Presets
            VStack(spacing: 10) {
                HStack {
                    Label("Charge Limit", systemImage: "gauge.with.needle")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(batteryManager.chargeLimit))%")
                        .font(.system(.headline, design: .rounded))
                        .monospacedDigit()
                }
                Slider(value: $batteryManager.chargeLimit, in: 20...100, step: 5)
                    .tint(batteryManager.chargeLimit > 80 ? .orange : .blue)
                    .accessibilityLabel("Charge limit slider") // Feature 58
                    .onChange(of: batteryManager.chargeLimit) { _ in haptic() }

                // Feature 38: Quick presets
                HStack(spacing: 8) {
                    ForEach([60, 80, 100], id: \.self) { preset in
                        Button("\(preset)%") {
                            batteryManager.setChargePreset(preset)
                            haptic()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(Int(batteryManager.chargeLimit) == preset ? .blue : .secondary)
                        .accessibilityLabel("Set charge limit to \(preset) percent") // Feature 58
                    }
                    Spacer()
                }

                // Sailing Mode Toggle
                Toggle(isOn: $batteryManager.sailingModeEnabled) {
                    Label("Sailing Mode", systemImage: "sailboat.fill")
                        .font(.subheadline.weight(.medium))
                }
                .tint(.blue)
                .onChange(of: batteryManager.sailingModeEnabled) { _ in haptic() }
            }
            .cardStyle()

            // Feature 37: Travel Mode
            VStack(spacing: 10) {
                Toggle(isOn: $batteryManager.travelModeEnabled) {
                    HStack {
                        Label("Travel Mode", systemImage: "airplane")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if batteryManager.travelModeEnabled, let expiry = batteryManager.travelModeExpiry {
                            Text(expiry, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.purple)
                .onChange(of: batteryManager.travelModeEnabled) { _ in haptic() }
                .accessibilityLabel("Travel mode, temporarily charge to 100 percent")

                if !batteryManager.travelModeEnabled {
                    HStack {
                        Text("Duration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $batteryManager.travelModeDuration, in: 1...24, step: 1)
                        Text("\(Int(batteryManager.travelModeDuration))h")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .cardStyle()

            // Info Pills
            HStack(spacing: 8) {
                InfoPill(icon: "thermometer.medium", text: String(format: "%.1f°C", batteryManager.temperature))
                InfoPill(icon: "waveform.path.ecg", text: batteryManager.usageIntensity)
                    .accessibilityLabel("Usage intensity: \(batteryManager.usageIntensity)") // Feature 58
                InfoPill(icon: "bolt.circle", text: String(format: "%.1fW", batteryManager.powerDrawWatts))
                if batteryManager.isPluggedIn {
                    InfoPill(icon: "hare.fill", text: batteryManager.chargeSpeed)
                        .accessibilityLabel("Charge speed: \(batteryManager.chargeSpeed)") // Feature 58
                }
                InfoPill(icon: "repeat", text: "\(batteryManager.cycleCount) cycles")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Tab 1: Details

    private var detailsTab: some View {
        VStack(spacing: 14) {
            // Capacity Card
            VStack(spacing: 10) {
                Label("Battery Capacity", systemImage: "battery.100.bolt")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                DetailRow(label: "Design Capacity", value: "\(batteryManager.designCapacity) mAh")
                DetailRow(label: "Current Max", value: "\(batteryManager.maxCapacity) mAh", color: healthColor)
                DetailRow(label: "Health", value: "\(batteryManager.healthPercent)%", color: healthColor)
                DetailRow(label: "Cycle Count", value: "\(batteryManager.cycleCount)")
                DetailRow(label: "Condition", value: batteryManager.batteryCondition, color: conditionColor)
                // Feature 36
                DetailRow(label: "Battery Age", value: String(format: "~%.1f years", batteryManager.batteryAgeYears))
                // Feature 42
                if batteryManager.estimatedReplacementDate != "—" {
                    DetailRow(label: "Est. Replacement", value: batteryManager.estimatedReplacementDate, color: .orange)
                }
            }
            .cardStyle()

            // Electrical Card
            VStack(spacing: 10) {
                Label("Power & Electrical", systemImage: "bolt.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Feature 31
                DetailRow(label: "Power Draw", value: String(format: "%.1f W", batteryManager.powerDrawWatts))
                DetailRow(label: "Amperage", value: "\(batteryManager.amperage) mA")
                DetailRow(label: "Voltage", value: String(format: "%.2f V", batteryManager.voltage))
                DetailRow(label: "Temperature", value: String(format: "%.1f°C", batteryManager.temperature))
                // Feature 34
                DetailRow(label: "Intensity", value: batteryManager.usageIntensity)
                // Feature 35
                if batteryManager.averageDrainPerHour > 0 {
                    DetailRow(label: "Avg Drain/Hour", value: "\(batteryManager.averageDrainPerHour)%/hr")
                }
                // Feature 32
                if batteryManager.isPluggedIn {
                    DetailRow(label: "Time to Full", value: batteryManager.estimatedTimeToFull, color: .green)
                } else {
                    DetailRow(label: "Time Remaining", value: batteryManager.timeRemaining)
                }
            }
            .cardStyle()

            // Adapter Card
            VStack(spacing: 10) {
                Label("Power Adapter", systemImage: "powerplug.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                DetailRow(label: "Connected", value: batteryManager.isPluggedIn ? "Yes" : "No", color: batteryManager.isPluggedIn ? .green : .secondary)
                DetailRow(label: "Adapter", value: batteryManager.adapterName)
                DetailRow(label: "Wattage", value: "\(batteryManager.adapterWatts)W")
                // Feature 39
                DetailRow(label: "Charge Speed", value: batteryManager.chargeSpeed)
            }
            .cardStyle()

            // Device Info Card
            VStack(spacing: 10) {
                Label("Device Info", systemImage: "laptopcomputer")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                DetailRow(label: "Serial Number", value: batteryManager.serialNumber)
                DetailRow(label: "Manufacture Date", value: batteryManager.manufactureDate)
            }
            .cardStyle()

            // Session Card
            if batteryManager.isPluggedIn, let _ = batteryManager.sessionStartTime {
                VStack(spacing: 10) {
                    Label("Current Session", systemImage: "timer")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    DetailRow(label: "Duration", value: batteryManager.sessionDuration)
                    let delta = batteryManager.sessionDelta
                    DetailRow(label: "Charged", value: delta >= 0 ? "+\(delta)%" : "\(delta)%", color: .green)
                }
                .cardStyle()
            }

            // Feature 50: Copy button
            Button {
                batteryManager.copyStatsToClipboard()
                withAnimation { flashCopied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { flashCopied = false }
                haptic()
            } label: {
                Label("Copy Stats to Clipboard", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityLabel("Copy battery statistics to clipboard") // Feature 58
        }
    }

    // MARK: - Tab 2: History

    private var historyTab: some View {
        VStack(spacing: 14) {
            // Feature 33: Capacity Fade
            if !batteryManager.capacitySnapshots.isEmpty {
                VStack(spacing: 10) {
                    HStack {
                        Label("Capacity Trend", systemImage: "chart.line.downtrend.xyaxis")
                            .font(.headline)
                        Spacer()
                        Text("\(batteryManager.capacitySnapshots.count) snapshots")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    capacityChart
                }
                .cardStyle()
            }

            // Feature 52: Event Log
            if !batteryManager.eventLog.isEmpty {
                VStack(spacing: 10) {
                    HStack {
                        Label("Event Log", systemImage: "list.bullet.clipboard")
                            .font(.headline)
                        Spacer()
                        Text("\(batteryManager.eventLog.count) events")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    ForEach(batteryManager.eventLog.prefix(15)) { event in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.message)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text("\(event.formattedDate) · \(event.formattedTime)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                    }
                }
                .cardStyle()
            }

            // Charge History
            if batteryManager.chargeHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No charge sessions yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Plug in your charger to start tracking")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(batteryManager.chargeHistory) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.formattedDate)
                                .font(.caption.weight(.medium))
                            Text("\(session.formattedDuration) · \(session.adapterWatts)W")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(session.startLevel)% → \(session.endLevel)%")
                            .font(.caption.monospacedDigit())
                        Text(session.delta >= 0 ? "+\(session.delta)%" : "\(session.delta)%")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(session.delta >= 0 ? .green : .red)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine) // Feature 58
                    .accessibilityLabel("Charge session on \(session.formattedDate), \(session.startLevel) to \(session.endLevel) percent")
                }
                .cardStyle()
            }

            // Export buttons
            HStack(spacing: 8) {
                // Feature 49: CSV
                Button {
                    exportCSV()
                    haptic()
                } label: {
                    Label("CSV", systemImage: "tablecells")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Export charge history as CSV") // Feature 58

                // Feature 21: Report
                Button {
                    if let url = ReportGenerator.saveToDesktop(from: batteryManager) {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                    }
                    haptic()
                } label: {
                    Label("Report", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Feature 51: Share
                Button {
                    shareReport()
                    haptic()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Share battery report") // Feature 58
            }
        }
    }

    // Feature 33: Capacity Chart
    private var capacityChart: some View {
        let snapshots = batteryManager.capacitySnapshots.suffix(30)
        let maxDesign = snapshots.first?.designCapacity ?? 1
        let maxVal = CGFloat(maxDesign)

        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = snapshots.count
            guard count > 1 else {
                return AnyView(Text("Not enough data").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity))
            }
            let stepX = w / CGFloat(count - 1)

            return AnyView(
                ZStack(alignment: .topLeading) {
                    // 80% threshold line
                    let threshold80 = h * (1 - (0.80))
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: threshold80))
                        path.addLine(to: CGPoint(x: w, y: threshold80))
                    }
                    .stroke(Color.orange.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))

                    // Line chart
                    Path { path in
                        for (i, snap) in snapshots.enumerated() {
                            let x = CGFloat(i) * stepX
                            let healthFraction = CGFloat(snap.maxCapacity) / maxVal
                            let y = h * (1 - healthFraction)
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.blue, lineWidth: 2)

                    // Labels
                    Text("100%")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .position(x: 18, y: 4)
                    Text("80%")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange.opacity(0.5))
                        .position(x: 14, y: threshold80 - 6)
                }
            )
        }
        .frame(height: 80)
        .accessibilityLabel("Capacity trend chart showing \(snapshots.count) data points") // Feature 58
    }

    // MARK: - Tab 3: Settings

    private var settingsTab: some View {
        VStack(spacing: 14) {
            // Alert Settings
            VStack(spacing: 10) {
                Label("Alerts", systemImage: "bell.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("Temp Alert")
                        .font(.subheadline)
                    Slider(value: $batteryManager.tempAlertThreshold, in: 30...50, step: 1)
                        .onChange(of: batteryManager.tempAlertThreshold) { _ in haptic() }
                    Text("\(Int(batteryManager.tempAlertThreshold))°C")
                        .font(.caption.monospacedDigit())
                        .frame(width: 35)
                }
                .accessibilityLabel("Temperature alert threshold: \(Int(batteryManager.tempAlertThreshold)) degrees") // Feature 58

                HStack {
                    Text("Low Battery")
                        .font(.subheadline)
                    Slider(value: Binding(get: { Double(batteryManager.lowBatteryThreshold) },
                                          set: { batteryManager.lowBatteryThreshold = Int($0) }),
                           in: 5...40, step: 5)
                        .onChange(of: batteryManager.lowBatteryThreshold) { _ in haptic() }
                    Text("\(batteryManager.lowBatteryThreshold)%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 35)
                }

                Toggle("Full Charge Notification", isOn: $batteryManager.fullChargeNotification)
                    .font(.subheadline)
                    .onChange(of: batteryManager.fullChargeNotification) { _ in haptic() }
            }
            .cardStyle()

            // Sound & Notification
            VStack(spacing: 10) {
                Label("Sounds & Notifications", systemImage: "speaker.wave.2.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("Sound Effects", isOn: $batteryManager.soundEffectsEnabled)
                    .font(.subheadline)
                    .onChange(of: batteryManager.soundEffectsEnabled) { _ in haptic() }

                Toggle("Do Not Disturb", isOn: $batteryManager.doNotDisturb)
                    .font(.subheadline)
                    .onChange(of: batteryManager.doNotDisturb) { _ in haptic() }

                // Feature 41
                Toggle("Charge Complete Chime", isOn: $batteryManager.chargeChimeEnabled)
                    .font(.subheadline)
                    .onChange(of: batteryManager.chargeChimeEnabled) { _ in haptic() }
            }
            .cardStyle()

            // Smart Features
            VStack(spacing: 10) {
                Label("Smart Features", systemImage: "brain")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Feature 40
                Toggle("Auto-pause Below 20%", isOn: $batteryManager.autoPauseLowBattery)
                    .font(.subheadline)
                    .onChange(of: batteryManager.autoPauseLowBattery) { _ in haptic() }

                // Feature 43
                HStack {
                    Text("Menu Bar Display")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: $batteryManager.menuBarDisplayMode) {
                        Text("%").tag(0)
                        Text("Time").tag(1)
                        Text("Watts").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .onChange(of: batteryManager.menuBarDisplayMode) { _ in haptic() }
                }
                .accessibilityLabel("Menu bar display mode") // Feature 58

                Toggle("Show in Menu Bar", isOn: $batteryManager.showPercentageInMenuBar)
                    .font(.subheadline)
                    .onChange(of: batteryManager.showPercentageInMenuBar) { _ in haptic() }

                HStack {
                    Text("Monitor Interval")
                        .font(.subheadline)
                    Slider(value: $batteryManager.monitoringInterval, in: 5...60, step: 5)
                        .onChange(of: batteryManager.monitoringInterval) { _ in haptic() }
                    Text("\(Int(batteryManager.monitoringInterval))s")
                        .font(.caption.monospacedDigit())
                        .frame(width: 30)
                }
            }
            .cardStyle()

            // Accessibility & Polish
            VStack(spacing: 10) {
                Label("Accessibility", systemImage: "accessibility")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Feature 57
                Toggle("Reduce Motion", isOn: $batteryManager.reduceMotion)
                    .font(.subheadline)
                    .onChange(of: batteryManager.reduceMotion) { _ in haptic() }

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .font(.subheadline)
                    .onChange(of: launchAtLogin) { newValue in
                        toggleLoginItem(newValue)
                        haptic()
                    }
            }
            .cardStyle()

            // Feature 53: Settings Import/Export
            VStack(spacing: 10) {
                Label("Data Management", systemImage: "externaldrive.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button {
                        exportSettings()
                        haptic()
                    } label: {
                        Label("Export Settings", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        importSettings()
                        haptic()
                    } label: {
                        Label("Import Settings", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .cardStyle()

            // Reset
            Button(role: .destructive) {
                batteryManager.resetAllSettings()
                haptic()
            } label: {
                Label("Reset All Settings", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityLabel("Reset all settings to defaults") // Feature 58
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(batteryManager.isPluggedIn ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
                .animation(batteryManager.reduceMotion ? nil : .easeInOut, value: batteryManager.isPluggedIn)
            Text(batteryManager.isPluggedIn ? "Connected" : "On Battery")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            // Feature 60: Shortcuts hint
            Text("⌘1-4 tabs · ⇧⌘C copy")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Onboarding

    private var onboardingSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 52))
                .foregroundStyle(.brown)

            Text("Welcome to BrewCap")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 10) {
                OnboardingRow(icon: "sailboat.fill", color: .blue, title: "Sailing Mode", desc: "Automatically pause charging at your set limit")
                OnboardingRow(icon: "heart.fill", color: .pink, title: "Battery Health", desc: "Track capacity, cycles, and degradation over time")
                OnboardingRow(icon: "bolt.circle.fill", color: .orange, title: "Power Analytics", desc: "Real-time power draw, drain rate, and usage intensity")
                OnboardingRow(icon: "airplane", color: .purple, title: "Travel Mode", desc: "Temporarily charge to 100% before trips")
                OnboardingRow(icon: "chart.line.downtrend.xyaxis", color: .green, title: "Capacity Tracking", desc: "Daily snapshots and estimated replacement date")
            }
            .padding(.horizontal, 10)

            Button("Get Started") {
                UserDefaults.standard.set(true, forKey: "onboardingSeen")
                showOnboarding = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.brown)
        }
        .padding(30)
        .frame(width: 380)
    }

    // MARK: - Feature 56: Haptic Feedback

    private func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    // MARK: - Feature 49: CSV Export

    private func exportCSV() {
        let csv = batteryManager.exportChargeHistoryCSV()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "BrewCap_History.csv"
        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? csv.write(to: url, atomically: true, encoding: .utf8)
                batteryManager.logEvent("Charge history exported as CSV")
            }
        }
    }

    // MARK: - Feature 51: Share

    private func shareReport() {
        guard let url = ReportGenerator.saveToDesktop(from: batteryManager) else { return }
        let picker = NSSharingServicePicker(items: [url])
        if let view = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }

    // MARK: - Feature 53: Settings Export/Import

    private func exportSettings() {
        guard let data = batteryManager.exportSettingsJSON() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "BrewCap_Settings.json"
        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? data.write(to: url)
                batteryManager.logEvent("Settings exported as JSON")
            }
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { result in
            if result == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
                let _ = batteryManager.importSettingsJSON(data)
            }
        }
    }

    // MARK: - Helpers

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

    private var batteryColor: Color {
        if batteryManager.batteryLevel <= 20 { return .red }
        if batteryManager.batteryLevel <= 50 { return .orange }
        return .green
    }

    private var healthColor: Color {
        if batteryManager.healthPercent >= 80 { return .green }
        if batteryManager.healthPercent >= 60 { return .orange }
        return .red
    }

    private var conditionColor: Color {
        switch batteryManager.batteryCondition {
        case "Normal": return .green
        case "Fair": return .orange
        default: return .red
        }
    }
}

// MARK: - Reusable Components

struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine) // Feature 58
        .accessibilityLabel("\(label): \(value)")
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine) // Feature 58
        .accessibilityLabel("\(label): \(value)")
    }
}

struct InfoPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5))
        .clipShape(Capsule())
    }
}

struct OnboardingRow: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Card Style (Feature 59: auto light/dark)

struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06), lineWidth: 0.5)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
