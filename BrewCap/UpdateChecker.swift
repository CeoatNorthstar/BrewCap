//
//  UpdateChecker.swift
//  BrewCap
//
//  Copyright (c) 2026 NorthStars Industries. All rights reserved.
//

import AppKit
import Combine
import UserNotifications

// MARK: - UpdateChecker

class UpdateChecker: NSObject, ObservableObject {
    static let shared = UpdateChecker()

    // MARK: Published state

    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String?
    @Published var latestReleaseURL: URL?

    // MARK: Private

    private let repoOwner = "CeoatNorthstar"
    private let repoName  = "BrewCap"
    private let checkInterval: TimeInterval = 5 * 60   // 5 minutes
    private var checkTimer: Timer?

    // UserDefaults key to track which versions we've already notified about
    private let notifiedKey = "brewcap.notifiedUpdateVersions"

    private var notifiedVersions: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: notifiedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: notifiedKey) }
    }

    // MARK: Init

    private override init() { super.init() }

    // MARK: - Public API

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Request notification permission and start periodic checks.
    func startChecking() {
        requestNotificationPermission()
        // Delay first check slightly so the app finishes launching first
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.checkForUpdate()
        }
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdate()
        }
    }

    func stopChecking() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// Fetches latest release from GitHub. Calls `completion(isNewer, latestTag)` on the main queue.
    func checkForUpdate(completion: ((Bool, String?) -> Void)? = nil) {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion?(false, nil) }
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("BrewCap/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self, let data, error == nil else {
                DispatchQueue.main.async { completion?(false, nil) }
                return
            }
            do {
                guard
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let tagName  = json["tag_name"]  as? String,
                    let htmlURL  = json["html_url"]  as? String
                else {
                    DispatchQueue.main.async { completion?(false, nil) }
                    return
                }

                let remote  = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let isNewer = self.isNewer(remote, than: self.currentVersion)

                DispatchQueue.main.async {
                    self.latestVersion    = remote
                    self.latestReleaseURL = URL(string: htmlURL)
                    self.updateAvailable  = isNewer

                    if isNewer {
                        var seen = self.notifiedVersions
                        if !seen.contains(remote) {
                            seen.insert(remote)
                            self.notifiedVersions = seen
                            self.sendNotification(version: remote)
                        }
                    }

                    completion?(isNewer, isNewer ? remote : nil)
                }
            } catch {
                DispatchQueue.main.async { completion?(false, nil) }
            }
        }.resume()
    }

    /// Shows an NSAlert prompting the user to update.
    func promptUpdate(relativeTo window: NSWindow? = nil) {
        guard let version = latestVersion else { return }

        let alert = NSAlert()
        alert.messageText        = "BrewCap \(version) Available"
        alert.informativeText    = "You are running v\(currentVersion). Would you like to update now?"
        alert.alertStyle         = .informational
        alert.icon               = NSApp.applicationIconImage

        if isBrewAvailable {
            alert.addButton(withTitle: "Update with Brew")
            alert.addButton(withTitle: "View on GitHub")
            alert.addButton(withTitle: "Later")
        } else {
            alert.addButton(withTitle: "Download on GitHub")
            alert.addButton(withTitle: "Later")
        }

        let response = alert.runModal()
        if isBrewAvailable {
            switch response {
            case .alertFirstButtonReturn:  updateWithBrew()
            case .alertSecondButtonReturn: openReleasePage()
            default: break
            }
        } else {
            if response == .alertFirstButtonReturn { openReleasePage() }
        }
    }

    // MARK: - Update actions

    var isBrewAvailable: Bool {
        FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ||
        FileManager.default.fileExists(atPath: "/usr/local/bin/brew")
    }

    func openReleasePage() {
        let url = latestReleaseURL
            ?? URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!
        NSWorkspace.shared.open(url)
    }

    /// Opens Terminal and runs `brew upgrade --cask brewcap`, falling back to the release page on error.
    func updateWithBrew() {
        let brew = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew")
            ? "/opt/homebrew/bin/brew"
            : "/usr/local/bin/brew"
        let fallbackURL = "https://github.com/\(repoOwner)/\(repoName)/releases/latest"
        // Try cask first, then formula, then open browser if neither finds BrewCap
        let cmd = "\(brew) upgrade --cask brewcap 2>/dev/null"
              + " || \(brew) upgrade brewcap 2>/dev/null"
              + " || open '\(fallbackURL)'"
        let script = """
        tell application "Terminal"
            activate
            do script "\(cmd)"
        end tell
        """
        var appleScriptError: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&appleScriptError)
        if appleScriptError != nil { openReleasePage() }
    }

    // MARK: - Private helpers

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator:  ".").compactMap { Int($0) }
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(version: String) {
        let content       = UNMutableNotificationContent()
        content.title     = "BrewCap \(version) Available"
        content.body      = "A new version is ready. Click to update."
        content.sound     = .default
        content.userInfo  = ["version": version]

        let request = UNNotificationRequest(
            identifier: "brewcap.update.\(version)",
            content: content,
            trigger: nil          // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
