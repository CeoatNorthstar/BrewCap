//
//  ReportGenerator.swift
//  BrewCap
//
//  Copyright (c) 2026 NorthStars Industries. All rights reserved.
//

import Foundation

// Feature 21: Export Battery Report
struct ReportGenerator {
    static func generateReport(from manager: BatteryManager) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let now = dateFormatter.string(from: Date())

        var lines: [String] = []
        lines.append("═══════════════════════════════════════")
        lines.append("         BrewCap Battery Report")
        lines.append("═══════════════════════════════════════")
        lines.append("Generated: \(now)")
        lines.append("")

        lines.append("── Battery Overview ──────────────────")
        lines.append("  Charge Level:       \(manager.batteryLevel)%")
        lines.append("  Health:             \(manager.healthPercent)%")
        lines.append("  Condition:          \(manager.batteryCondition)")
        lines.append("  Temperature:        \(String(format: "%.1f°C", manager.temperature))")
        lines.append("  Cycle Count:        \(manager.cycleCount)")
        lines.append("")

        lines.append("── Capacity ─────────────────────────")
        lines.append("  Design Capacity:    \(manager.designCapacity) mAh")
        lines.append("  Current Max:        \(manager.maxCapacity) mAh")
        lines.append("  Capacity Lost:      \(manager.designCapacity - manager.maxCapacity) mAh")
        lines.append("")

        lines.append("── Electrical ───────────────────────")
        lines.append("  Voltage:            \(String(format: "%.2fV", manager.voltage))")
        lines.append("  Amperage:           \(manager.amperage) mA")
        lines.append("  Time Remaining:     \(manager.timeRemaining)")
        lines.append("")

        lines.append("── Power Source ─────────────────────")
        lines.append("  Plugged In:         \(manager.isPluggedIn ? "Yes" : "No")")
        lines.append("  Charging:           \(manager.isCharging ? "Yes" : "No")")
        lines.append("  Adapter:            \(manager.adapterName)")
        lines.append("  Adapter Wattage:    \(manager.adapterWatts)W")
        lines.append("")

        lines.append("── Device Info ──────────────────────")
        lines.append("  Serial Number:      \(manager.serialNumber)")
        lines.append("  Manufacture Date:   \(manager.manufactureDate)")
        lines.append("")

        lines.append("── BrewCap Settings ─────────────────")
        lines.append("  Charge Limit:       \(Int(manager.chargeLimit))%")
        lines.append("  Sailing Mode:       \(manager.sailingModeEnabled ? "On" : "Off")")
        lines.append("  Charging Inhibited: \(manager.chargingInhibited ? "Yes" : "No")")
        lines.append("  Temp Alert:         \(Int(manager.tempAlertThreshold))°C")
        lines.append("  Low Battery Alert:  \(manager.lowBatteryThreshold)%")
        lines.append("  Monitor Interval:   \(Int(manager.monitoringInterval))s")
        lines.append("")

        if !manager.chargeHistory.isEmpty {
            lines.append("── Charge History (Last \(manager.chargeHistory.count)) ──")
            for session in manager.chargeHistory.prefix(10) {
                let delta = session.delta >= 0 ? "+\(session.delta)" : "\(session.delta)"
                lines.append("  \(session.formattedDate)  │  \(session.startLevel)% → \(session.endLevel)% (\(delta)%)  │  \(session.formattedDuration)  │  \(session.adapterWatts)W")
            }
            lines.append("")
        }

        lines.append("═══════════════════════════════════════")
        lines.append("  Report by BrewCap v1.0")
        lines.append("═══════════════════════════════════════")

        return lines.joined(separator: "\n")
    }

    static func saveToDesktop(from manager: BatteryManager) -> URL? {
        let report = generateReport(from: manager)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "BrewCap_Report_\(dateFormatter.string(from: Date())).txt"

        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let url = desktop.appendingPathComponent(filename)

        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Failed to save report: \(error)")
            return nil
        }
    }
}
