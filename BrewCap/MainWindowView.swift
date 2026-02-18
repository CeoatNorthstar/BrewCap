import SwiftUI
import ServiceManagement

struct MainWindowView: View {
    @ObservedObject var batteryManager: BatteryManager
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login error: \(error)")
            // Revert the toggle on failure
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.brown)
                Text("BrewCap")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
            }
            .padding(.top, 24)

            Divider().padding(.horizontal, 20)

            // Battery Info Card
            VStack(spacing: 12) {
                Text("Battery Status")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    BatteryStatItem(
                        icon: "battery.\(batteryIconLevel)",
                        label: "Charge",
                        value: "\(batteryManager.batteryLevel)%",
                        color: batteryColor
                    )
                    Spacer()
                    BatteryStatItem(
                        icon: statusIcon,
                        label: "Status",
                        value: batteryStatusText,
                        color: statusColor
                    )
                    Spacer()
                    BatteryStatItem(
                        icon: "thermometer.medium",
                        label: "Temp",
                        value: String(format: "%.1f°C", batteryManager.temperature),
                        color: temperatureColor
                    )
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)

            // Charge Limit Slider Card
            VStack(spacing: 12) {
                HStack {
                    Text("Charge Limit")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(batteryManager.chargeLimit))%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
                Slider(value: $batteryManager.chargeLimit, in: 20...100, step: 5)
                    .tint(.accentColor)
                HStack {
                    Text("20%").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("100%").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.top, -8)
            }
            .padding(16)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)

            // Sailing Mode Card
            VStack(spacing: 8) {
                Toggle(isOn: $batteryManager.sailingModeEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "sailboat.fill")
                            .foregroundStyle(batteryManager.sailingModeEnabled ? .blue : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sailing Mode")
                                .font(.headline)
                            Text("Hardware-level charge control via SMC")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)

                // Setup prompt
                if batteryManager.setupNeeded {
                    VStack(spacing: 8) {
                        Text("One-time setup required")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(.orange)
                        Text("BrewCap needs admin access once to install the SMC helper. After this, no passwords will be needed.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Grant Access") {
                            batteryManager.runSetup { success in
                                if !success {
                                    print("Setup failed")
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }

                // Status indicator
                if batteryManager.sailingModeEnabled && !batteryManager.setupNeeded {
                    HStack(spacing: 4) {
                        if batteryManager.chargingInhibited {
                            Image(systemName: "pause.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Charging paused — running on AC power")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if batteryManager.isPluggedIn && batteryManager.batteryLevel >= Int(batteryManager.chargeLimit) {
                            Image(systemName: "bolt.slash.fill")
                                .foregroundStyle(.orange)
                            Text("Applying charge limit...")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Monitoring — will stop charging at limit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)

            // Launch at Login Card
            VStack(spacing: 8) {
                Toggle(isOn: $launchAtLogin) {
                    HStack(spacing: 8) {
                        Image(systemName: "sunrise.fill")
                            .foregroundStyle(launchAtLogin ? .orange : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at Login")
                                .font(.headline)
                            Text("Automatically start BrewCap when you log in")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { newValue in
                    setLaunchAtLogin(newValue)
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "info.circle").font(.caption2)
                Text("v1.0 — Hardware charge control via SMC")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
            .padding(.bottom, 12)
        }
        .frame(width: 380, height: 600)
    }

    // MARK: - Computed

    private var batteryIconLevel: String {
        switch batteryManager.batteryLevel {
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

    private var batteryStatusText: String {
        if batteryManager.chargingInhibited { return "Paused" }
        if batteryManager.isCharging { return "Charging" }
        if batteryManager.isPluggedIn { return "Plugged In" }
        return "On Battery"
    }

    private var statusIcon: String {
        if batteryManager.chargingInhibited { return "pause.circle.fill" }
        if batteryManager.isCharging { return "bolt.fill" }
        if batteryManager.isPluggedIn { return "powerplug.fill" }
        return "powerplug"
    }

    private var statusColor: Color {
        if batteryManager.chargingInhibited { return .orange }
        if batteryManager.isCharging { return .green }
        if batteryManager.isPluggedIn { return .orange }
        return .secondary
    }

    private var temperatureColor: Color {
        if batteryManager.temperature >= 40 { return .red }
        if batteryManager.temperature >= 35 { return .orange }
        return .secondary
    }
}

struct BatteryStatItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 90)
    }
}

#Preview {
    MainWindowView(batteryManager: BatteryManager())
}
