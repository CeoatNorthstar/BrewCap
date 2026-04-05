//
//  LicenseManager.swift
//  BrewCap
//
//  Enterprise License Key Management System
//  Copyright (c) 2026 NorthStars Industries. All rights reserved.
//

import Foundation
import CryptoKit
import Security
import AppKit

// MARK: - License Tier

enum LicenseTier: String, Codable, CaseIterable {
    case free = "free"
    case pro = "pro"
    
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        }
    }
    
    var features: [String] {
        switch self {
        case .free:
            return [
                "Basic battery monitoring",
                "Menu bar percentage display",
                "Basic notifications"
            ]
        case .pro:
            return [
                "Everything in Free",
                "Sailing Mode (charge limiting)",
                "Advanced health analytics",
                "Battery reports & export",
                "Priority support",
                "Unlimited devices"
            ]
        }
    }
}

// MARK: - License Info

struct LicenseInfo: Codable {
    let licenseKey: String
    let email: String
    let tier: LicenseTier
    let productId: String
    let purchaseDate: Date
    let expirationDate: Date?
    let isSubscription: Bool
    let machineId: String
    let validatedAt: Date
    let uses: Int
    let maxUses: Int?
    
    var isExpired: Bool {
        guard let expiration = expirationDate else { return false }
        return Date() > expiration
    }
    
    var isValid: Bool {
        !isExpired
    }
    
    var daysRemaining: Int? {
        guard let expiration = expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiration).day
    }
}

// MARK: - Validation Response

struct GumroadValidationResponse: Codable {
    let success: Bool
    let uses: Int?
    let purchase: GumroadPurchase?
    let message: String?
}

struct GumroadPurchase: Codable {
    let sellerID: String?
    let productID: String?
    let productName: String?
    let permalink: String?
    let productPermalink: String?
    let email: String?
    let price: Int?
    let gumroadFee: Int?
    let currency: String?
    let quantity: Int?
    let discoverFeeCharged: Bool?
    let canContact: Bool?
    let referrer: String?
    let orderNumber: Int?
    let saleID: String?
    let saleTimestamp: String?
    let purchaserID: String?
    let subscriptionID: String?
    let variants: String?
    let licenseKey: String?
    let isMultiseatLicense: Bool?
    let ipCountry: String?
    let recurrence: String?
    let isGiftReceiverPurchase: Bool?
    let refunded: Bool?
    let disputed: Bool?
    let disputeWon: Bool?
    let chargebacked: Bool?
    let subscriptionEndedAt: String?
    let subscriptionCancelledAt: String?
    let subscriptionFailedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case sellerID = "seller_id"
        case productID = "product_id"
        case productName = "product_name"
        case permalink
        case productPermalink = "product_permalink"
        case email
        case price
        case gumroadFee = "gumroad_fee"
        case currency
        case quantity
        case discoverFeeCharged = "discover_fee_charged"
        case canContact = "can_contact"
        case referrer
        case orderNumber = "order_number"
        case saleID = "sale_id"
        case saleTimestamp = "sale_timestamp"
        case purchaserID = "purchaser_id"
        case subscriptionID = "subscription_id"
        case variants
        case licenseKey = "license_key"
        case isMultiseatLicense = "is_multiseat_license"
        case ipCountry = "ip_country"
        case recurrence
        case isGiftReceiverPurchase = "is_gift_receiver_purchase"
        case refunded
        case disputed
        case disputeWon = "dispute_won"
        case chargebacked
        case subscriptionEndedAt = "subscription_ended_at"
        case subscriptionCancelledAt = "subscription_cancelled_at"
        case subscriptionFailedAt = "subscription_failed_at"
    }
}

// MARK: - License Errors

enum LicenseError: LocalizedError {
    case invalidKey
    case keyExpired
    case keyRefunded
    case keyDisputed
    case subscriptionEnded
    case networkError(Error)
    case validationFailed(String)
    case keychainError
    case machineNotAuthorized
    case maxUsesReached
    
    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Invalid license key. Please check and try again."
        case .keyExpired:
            return "Your license has expired. Please renew to continue using Pro features."
        case .keyRefunded:
            return "This license key has been refunded and is no longer valid."
        case .keyDisputed:
            return "This license key is under dispute and temporarily disabled."
        case .subscriptionEnded:
            return "Your subscription has ended. Please renew to continue."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .keychainError:
            return "Unable to securely store license. Please try again."
        case .machineNotAuthorized:
            return "This device is not authorized. Please deactivate another device first."
        case .maxUsesReached:
            return "Maximum activations reached. Please deactivate another device."
        }
    }
}

