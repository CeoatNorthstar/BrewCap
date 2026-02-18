# Distributing BrewCap via Homebrew Tap

## Overview

This lets users install BrewCap with:

```bash
brew tap CeoatNorthstar/brewcap
brew install brewcap
```

No Apple notarization needed — Homebrew casks can skip Gatekeeper.

---

## Step 1: Create a GitHub Release with the DMG

```bash
# Tag the release
cd ~/Developer/BrewCap
git tag -a v1.0 -m "BrewCap v1.0"
git push origin v1.0
```

Then go to **https://github.com/CeoatNorthstar/BrewCap/releases/new**:

1. Choose tag `v1.0`
2. Title: `BrewCap v1.0`
3. Drag and drop `~/Desktop/BrewCap-1.0.dmg` as a release asset
4. Publish the release

After uploading, copy the DMG download URL. It will look like:

```
https://github.com/CeoatNorthstar/BrewCap/releases/download/v1.0/BrewCap-1.0.dmg
```

## Step 2: Get the SHA256 hash

```bash
shasum -a 256 ~/Desktop/BrewCap-1.0.dmg
```

Copy the hash — you'll need it for the cask formula.

## Step 3: Create the Homebrew Tap repo

Create a new GitHub repo named **`homebrew-brewcap`** (the `homebrew-` prefix is required):

```bash
cd ~/Developer
mkdir homebrew-brewcap && cd homebrew-brewcap
git init
mkdir Casks
```

## Step 4: Create the Cask formula

```bash
cat > Casks/brewcap.rb << 'EOF'
cask "brewcap" do
  version "1.0"
  sha256 "PASTE_YOUR_SHA256_HERE"

  url "https://github.com/CeoatNorthstar/BrewCap/releases/download/v#{version}/BrewCap-#{version}.dmg"
  name "BrewCap"
  desc "Battery health and charge management for macOS"
  homepage "https://github.com/CeoatNorthstar/BrewCap"

  preflight do
    system_command "xattr", args: ["-cr", "#{staged_path}/BrewCap.app"]
  end

  app "BrewCap.app"

  zap trash: [
    "~/Library/Preferences/com.brewcap.app.plist",
  ]
end
EOF
```

Replace `PASTE_YOUR_SHA256_HERE` with the actual hash from Step 2.

## Step 5: Push the tap repo

```bash
cd ~/Developer/homebrew-brewcap
git add .
git commit -m "Add BrewCap cask v1.0"
git remote add origin git@github.com:CeoatNorthstar/homebrew-brewcap.git
git branch -M main
git push -u origin main
```

## Step 6: Test the install

```bash
brew tap CeoatNorthstar/brewcap
brew install brewcap
```

---

## Updating for New Releases

When you release a new version (e.g. v1.1):

1. Update `CFBundleShortVersionString` in `Info.plist` to `1.1`
2. Build the DMG → outputs as `~/Desktop/BrewCap-1.1.dmg`
3. Create a GitHub release tagged `v1.1`, upload the DMG
4. Get the new SHA256: `shasum -a 256 ~/Desktop/BrewCap-1.1.dmg`
5. Update `Casks/brewcap.rb` with new version + hash
6. Commit and push the tap repo

Users update with: `brew upgrade brewcap`

---

## Quick Reference

| Command                             | What it does         |
| ----------------------------------- | -------------------- |
| `brew tap CeoatNorthstar/brewcap`   | Adds your tap        |
| `brew install brewcap`              | Installs BrewCap.app |
| `brew upgrade brewcap`              | Updates to latest    |
| `brew uninstall brewcap`            | Removes BrewCap      |
| `brew untap CeoatNorthstar/brewcap` | Removes the tap      |
