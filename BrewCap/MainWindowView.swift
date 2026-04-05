//
//  MainWindowView.swift
//  BrewCap
//
//  Copyright (c) 2026 NorthStars Industries. All rights reserved.
//

import SwiftUI
import ServiceManagement
import CoreImage.CIFilterBuiltins

// MARK: - Notification Extension

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let navigateToUpgrade = Notification.Name("navigateToUpgrade")
}

// MARK: - Sidebar Navigation

enum SidebarItem: String, CaseIterable, Identifiable {
    case battery = "Battery"
    case health = "Health"
    case power = "Power"
    case settings = "Settings"
    case upgrade = "Upgrade"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .battery: return "battery.100percent"
        case .health: return "heart.fill"
        case .power: return "bolt.fill"
        case .settings: return "gearshape.fill"
        case .upgrade: return "sparkles"
        }
    }
    
    @MainActor
    static var visibleCases: [SidebarItem] {
        // Show upgrade only for free users
        if LicenseManager.shared.currentTier == .free {
            return allCases
        } else {
            return allCases.filter { $0 != .upgrade }
        }
    }
}

// MARK: - Main Window

struct MainWindowView: View {
    @ObservedObject var batteryManager: BatteryManager
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var selectedItem: SidebarItem? = .battery
    @State private var showSetupAlert = false
    @State private var flashCopied = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            List(sidebarItems, selection: $selectedItem) { item in
                NavigationLink(value: item) {
                    HStack {
                        Label(item.rawValue, systemImage: item.icon)
                        if item == .upgrade {
                            Spacer()
                            Text("PRO")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
            .listStyle(.sidebar)
        } detail: {
            // Detail view based on selection
            Group {
                switch selectedItem {
                case .battery:
                    BatteryDetailView(batteryManager: batteryManager, showCopied: showCopied, onUpgrade: { selectedItem = .upgrade })
                case .health:
                    HealthDetailView(batteryManager: batteryManager)
                case .power:
                    PowerDetailView(batteryManager: batteryManager)
                case .settings:
                    SettingsDetailView(batteryManager: batteryManager)
                case .upgrade:
                    UpgradeDetailView(onComplete: { selectedItem = .battery })
                case .none:
                    BatteryDetailView(batteryManager: batteryManager, showCopied: showCopied, onUpgrade: { selectedItem = .upgrade })
                }
            }
            .frame(minWidth: 450)
        }
        .frame(minWidth: 650, minHeight: 450)
        .onReceive(batteryManager.$setupNeeded) { needed in
            if needed { showSetupAlert = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToUpgrade)) { _ in
            selectedItem = .upgrade
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
                Text("Copied!")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.green.gradient, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 12)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: flashCopied)
    }
    
    private var sidebarItems: [SidebarItem] {
        if licenseManager.currentTier == .free {
            return SidebarItem.allCases
        } else {
            return SidebarItem.allCases.filter { $0 != .upgrade }
        }
    }

    private func showCopied() {
        withAnimation { flashCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { flashCopied = false }
        }
    }
    
    func navigateToUpgrade() {
        selectedItem = .upgrade
    }
}

// MARK: - Upgrade Detail View (Minimal Store)

struct UpgradeDetailView: View {
    var onComplete: () -> Void
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var selectedPlan: Plan? = nil
    @State private var licenseKey = ""
    @State private var isActivating = false
    @State private var showCheckout = false
    @State private var errorMessage: String?
    
    enum Plan: String, CaseIterable, Identifiable {
        case monthly = "Monthly"
        case quarterly = "Quarterly"
        case biannual = "6 Months"
        case yearly = "Yearly"
        
        var id: String { rawValue }
        
        var price: Int {
            switch self {
            case .monthly: return 8
            case .quarterly: return 26
            case .biannual: return 49
            case .yearly: return 100
            }
        }
        
        var perMonth: String {
            switch self {
            case .monthly: return "$8/mo"
            case .quarterly: return "$8.67/mo"
            case .biannual: return "$8.17/mo"
            case .yearly: return "$8.33/mo"
            }
        }
        