// MARK: - License Manager

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    
    // MARK: - Configuration
    
    /// Your Gumroad product permalink (set this after creating your product)
    private let productPermalink = "BREWCAP_PRO" // Replace with your actual permalink
    
    /// Gumroad API endpoint
    private let gumroadAPIURL = "https://api.gumroad.com/v2/licenses/verify"
    
    /// How often to revalidate (in seconds) - 24 hours
    private let revalidationInterval: TimeInterval = 86400
    
    /// Grace period for offline use (in days)
    private let offlineGracePeriod: Int = 7
    
    // MARK: - Published Properties
    
    @Published private(set) var currentTier: LicenseTier = .free
    @Published private(set) var licenseInfo: LicenseInfo?
    @Published private(set) var isValidating = false
    @Published private(set) var lastError: LicenseError?
    @Published private(set) var needsRevalidation = false
    
    // MARK: - Private Properties
    
    private let keychainService = "com.northstars.brewcap.license"
    private let keychainAccount = "license_info"
    private let userDefaults = UserDefaults.standard
    private let machineId: String
    
    // MARK: - Initialization
    
    private init() {
        self.machineId = Self.generateMachineId()
        loadStoredLicense()
    }
    
    // MARK: - Public API
    
    /// Activate a license key
    func activateLicense(key: String) async throws {
        isValidating = true
        lastError = nil
        defer { isValidating = false }
        
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        guard isValidKeyFormat(trimmedKey) else {
            let error = LicenseError.invalidKey
            lastError = error
            throw error
        }
        
        do {
            let license = try await validateWithGumroad(licenseKey: trimmedKey)
            try storeLicense(license)
            self.licenseInfo = license
            self.currentTier = license.tier
            self.needsRevalidation = false
            
            NotificationCenter.default.post(name: .licenseActivated, object: license)
        } catch {
            if let licenseError = error as? LicenseError {
                lastError = licenseError
            } else {
                lastError = .networkError(error)
            }
            throw error
        }
    }
    
    /// Deactivate current license
    func deactivateLicense() throws {
        try deleteLicenseFromKeychain()
        licenseInfo = nil
        currentTier = .free
        needsRevalidation = false
        lastError = nil
        
        NotificationCenter.default.post(name: .licenseDeactivated, object: nil)
    }
    
    /// Revalidate existing license
    func revalidateLicense() async throws {
        guard let license = licenseInfo else { return }
        
        isValidating = true
        lastError = nil
        defer { isValidating = false }
        
        do {
            let updatedLicense = try await validateWithGumroad(licenseKey: license.licenseKey)
            try storeLicense(updatedLicense)
            self.licenseInfo = updatedLicense
            self.currentTier = updatedLicense.tier
            self.needsRevalidation = false
        } catch {
            // If network fails, check offline grace period
            if case .networkError = error as? LicenseError {
                if isWithinOfflineGracePeriod(license) {
                    // Allow continued use within grace period
                    needsRevalidation = true
                    return
                }
            }
            
            if let licenseError = error as? LicenseError {
                lastError = licenseError
            }
            throw error
        }
    }
    
    /// Check if a feature is available
    func hasAccess(to feature: ProFeature) -> Bool {
        switch currentTier {
        case .free:
            return feature.availableInFree
        case .pro:
            return true
        }
    }
    
    /// Restore purchases (re-check stored license)
    func restoreLicense() async throws {
        guard let license = licenseInfo else {
            throw LicenseError.invalidKey
        }
        try await revalidateLicense()
    }
    
    // MARK: - Gumroad Validation
    
    private func validateWithGumroad(licenseKey: String) async throws -> LicenseInfo {
        var components = URLComponents(string: gumroadAPIURL)!
        components.queryItems = [
            URLQueryItem(name: "product_permalink", value: productPermalink),
            URLQueryItem(name: "license_key", value: licenseKey),
            URLQueryItem(name: "increment_uses_count", value: "true")
        ]
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseError.networkError(URLError(.badServerResponse))
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw LicenseError.invalidKey
            }
            throw LicenseError.networkError(URLError(.badServerResponse))
        }
        
        let decoder = JSONDecoder()
        let gumroadResponse = try decoder.decode(GumroadValidationResponse.self, from: data)
        
        guard gumroadResponse.success, let purchase = gumroadResponse.purchase else {
            throw LicenseError.validationFailed(gumroadResponse.message ?? "Unknown error")
        }
        
        // Check for refunds/disputes
        if purchase.refunded == true {
            throw LicenseError.keyRefunded
        }
        
        if purchase.disputed == true && purchase.disputeWon != true {
            throw LicenseError.keyDisputed
        }
        
        if purchase.chargebacked == true {
            throw LicenseError.keyRefunded
        }
        
        // Check subscription status
        let isSubscription = purchase.subscriptionID != nil
        var expirationDate: Date? = nil
        
        if isSubscription {
            if let endedAt = purchase.subscriptionEndedAt, !endedAt.isEmpty {
                throw LicenseError.subscriptionEnded
            }
            if let cancelledAt = purchase.subscriptionCancelledAt, !cancelledAt.isEmpty {
                // Subscription cancelled but may still be valid until period ends
                expirationDate = ISO8601DateFormatter().date(from: cancelledAt)
            }
            if let failedAt = purchase.subscriptionFailedAt, !failedAt.isEmpty {
                throw LicenseError.subscriptionEnded
            }
        }
        
        // Parse purchase date
        let purchaseDate: Date
        if let timestamp = purchase.saleTimestamp {
            purchaseDate = ISO8601DateFormatter().date(from: timestamp) ?? Date()
        } else {
            purchaseDate = Date()
        }
        
        // Determine tier based on product or variants
        let tier: LicenseTier = .pro // All Gumroad purchases are Pro
        
        return LicenseInfo(
            licenseKey: licenseKey,
            email: purchase.email ?? "",
            tier: tier,
            productId: purchase.productID ?? productPermalink,
            purchaseDate: purchaseDate,
            expirationDate: expirationDate,
            isSubscription: isSubscription,
            machineId: machineId,
            validatedAt: Date(),
            uses: gumroadResponse.uses ?? 1,
            maxUses: nil
        )
    }
    
    // MARK: - Keychain Storage
    
    private func storeLicense(_ license: LicenseInfo) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(license)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        // Delete existing
        SecItemDelete(query as CFDictionary)
        
        // Add new
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LicenseError.keychainError
        }
    }
    
    private func loadStoredLicense() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            currentTier = .free
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let license = try decoder.decode(LicenseInfo.self, from: data)
            
            // Check if revalidation is needed
            let timeSinceValidation = Date().timeIntervalSince(license.validatedAt)
            
            if license.isExpired {
                // License expired, revert to free
                try? deleteLicenseFromKeychain()
                currentTier = .free
                return
            }
            
            if timeSinceValidation > revalidationInterval {
                // Needs revalidation, but allow use within grace period
                if isWithinOfflineGracePeriod(license) {
                    licenseInfo = license
                    currentTier = license.tier
                    needsRevalidation = true
                } else {
                    // Grace period exceeded
                    try? deleteLicenseFromKeychain()
                    currentTier = .free
                }
            } else {
                licenseInfo = license
                currentTier = license.tier
            }
        } catch {
            currentTier = .free
        }
    }
    
    private func deleteLicenseFromKeychain() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LicenseError.keychainError
        }
    }
    
    // MARK: - Helpers
    
    private func isValidKeyFormat(_ key: String) -> Bool {
        // Gumroad keys are typically 35 characters: XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX
        let pattern = "^[A-Z0-9]{8}-[A-Z0-9]{8}-[A-Z0-9]{8}-[A-Z0-9]{8}$"
        return key.range(of: pattern, options: .regularExpression) != nil
    }
    
    private func isWithinOfflineGracePeriod(_ license: LicenseInfo) -> Bool {
        let daysSinceValidation = Calendar.current.dateComponents(
            [.day],
            from: license.validatedAt,
            to: Date()
        ).day ?? 0
        
        return daysSinceValidation <= offlineGracePeriod
    }
    
    private static func generateMachineId() -> String {
        // Generate a unique machine identifier based on hardware
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        
        defer { IOObjectRelease(platformExpert) }
        
        if let serialNumber = IORegistryEntryCreateCFProperty(
            platformExpert,
            "IOPlatformSerialNumber" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String {
            // Hash the serial number for privacy
            let data = Data(serialNumber.utf8)
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(32).description
        }
        
        // Fallback to UUID
        return UUID().uuidString
    }
}

// MARK: - Pro Features

enum ProFeature {
    case sailingMode
    case healthAnalytics
    case batteryReports
    case exportData
    case prioritySupport
    
    var availableInFree: Bool {
        return false // All Pro features require Pro license
    }
    
    var displayName: String {
        switch self {
        case .sailingMode: return "Sailing Mode"
        case .healthAnalytics: return "Health Analytics"
        case .batteryReports: return "Battery Reports"
        case .exportData: return "Export Data"
        case .prioritySupport: return "Priority Support"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let licenseActivated = Notification.Name("licenseActivated")
    static let licenseDeactivated = Notification.Name("licenseDeactivated")
    static let licenseExpired = Notification.Name("licenseExpired")
}
