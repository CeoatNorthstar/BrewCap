//
//  LicenseViews.swift
//  BrewCap
//
//  License Management UI Components
//  Copyright (c) 2026 NorthStars Industries. All rights reserved.
//

import SwiftUI

// MARK: - License Status View (for Settings)

struct LicenseStatusView: View {
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var showActivation = false
    @State private var showDeactivateConfirm = false
    
    var body: some View {
        GroupBox {
            VStack(spacing: 16) {
                // Current status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(licenseManager.currentTier.displayName)
                                .font(.headline)
                            
                            if licenseManager.currentTier == .pro {
                                Text("ACTIVE")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.green)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        if let license = licenseManager.licenseInfo {
                            Text(license.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if let days = license.daysRemaining {
                                Text("\(days) days remaining")
                                    .font(.caption)
                                    .foregroundStyle(days < 7 ? .orange : .secondary)
                            }
                        } else {
                            Text("Upgrade to Pro for all features")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if licenseManager.currentTier == .free {
                        Button("Activate License") {
                            showActivation = true
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Menu {
                            Button("View License Details") {
                                showActivation = true
                            }
                            
                            Button("Refresh License") {
                                Task {
                                    try? await licenseManager.revalidateLicense()
                                }
                            }
                            
                            Divider()
                            
                            Button("Deactivate License", role: .destructive) {
                                showDeactivateConfirm = true
                            }
                        } label: {
                            Label("Manage", systemImage: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
                
                // Revalidation warning
                if licenseManager.needsRevalidation {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("License needs verification. Please connect to the internet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(8)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(8)
        } label: {
            Label("License", systemImage: "key.fill")
        }
        .sheet(isPresented: $showActivation) {
            LicenseActivationView()
        }
        .alert("Deactivate License?", isPresented: $showDeactivateConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Deactivate", role: .destructive) {
                try? licenseManager.deactivateLicense()
            }
        } message: {
            Text("This will remove the license from this device. You can reactivate anytime with your license key.")
        }
    }
}

// MARK: - License Activation View

struct LicenseActivationView: View {
    @StateObject private var licenseManager = LicenseManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var licenseKey = ""
    @State private var isActivating = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(licenseManager.currentTier == .pro ? "License Details" : "Activate Pro")
                        .font(.title2.weight(.semibold))
                    Text(licenseManager.currentTier == .pro ? "Manage your license" : "Enter your license key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            if licenseManager.currentTier == .pro, let license = licenseManager.licenseInfo {
                // Show license details
                ScrollView {
                    VStack(spacing: 20) {
                        // Status card
                        GroupBox {
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.largeTitle)
                                        .foregroundStyle(.green)
                                    VStack(alignment: .leading) {
                                        Text("Pro License Active")
                                            .font(.headline)
                                        Text(license.email)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                
                                Divider()
                                
                                LicenseDetailRow(label: "License Key", value: maskLicenseKey(license.licenseKey))
                                LicenseDetailRow(label: "Activated", value: formatDate(license.purchaseDate))
                                LicenseDetailRow(label: "Last Verified", value: formatDate(license.validatedAt))
                                if let expiration = license.expirationDate {
                                    LicenseDetailRow(label: "Expires", value: formatDate(expiration))
                                }
                                LicenseDetailRow(label: "Device ID", value: String(license.machineId.prefix(8)) + "...")
                            }
                            .padding(8)
                        }
                        
                        // Features list
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Included Features")
                                    .font(.headline)
                                
                                ForEach(LicenseTier.pro.features, id: \.self) { feature in
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                        Text(feature)
                                        Spacer()
                                    }
                                    .font(.subheadline)
                                }
                            }
                            .padding(8)
                        }
                    }
                    .padding(20)
                }
            } else {
                // Activation form
                ScrollView {
                    VStack(spacing: 20) {
                        // Features comparison
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Pro Features")
                                    .font(.headline)
                                
                                ForEach(LicenseTier.pro.features, id: \.self) { feature in
                                    HStack {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(.yellow)
                                            .font(.caption)
                                        Text(feature)
                                        Spacer()
                                    }
                                    .font(.subheadline)
                                }
                            }
                            .padding(8)
                        }
                        
                        // License key input
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Enter License Key")
                                    .font(.headline)
                                
                                TextField("XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX", text: $licenseKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .autocorrectionDisabled()
                                    .onChange(of: licenseKey) { newValue in
                                        licenseKey = formatLicenseKey(newValue)
                                    }
                                
                                if let error = errorMessage {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.red)
                                        Text(error)
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                }
                                
                                Text("Your license key was sent to your email after purchase.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                        }
                        
                        // Purchase link
                        GroupBox {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Don't have a license?")
                                        .font(.subheadline)
                                    Text("Purchase Pro to unlock all features")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Link(destination: URL(string: "https://axionceo.gumroad.com/l/BREWCAP_PRO")!) {
                                    Text("Buy Pro")
                                        .font(.subheadline.weight(.medium))
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(8)
                        }
                    }
                    .padding(20)
                }
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                if licenseManager.currentTier == .free {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                
                Spacer()
                
                if licenseManager.currentTier == .free {
                    Button {
                        activateLicense()
                    } label: {
                        if isActivating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 80)
                        } else {
                            Text("Activate")
                                .frame(width: 80)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(licenseKey.count < 35 || isActivating)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 450)
        .frame(minHeight: 500)
        .alert("License Activated!", isPresented: $showSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Welcome to BrewCap Pro! All features are now unlocked.")
        }
    }
    
    private func activateLicense() {
        isActivating = true
        errorMessage = nil
        
        Task {
            do {
                try await licenseManager.activateLicense(key: licenseKey)
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isActivating = false
        }
    }
    
    private func formatLicenseKey(_ input: String) -> String {
        let cleaned = input.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        
        // Remove all dashes and reformat
        let noHyphens = cleaned.filter { $0 != "-" }
        var result = ""
        
        for (index, char) in noHyphens.prefix(32).enumerated() {
            if index > 0 && index % 8 == 0 {
                result += "-"
            }
            result.append(char)
        }
        
        return result
    }
    
    private func maskLicenseKey(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 4 else { return key }
        return "\(parts[0])-****-****-\(parts[3])"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - License Detail Row

struct LicenseDetailRow: View {
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
        .font(.subheadline)
    }
}

// MARK: - Pro Feature Gate

struct ProFeatureGate<Content: View>: View {
    let feature: ProFeature
    @ViewBuilder let content: Content
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var showUpgrade = false
    
    var body: some View {
        if licenseManager.hasAccess(to: feature) {
            content
        } else {
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("\(feature.displayName)")
                    .font(.title2.weight(.bold))
                
                Text("This is a Pro feature")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text("Upgrade to unlock \(feature.displayName.lowercased()) and protect your battery with advanced features.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Button {
                    showUpgrade = true
                } label: {
                    HStack {
                        Image(systemName: "bolt.shield.fill")
                        Text("Upgrade to Pro")
                    }
                    .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .sheet(isPresented: $showUpgrade) {
                UpgradeWindow()
            }
        }
    }
}

// MARK: - Pro Badge

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                LinearGradient(
                    colors: [.purple, .blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}

// MARK: - Inline Upgrade Prompt

struct InlineUpgradePrompt: View {
    @State private var showUpgrade = false
    
    var body: some View {
        HStack {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
            
            Text("Upgrade to Pro for all features")
                .font(.subheadline)
            
            Spacer()
            
            Button("Upgrade") {
                showUpgrade = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showUpgrade) {
            LicenseActivationView()
        }
    }
}

// MARK: - In-App Gumroad Checkout

import WebKit

struct GumroadCheckoutView: NSViewRepresentable {
    let productURL: String
    var onPurchaseComplete: ((String) -> Void)? = nil
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // Load Gumroad overlay checkout
        let overlayURL: String
        if productURL.contains("?") {
            overlayURL = productURL + "&wanted=true"
        } else {
            overlayURL = productURL + "?wanted=true"
        }
        if let url = URL(string: overlayURL) {
            webView.load(URLRequest(url: url))
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPurchaseComplete: onPurchaseComplete)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var onPurchaseComplete: ((String) -> Void)?
        
        init(onPurchaseComplete: ((String) -> Void)?) {
            self.onPurchaseComplete = onPurchaseComplete
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Check if this is a successful purchase redirect
            if let url = navigationAction.request.url?.absoluteString {
                if url.contains("license_key=") || url.contains("receipt") {
                    // Extract license key if present
                    if let range = url.range(of: "license_key=") {
                        let keyStart = url[range.upperBound...]
                        let key = String(keyStart.prefix(35))
                        onPurchaseComplete?(key)
                    }
                }
            }
            decisionHandler(.allow)
        }
    }
}

// MARK: - Upgrade Window (Full Purchase Flow)

struct UpgradeWindow: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var selectedPlan: PricingPlan = .yearly
    @State private var showCheckout = false
    @State private var showActivation = false
    @State private var purchasedKey: String = ""
    
    enum PricingPlan: String, CaseIterable {
        case monthly = "Monthly"
        case quarterly = "3 Months"
        case biannual = "6 Months"
        case yearly = "Yearly"
        
        var price: String {
            switch self {
            case .monthly: return "$8"
            case .quarterly: return "$26"
            case .biannual: return "$49"
            case .yearly: return "$100"
            }
        }
        
        var period: String {
            switch self {
            case .monthly: return "/month"
            case .quarterly: return "/3 months"
            case .biannual: return "/6 months"
            case .yearly: return "/year"
            }
        }
        
        var savings: String? {
            switch self {
            case .monthly: return nil
            case .quarterly: return "Save 8%"
            case .biannual: return "Save 18%"
            case .yearly: return "Best Value"
            }
        }
        
        var gumroadVariant: String {
            switch self {
            case .monthly: return "Monthly"
            case .quarterly: return "Quarterly"
            case .biannual: return "Biannual"
            case .yearly: return "Yearly"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("Upgrade to Pro")
                    .font(.title.weight(.bold))
                
                Text("Unlock all features and protect your battery")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 30)
            .padding(.bottom, 20)
            
            // Features
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    FeatureRow(icon: "sailboat.fill", title: "Sailing Mode", description: "Limit charging to extend battery lifespan")
                    Divider()
                    FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Health Analytics", description: "Deep insights into battery health trends")
                    Divider()
                    FeatureRow(icon: "doc.text.fill", title: "Battery Reports", description: "Export detailed reports & diagnostics")
                    Divider()
                    FeatureRow(icon: "bell.badge.fill", title: "Smart Alerts", description: "Custom notifications for all events")
                }
                .padding(8)
            }
            .padding(.horizontal, 24)
            
            // Pricing plans
            VStack(spacing: 12) {
                Text("Choose your plan")
                    .font(.headline)
                    .padding(.top, 20)
                
                HStack(spacing: 12) {
                    ForEach(PricingPlan.allCases, id: \.self) { plan in
                        PlanCard(plan: plan, isSelected: selectedPlan == plan) {
                            selectedPlan = plan
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            
            Spacer()
            
            // CTA
            VStack(spacing: 12) {
                Button {
                    showCheckout = true
                } label: {
                    HStack {
                        Text("Continue with \(selectedPlan.price)\(selectedPlan.period)")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button("I already have a license key") {
                    showActivation = true
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                
                Text("Secure payment via Gumroad • Cancel anytime")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
        }
        .frame(width: 500, height: 620)
        .sheet(isPresented: $showCheckout) {
            GumroadCheckoutSheet(plan: selectedPlan) { licenseKey in
                purchasedKey = licenseKey
                showCheckout = false
                // Auto-activate the license
                Task {
                    try? await licenseManager.activateLicense(key: licenseKey)
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showActivation) {
            LicenseActivationView()
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

// MARK: - Plan Card

struct PlanCard: View {
    let plan: UpgradeWindow.PricingPlan
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let savings = plan.savings {
                    Text(savings)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(plan == .yearly ? .green : .orange)
                        .clipShape(Capsule())
                } else {
                    Text(" ")
                        .font(.caption2)
                }
                
                Text(plan.price)
                    .font(.title2.weight(.bold))
                
                Text(plan.period)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Gumroad Checkout Sheet

struct GumroadCheckoutSheet: View {
    let plan: UpgradeWindow.PricingPlan
    var onPurchaseComplete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    
    private var checkoutURL: String {
        "https://axionceo.gumroad.com/l/BREWCAP_PRO"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Complete Purchase")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ZStack {
                GumroadCheckoutView(productURL: checkoutURL) { key in
                    onPurchaseComplete(key)
                }
                
                if isLoading {
                    VStack {
                        ProgressView()
                        Text("Loading checkout...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    isLoading = false
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.green)
                Text("Secure checkout powered by Gumroad")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Enter License Key Instead") {
                    dismiss()
                }
                .font(.caption)
            }
            .padding()
        }
        .frame(width: 500, height: 650)
    }
}

// MARK: - Pro Feature Required Alert

struct ProFeatureRequiredView: View {
    let feature: ProFeature
    @Environment(\.dismiss) private var dismiss
    @State private var showUpgrade = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.linearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
            
            Text("\(feature.displayName) Requires Pro")
                .font(.title2.weight(.bold))
            
            Text("Upgrade to BrewCap Pro to unlock \(feature.displayName.lowercased()) and all other premium features.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                Button {
                    showUpgrade = true
                } label: {
                    Text("Upgrade to Pro")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button("Maybe Later") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
        }
        .padding(30)
        .frame(width: 380)
        .sheet(isPresented: $showUpgrade) {
            UpgradeWindow()
        }
    }
}