        var badge: String? {
            switch self {
            case .yearly: return "Best Value"
            case .biannual: return "Popular"
            default: return nil
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Text("Upgrade to Pro")
                        .font(.largeTitle.weight(.semibold))
                    Text("Unlock all features")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)
                
                // Plan cards - Store shelf style
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        ForEach(Plan.allCases) { plan in
                            PlanCardMinimal(
                                plan: plan,
                                isSelected: selectedPlan == plan
                            ) {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedPlan = plan
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                
                // Continue button
                if selectedPlan != nil {
                    Button {
                        showCheckout = true
                    } label: {
                        Text("Continue")
                            .font(.body.weight(.medium))
                            .frame(width: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                
                // Divider
                HStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                }
                .padding(.horizontal, 60)
                
                // License key input
                VStack(spacing: 12) {
                    Text("Already have a license?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        TextField("License key", text: $licenseKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: 300)
                        
                        Button {
                            activateLicense()
                        } label: {
                            if isActivating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("Activate")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(licenseKey.isEmpty || isActivating)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                // Features list
                VStack(alignment: .leading, spacing: 12) {
                    Text("What's included")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    FeatureItem(text: "Sailing Mode – limit charge to extend battery life")
                    FeatureItem(text: "Advanced health analytics and trends")
                    FeatureItem(text: "Battery reports and export")
                    FeatureItem(text: "Smart notifications for all events")
                    FeatureItem(text: "Priority support")
                }
                .frame(maxWidth: 400, alignment: .leading)
                .padding(.top, 8)
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Upgrade")
        .sheet(isPresented: $showCheckout) {
            if let plan = selectedPlan {
                CheckoutView(plan: plan) {
                    showCheckout = false
                    onComplete()
                }
            }
        }
    }
    
    private func activateLicense() {
        isActivating = true
        errorMessage = nil
        
        Task {
            do {
                try await licenseManager.activateLicense(key: licenseKey)
                onComplete()
            } catch {
                errorMessage = error.localizedDescription
            }
            isActivating = false
        }
    }
}

// MARK: - Minimal Plan Card

struct PlanCardMinimal: View {
    let plan: UpgradeDetailView.Plan
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Badge
                if let badge = plan.badge {
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                        .font(.caption2)
                }
                
                // Price
                Text("$\(plan.price)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                
                // Period
                Text(plan.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Per month
                Text(plan.perMonth)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feature Item

struct FeatureItem: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Checkout View (In-app)

struct CheckoutView: View {
    let plan: UpgradeDetailView.Plan
    var onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var isLoading = true
    
    private var checkoutURL: String {
        "https://axionceo.gumroad.com/l/BREWCAP_PRO"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Complete purchase")
                        .font(.headline)
                    Text("\(plan.rawValue) · $\(plan.price)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            
            Divider()
            
            // Gumroad WebView
            ZStack {
                GumroadCheckoutView(productURL: checkoutURL) { licenseKey in
                    Task {
                        try? await licenseManager.activateLicense(key: licenseKey)
                        dismiss()
                        onComplete()
                    }
                }
                
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isLoading = false
                }
            }
        }
        .frame(width: 480, height: 600)
    }
}

// MARK: - Battery Detail View

struct BatteryDetailView: View {
    @ObservedObject var batteryManager: BatteryManager
    var showCopied: () -> Void
    var onUpgrade: (() -> Void)? = nil
    @State private var showShareStats = false
    @State private var showShareApp = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Battery status card
                GroupBox {
                    VStack(spacing: 20) {
                        // Battery indicator
                        HStack(spacing: 24) {
                            // Battery ring
                            ZStack {
                                Circle()
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 10)
                                    .frame(width: 100, height: 100)
                                
                                Circle()
                                    .trim(from: 0, to: CGFloat(batteryManager.batteryLevel) / 100)
                                    .stroke(batteryColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                    .frame(width: 100, height: 100)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.spring(response: 0.6), value: batteryManager.batteryLevel)
                                
                                VStack(spacing: 2) {
                                    Text("\(batteryManager.batteryLevel)")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                    Text("%")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(statusText)
                                    .font(.title2.weight(.semibold))
                                
                                if batteryManager.isPluggedIn {
                                    Label(batteryManager.isCharging ? "Charging" : "Connected", systemImage: "bolt.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.green)
                                } else {
                                    Label("On Battery", systemImage: "battery.100percent")
                                        .font(.subheadline)
                                        .foregroundStyle(.orange)
                                }
                                
                                Text(batteryManager.timeRemaining)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        
                        Divider()
                        
                        // Sailing Mode toggle (Pro feature)
                        SailingModeSection(batteryManager: batteryManager, onUpgrade: onUpgrade)
                    }
                    .padding(8)
                } label: {
                    Label("Battery Status", systemImage: "battery.100percent")
                }
                
                // Quick actions
                GroupBox {
                    HStack(spacing: 16) {
                        Button {
                            batteryManager.copyStatsToClipboard()
                            showCopied()
                        } label: {
                            Label("Copy Stats", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            showShareStats = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            showShareApp = true
                        } label: {
                            Label("QR Code", systemImage: "qrcode")
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                    }
                    .padding(8)
                } label: {
                    Label("Quick Actions", systemImage: "bolt.circle")
                }
            }
            .padding(20)
        }
        .navigationTitle("Battery")
        .sheet(isPresented: $showShareStats) {
            ShareStatsSheet(batteryManager: batteryManager)
        }
        .sheet(isPresented: $showShareApp) {
            ShareAppSheet()
        }
    }
    
    private var batteryColor: Color {
        if batteryManager.batteryLevel <= 20 { return .red }
        if batteryManager.batteryLevel <= 40 { return .orange }
        return .green
    }
    
    private var statusText: String {
        if batteryManager.chargingInhibited {
            return "Paused at \(Int(batteryManager.chargeLimit))%"
        }
        if batteryManager.isCharging {
            return "Charging"
        }
        if batteryManager.isPluggedIn {
            return "Fully Charged"
        }
        return "Discharging"
    }
}

// MARK: - Health Detail View

struct HealthDetailView: View {
    @ObservedObject var batteryManager: BatteryManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Health overview
                GroupBox {
                    VStack(spacing: 20) {
                        HStack {
                            // Health gauge
                            ZStack {
                                Circle()
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 10)
                                    .frame(width: 100, height: 100)
                                
                                Circle()
                                    .trim(from: 0, to: CGFloat(batteryManager.healthPercent) / 100)
                                    .stroke(healthColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                    .frame(width: 100, height: 100)
                                    .rotationEffect(.degrees(-90))
                                
                                VStack(spacing: 2) {
                                    Text("\(batteryManager.healthPercent)")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                    Text("%")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Battery Health")
                                    .font(.title2.weight(.semibold))
                                
                                Text(batteryManager.batteryCondition)
                                    .font(.headline)
                                    .foregroundStyle(healthColor)
                                
                                Text("\(batteryManager.cycleCount) charge cycles")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(8)
                } label: {
                    Label("Health Overview", systemImage: "heart.fill")
                }
                
                // Capacity details
                GroupBox {
                    VStack(spacing: 12) {
                        DetailRow(label: "Maximum Capacity", value: "\(batteryManager.maxCapacity) mAh")
                        Divider()
                        DetailRow(label: "Design Capacity", value: "\(batteryManager.designCapacity) mAh")
                        Divider()
                        DetailRow(label: "Capacity Loss", value: "\(batteryManager.designCapacity - batteryManager.maxCapacity) mAh", color: .orange)
                        Divider()
                        DetailRow(label: "Charge Cycles", value: "\(batteryManager.cycleCount)")
                    }
                    .padding(8)
                } label: {
                    Label("Capacity Details", systemImage: "chart.bar.fill")
                }
                
                // Health tips
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HealthTip(icon: "thermometer.medium", title: "Avoid Extreme Temperatures", description: "Keep your Mac between 10°C and 35°C for optimal battery health.")
                        Divider()
                        HealthTip(icon: "battery.75percent", title: "Use Sailing Mode", description: "Limiting charge to 80% can significantly extend battery lifespan.")
                        Divider()
                        HealthTip(icon: "bolt.slash", title: "Avoid Full Discharges", description: "Try not to let your battery drop below 20% regularly.")
                    }
                    .padding(8)
                } label: {
                    Label("Battery Tips", systemImage: "lightbulb.fill")
                }
            }
            .padding(20)
        }
        .navigationTitle("Health")
    }
    
    private var healthColor: Color {
        if batteryManager.healthPercent >= 80 { return .green }
        if batteryManager.healthPercent >= 60 { return .yellow }
        return .red
    }
}

// MARK: - Power Detail View

struct PowerDetailView: View {
    @ObservedObject var batteryManager: BatteryManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Power status
                GroupBox {
                    VStack(spacing: 12) {
                        DetailRow(label: "Power Draw", value: String(format: "%.1f W", batteryManager.powerDrawWatts))
                        Divider()
                        DetailRow(label: "Temperature", value: String(format: "%.1f°C", batteryManager.temperature), color: tempColor)
                        Divider()
                        DetailRow(label: "Time Remaining", value: batteryManager.timeRemaining)
                    }
                    .padding(8)
                } label: {
                    Label("Power Status", systemImage: "bolt.fill")
                }
                
                // Adapter info
                if batteryManager.isPluggedIn {
                    GroupBox {
                        VStack(spacing: 12) {
                            DetailRow(label: "Adapter", value: batteryManager.adapterName)
                            Divider()
                            DetailRow(label: "Wattage", value: "\(batteryManager.adapterWatts)W")
                            if batteryManager.isCharging {
                                Divider()
                                DetailRow(label: "Charge Speed", value: batteryManager.chargeSpeed)
                            }
                        }
                        .padding(8)
                    } label: {
                        Label("Power Adapter", systemImage: "powerplug.fill")
                    }
                }
                
                // Battery usage
                if !batteryManager.isPluggedIn && batteryManager.averageDrainPerHour > 0 {
                    GroupBox {
                        VStack(spacing: 12) {
                            DetailRow(label: "Average Drain", value: "\(batteryManager.averageDrainPerHour)%/hr")
                            Divider()
                            DetailRow(label: "Estimated Runtime", value: batteryManager.timeRemaining)
                        }
                        .padding(8)
                    } label: {
                        Label("Battery Usage", systemImage: "chart.line.downtrend.xyaxis")
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Power")
    }
    
    private var tempColor: Color {
        if batteryManager.temperature < 35 { return .green }
        if batteryManager.temperature < 40 { return .yellow }
        return .red
    }
}

// MARK: - Settings Detail View

struct SettingsDetailView: View {
    @ObservedObject var batteryManager: BatteryManager
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showPercentInMenu") private var showPercentInMenu = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("lowBatteryThreshold") private var lowBatteryThreshold = 20
    @AppStorage("fullChargeNotification") private var fullChargeNotification = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // General
                GroupBox {
                    VStack(spacing: 12) {
                        Toggle("Launch at Login", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { newValue in
                                updateLaunchAtLogin(newValue)
                            }
                        Divider()
                        Toggle("Show Percentage in Menu Bar", isOn: $showPercentInMenu)
                    }
                    .padding(8)
                } label: {
                    Label("General", systemImage: "slider.horizontal.3")
                }
                
                // Notifications
                GroupBox {
                    VStack(spacing: 12) {
                        Toggle("Enable Notifications", isOn: $notificationsEnabled)
                        Divider()
                        Toggle("Full Charge Alert", isOn: $fullChargeNotification)
                            .disabled(!notificationsEnabled)
                        Divider()
                        HStack {
                            Text("Low Battery Threshold")
                            Spacer()
                            Picker("", selection: $lowBatteryThreshold) {
                                Text("10%").tag(10)
                                Text("15%").tag(15)
                                Text("20%").tag(20)
                                Text("25%").tag(25)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 80)
                            .disabled(!notificationsEnabled)
                        }
                    }
                    .padding(8)
                } label: {
                    Label("Notifications", systemImage: "bell.fill")
                }
                
                // Sailing Mode defaults
                GroupBox {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Default Charge Limit")
                            Spacer()
                            Text("\(Int(batteryManager.chargeLimit))%")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: $batteryManager.chargeLimit, in: 20...100, step: 5)
                        
                        HStack {
                            Text("Quick Presets")
                            Spacer()
                            Picker("", selection: Binding(
                                get: { Int(batteryManager.chargeLimit) },
                                set: { batteryManager.setChargePreset($0) }
                            )) {
                                Text("60%").tag(60)
                                Text("80%").tag(80)
                                Text("100%").tag(100)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                    }
                    .padding(8)
                } label: {
                    HStack {
                        Label("Sailing Mode", systemImage: "sailboat.fill")
                        ProBadge()
                    }
                }
                
                // License
                LicenseStatusView()
                
                // About
                GroupBox {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        HStack {
                            Text("Build")
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                } label: {
                    Label("About", systemImage: "info.circle.fill")
                }
            }
            .padding(20)
        }
        .navigationTitle("Settings")
    }
    
    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}

// MARK: - Helper Views

struct DetailRow: View {
    let label: String
    let value: String
    var color: Color? = nil

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(color ?? .primary)
        }
    }
}

struct HealthTip: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Sailing Mode Section (Pro Gated)

struct SailingModeSection: View {
    @ObservedObject var batteryManager: BatteryManager
    @StateObject private var licenseManager = LicenseManager.shared
    var onUpgrade: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Sailing Mode")
                            .font(.headline)
                        if licenseManager.currentTier == .free {
                            ProBadge()
                        }
                    }
                    Text("Limit charge to preserve battery health")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if licenseManager.hasAccess(to: .sailingMode) {
                    Toggle("", isOn: $batteryManager.sailingModeEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                } else {
                    Button {
                        onUpgrade?()
                    } label: {
                        Text("Unlock")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            if licenseManager.hasAccess(to: .sailingMode) && batteryManager.sailingModeEnabled {
                VStack(spacing: 12) {
                    HStack {
                        Text("Charge Limit")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(batteryManager.chargeLimit))%")
                            .font(.subheadline.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(value: $batteryManager.chargeLimit, in: 20...100, step: 5)
                    
                    Picker("", selection: Binding(
                        get: { Int(batteryManager.chargeLimit) },
                        set: { batteryManager.setChargePreset($0) }
                    )) {
                        Text("60%").tag(60)
                        Text("80%").tag(80)
                        Text("100%").tag(100)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: batteryManager.sailingModeEnabled)
    }
}

// MARK: - Share Stats Sheet

struct ShareStatsSheet: View {
    @ObservedObject var batteryManager: BatteryManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Share Battery Stats")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Battery: \(batteryManager.batteryLevel)%")
                    Text("Health: \(batteryManager.healthPercent)%")
                    Text("Cycles: \(batteryManager.cycleCount)")
                    Text("Condition: \(batteryManager.batteryCondition)")
                }
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Copy to Clipboard") {
                    batteryManager.copyStatsToClipboard()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

// MARK: - Share App Sheet

struct ShareAppSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let appURL = "https://github.com/icon-mania/BrewCap"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Share BrewCap")
                .font(.headline)
            
            if let qrImage = generateQRCode(from: appURL) {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .background(Color.white)
                    .cornerRadius(8)
            }
            
            Text(appURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            
            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appURL, forType: .string)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 280)
    }
    
    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let ciImage = filter.outputImage else { return nil }
        let scale = 10.0
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}

// MARK: - Legacy Settings View (for AppDelegate)

struct SettingsView: View {
    @ObservedObject var batteryManager: BatteryManager
    
    var body: some View {
        SettingsDetailView(batteryManager: batteryManager)
    }
}
