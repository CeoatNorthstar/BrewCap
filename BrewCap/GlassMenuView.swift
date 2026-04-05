//
//  GlassMenuView.swift
//  BrewCap
//
//  Copyright (c) 2026 NorthStars Industries. All rights reserved.
//

import SwiftUI

struct GlassMenuView: View {
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var updateChecker: UpdateChecker
    @StateObject private var licenseManager = LicenseManager.shared
    
    var onOpenMain: () -> Void
    var onExportReport: () -> Void
    var onCopyStats: () -> Void
    var onShowAbout: () -> Void
    var onCheckUpdates: () -> Void
    var onQuit: () -> Void
    var onClose: () -> Void
    var onUpgrade: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Status section
            VStack(spacing: 8) {
                // Battery level
                HStack {
                    Text("Battery")
                        .font(.subheadline)
                        .foregroundStyle(MonochromeColors.secondary)
                    Spacer()
                    Text("\(batteryManager.batteryLevel)%")
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(MonochromeColors.primary)
                }
                
                // Status indicator
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(MonochromeColors.secondary)
                    Spacer()
                }
                
                // Mini progress
                GlassProgressView(value: Double(batteryManager.batteryLevel), total: 100)
                    .frame(height: 4)
            }
            .padding(16)
            .glassCard(cornerRadius: 12, material: .thin)
            
            GlassDivider()
                .padding(.vertical, 8)
            
            // Info section
            VStack(spacing: 6) {
                InfoRow(label: "Health", value: "\(batteryManager.healthPercent)%")
                InfoRow(label: "Temperature", value: String(format: "%.1f°C", batteryManager.temperature))
                InfoRow(label: "Cycles", value: "\(batteryManager.cycleCount)")
                InfoRow(label: "Power", value: String(format: "%.1f W", batteryManager.powerDrawWatts))
                InfoRow(label: "Time", value: batteryManager.timeRemaining)
                
                if batteryManager.isPluggedIn {
                    InfoRow(label: "Adapter", value: "\(batteryManager.adapterName) · \(batteryManager.adapterWatts)W")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            GlassDivider()
                .padding(.vertical, 8)
            
            // Sailing Mode toggle (Pro feature)
            VStack(spacing: 0) {
                Button {
                    if licenseManager.hasAccess(to: .sailingMode) {
                        withAnimation(.spring(response: 0.3)) {
                            batteryManager.sailingModeEnabled.toggle()
                        }
                    } else {
                        onClose()
                        onUpgrade?()
                    }
                } label: {
                    HStack {
                        Image(systemName: "sailboat")
                            .imageScale(.medium)
                        if licenseManager.hasAccess(to: .sailingMode) {
                            Text(batteryManager.sailingModeEnabled ? "Sailing Mode · \(Int(batteryManager.chargeLimit))%" : "Sailing Mode")
                                .font(.subheadline.weight(.medium))
                        } else {
                            Text("Sailing Mode")
                                .font(.subheadline.weight(.medium))
                            Text("PRO")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                        Spacer()
                        if licenseManager.hasAccess(to: .sailingMode) {
                            Image(systemName: batteryManager.sailingModeEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(batteryManager.sailingModeEnabled ? MonochromeColors.accent : .secondary.opacity(0.7))
                        }
                    }
                }
                .buttonStyle(.glass)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                
                Button {
                    batteryManager.showPercentageInMenuBar.toggle()
                } label: {
                    HStack {
                        Image(systemName: "menubar.rectangle")
                            .imageScale(.medium)
                        Text("Show in Menu Bar")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: batteryManager.showPercentageInMenuBar ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(batteryManager.showPercentageInMenuBar ? MonochromeColors.accent : .secondary.opacity(0.7))
                    }
                }
                .buttonStyle(.glass)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .foregroundStyle(.primary)
            
            GlassDivider()
                .padding(.vertical, 8)
            
            // Actions
            VStack(spacing: 0) {
                MenuButton(icon: "app.badge", label: "Open BrewCap") {
                    onClose()
                    onOpenMain()
                }
                
                MenuButton(icon: "doc.text", label: "Export Report") {
                    onClose()
                    onExportReport()
                }
                
                MenuButton(icon: "doc.on.clipboard", label: "Copy Stats") {
                    onClose()
                    onCopyStats()
                }
                
                MenuButton(icon: "info.circle", label: "About BrewCap") {
                    onClose()
                    onShowAbout()
                }
                
                if updateChecker.updateAvailable, let version = updateChecker.latestVersion {
                    MenuButton(icon: "arrow.down.circle", label: "Update Available: v\(version)", accent: true) {
                        onClose()
                        onCheckUpdates()
                    }
                } else {
                    MenuButton(icon: "checkmark.circle", label: "Check for Updates") {
                        onClose()
                        onCheckUpdates()
                    }
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            
            GlassDivider()
                .padding(.vertical, 8)
            
            // Quit button
            Button {
                onQuit()
            } label: {
                HStack {
                    Image(systemName: "power")
                        .imageScale(.medium)
                    Text("Quit BrewCap")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
            }
            .buttonStyle(.glass)
            .foregroundStyle(MonochromeColors.accent)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .padding(12)
        .frame(width: 280)
        .glassWindowBackground()
    }
    
    private var statusText: String {
        if batteryManager.isPluggedIn {
            if batteryManager.chargingInhibited { return "Sailing Mode Active" }
            if batteryManager.isCharging { return "Charging" }
            return "Connected"
        }
        return "On Battery"
    }
    
    private var statusColor: Color {
        if batteryManager.chargingInhibited { return MonochromeColors.accent }
        if batteryManager.isCharging { return MonochromeColors.primary }
        return MonochromeColors.secondary
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(MonochromeColors.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Menu Button

private struct MenuButton: View {
    let icon: String
    let label: String
    var accent: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                Image(systemName: icon)
                    .imageScale(.medium)
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
        }
        .buttonStyle(.glass)
        .foregroundStyle(accent ? MonochromeColors.accent : .primary)
        .padding(.vertical, 2)
    }
}
