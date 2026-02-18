import Foundation

/// Manages the bundled `smc` binary for hardware charging control.
/// Uses visudo NOPASSWD entries so admin password is only needed ONCE during setup.
class SMCClient {

    /// Path to the smc binary bundled with the app
    static var smcPath: String {
        // First check if installed to /usr/local/bin/brewcap-smc (after setup)
        let installed = "/usr/local/bin/brewcap-smc"
        if FileManager.default.fileExists(atPath: installed) {
            return installed
        }
        // Fallback to bundle
        return Bundle.main.path(forResource: "smc", ofType: nil) ?? ""
    }

    /// Whether the one-time visudo setup has been completed
    static var isSetupComplete: Bool {
        UserDefaults.standard.bool(forKey: "brewcap_setup_complete")
    }

    // MARK: - One-time Setup (installs smc + visudo entry)

    /// Performs one-time setup: copies smc to /usr/local/bin and adds visudo entry.
    /// This is the ONLY time the user is prompted for their password.
    static func performOneTimeSetup() -> Bool {
        guard let bundledSmc = Bundle.main.path(forResource: "smc", ofType: nil) else {
            print("SMCClient: smc binary not found in bundle")
            return false
        }

        let installPath = "/usr/local/bin/brewcap-smc"
        let visudoFile = "/etc/sudoers.d/brewcap"

        // Build a shell script that:
        // 1. Copies the smc binary to /usr/local/bin/brewcap-smc
        // 2. Makes it executable
        // 3. Creates a visudo NOPASSWD entry so future calls don't need password
        let visudoContent = """
        # BrewCap battery charging control
        ALL ALL = NOPASSWD: \(installPath) -k CHTE -r
        ALL ALL = NOPASSWD: \(installPath) -k CHTE -w 01000000
        ALL ALL = NOPASSWD: \(installPath) -k CHTE -w 00000000
        ALL ALL = NOPASSWD: \(installPath) -k CHIE -r
        ALL ALL = NOPASSWD: \(installPath) -k CHIE -w 08
        ALL ALL = NOPASSWD: \(installPath) -k CHIE -w 00
        """

        let escapedBundled = bundledSmc.replacingOccurrences(of: "'", with: "'\\''")
        let escapedVisudo = visudoContent.replacingOccurrences(of: "\"", with: "\\\"")

        let setupScript = """
        cp '\(escapedBundled)' \(installPath) && \
        chmod 755 \(installPath) && \
        echo "\(escapedVisudo)" > \(visudoFile) && \
        chmod 0440 \(visudoFile) && \
        chown root:wheel \(visudoFile)
        """

        let escapedSetup = setupScript.replacingOccurrences(of: "\\", with: "\\\\")
                                       .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escapedSetup)\" with administrator privileges"

        print("SMCClient: performing one-time setup...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if !output.isEmpty { print("  stdout: \(output)") }
            if !errOutput.isEmpty { print("  stderr: \(errOutput)") }

            if process.terminationStatus == 0 {
                UserDefaults.standard.set(true, forKey: "brewcap_setup_complete")
                print("SMCClient: setup complete — no more password prompts!")
                return true
            } else {
                print("SMCClient: setup failed (exit \(process.terminationStatus))")
                return false
            }
        } catch {
            print("SMCClient: setup launch failed: \(error)")
            return false
        }
    }

    // MARK: - SMC Read/Write (password-free after setup)

    /// Read an SMC key. Returns hex string or nil.
    static func readKey(_ key: String) -> String? {
        let path = smcPath
        guard !path.isEmpty else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = [path, "-k", key, "-r"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Write hex value to SMC key. Returns true on success.
    static func writeKey(_ key: String, hex: String) -> Bool {
        let path = smcPath
        guard !path.isEmpty else { return false }

        print("SMCClient: sudo \(path) -k \(key) -w \(hex)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = [path, "-k", key, "-w", hex]

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if !output.isEmpty { print("  stdout: \(output.trimmingCharacters(in: .whitespacesAndNewlines))") }
            if !errOutput.isEmpty { print("  stderr: \(errOutput.trimmingCharacters(in: .whitespacesAndNewlines))") }

            let success = process.terminationStatus == 0
            print("  result: \(success ? "OK" : "FAILED")")
            return success
        } catch {
            print("  error: \(error)")
            return false
        }
    }

    // MARK: - High-level charging control

    /// Disable charging via CHTE key (macOS 26 Tahoe)
    static func disableCharging() -> Bool {
        return writeKey("CHTE", hex: "01000000")
    }

    /// Enable charging via CHTE key
    static func enableCharging() -> Bool {
        return writeKey("CHTE", hex: "00000000")
    }

    /// Check if charging is currently inhibited
    static func isChargingInhibited() -> Bool {
        guard let output = readKey("CHTE") else { return false }
        // Output looks like: "  CHTE  [ui32]  (bytes 01 00 00 00)"
        // Extract the first byte after "bytes "
        guard let range = output.range(of: "bytes ") else { return false }
        let bytesStr = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let firstByte = bytesStr.prefix(2)
        return firstByte == "01"
    }
}
