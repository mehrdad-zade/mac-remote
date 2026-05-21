# Mac Remote

An open-source iOS app that turns your iPhone into a wireless trackpad, keyboard, and remote control for your Mac — all over your local WiFi network with no cloud required.

---

## Features

- **Full-screen trackpad** — drag to move the cursor, tap to click, two-finger drag to scroll, long press to right-click
- **Virtual desktop switching** — navigate between Mission Control Spaces with the ← → arrows
- **Wireless keyboard** — type on your iPhone's keyboard and the text appears on your Mac
- **Sleep button** — put your Mac to sleep from anywhere in the room
- **Saved machines** — remembers your Macs and PINs so reconnecting is one tap
- **Zero cloud** — everything stays on your local network; Bonjour auto-discovery, no IP addresses to type
- **Modern glass UI** — dark glass design that looks great at a glance

---

## Requirements

| Component | Minimum version |
|-----------|----------------|
| iPhone / iPad | iOS 26+ |
| Mac | macOS 14 (Sonoma) or later |
| Network | Both devices on the **same WiFi network** |
| Xcode (for iOS build) | Xcode 26+ |
| Swift (for Mac build) | Swift 5.9+ (ships with Xcode 26 or `xcode-select`) |

---

## Mac Setup

### 1. Clone the repository

```bash
git clone https://github.com/yourname/mac-remote.git
cd mac-remote
```

### 2. Build and install the Mac server

Run this single command from the repo root — it builds, copies the binary to a stable location, and launches it:

```bash
cd MacServer && swift build -c release && mkdir -p ~/Applications && pkill -x MacServer; cp .build/release/MacServer ~/Applications/MacServer && ~/Applications/MacServer
```

> **Why `~/Applications` and not `/Applications`?** `~/Applications` is your personal Applications folder (visible in Finder under your home folder). Any app can write there without admin rights, and macOS treats it identically to `/Applications` for permissions purposes. The binary won't have a `.app` icon — it runs headless as a menu bar app. Every `swift build` replaces the binary in `.build/`, and macOS treats a changed binary as a new app — revoking its Accessibility permission. Copying to a fixed path means you grant permission once and it sticks. For normal day-to-day use, just run `~/Applications/MacServer` directly; only re-run this command when you update the source.

### 3. Allow incoming connections through the Firewall

If your Mac's firewall is on (most Macs have it enabled), you must add MacServer to the allowlist — otherwise the iOS app will discover the server via Bonjour but every connection attempt will be silently dropped.

Run these two commands (you'll be prompted for your password):

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add ~/Applications/MacServer
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp ~/Applications/MacServer
```

Or do it via the GUI: **System Settings → Network → Firewall → Options…** → **`+`** → select `~/Applications/MacServer` → set it to **Allow incoming connections**.

> **After a rebuild:** Re-run the two `sudo` commands above (or remove and re-add the entry in the GUI). macOS treats the new binary as a different app and revokes the exception.

### 4. Grant Accessibility permission

MacServer needs Accessibility access to move the cursor and inject keyboard input. On first launch the server registers itself with macOS — follow these steps to grant permission:

1. Open **System Settings → Privacy & Security → Accessibility**.

2. Click the **`+`** button at the bottom of the list.

3. In the file picker, press **`⌘ Shift G`**, paste this path (replace `YOUR_USERNAME` with your macOS username — run `whoami` in Terminal if unsure), then click **Open**:
   ```
   /Users/YOUR_USERNAME/Applications/MacServer
   ```

4. `MacServer` will appear in the list — make sure the toggle next to it is **on**.

> **After a rebuild:** If you re-run the install command above, go back to **Privacy & Security → Accessibility**, toggle MacServer **off**, then back **on**. macOS detects the file changed and requires re-confirmation.

### 4. Run the server

```bash
~/Applications/MacServer
```

A cursor icon (⌖) will appear in your menu bar. The server is now broadcasting itself on your local network via Bonjour.

**To launch automatically at login:** Open **System Settings → General → Login Items & Extensions** → click `+` under "Open at Login" → select `~/Applications/MacServer`.

### 6. Set your PIN

Click the ⌖ icon in the menu bar → **Change PIN…** → enter any 4-digit number → **Save**.

You will enter this same PIN in the iOS app to authenticate.

---

## iOS Setup

### 1. Enable Developer Mode on your iPhone

1. Connect your iPhone to your Mac with a cable.
2. On your iPhone: **Settings → Privacy & Security → Developer Mode** → toggle it on.
3. Restart your iPhone when prompted.

> Developer Mode is required to run apps built directly from Xcode without an App Store distribution.

### 2. Open the project in Xcode

```bash
open mac-remote.xcodeproj
```

### 3. Set your signing team

1. In Xcode, click the **mac-remote** project in the navigator.
2. Select the **mac-remote** target → **Signing & Capabilities**.
3. Under **Team**, choose your personal Apple ID (free accounts work for personal devices).
4. Xcode will automatically manage the provisioning profile.

### 4. Select your device and run

1. In the Xcode toolbar, select your iPhone from the device list.
2. Press **⌘R** (or the ▶ Run button).
3. The first time you run, your iPhone will ask you to trust the developer certificate: go to **Settings → General → VPN & Device Management → [your Apple ID] → Trust**.

---

## Usage

### Connecting

1. Make sure the Mac server is running (⌖ in menu bar).
2. Open **Mac Remote** on your iPhone — your Mac appears in the list within a few seconds.
3. Tap your Mac, enter the 4-digit PIN, tap **Connect**.

Previously connected Macs are saved at the top of the list — tap one to auto-fill the PIN and reconnect in one tap.

### Trackpad controls

| Gesture | Action |
|---------|--------|
| 1-finger drag | Move cursor |
| Tap | Left click |
| Long press (~0.4s) | Right click |
| 2-finger drag | Scroll |

### Desktop navigation

Tap **←** or **→** in the top-right corner to switch between Mission Control Spaces.

> You need at least 2 Spaces set up: **System Settings → Desktop & Dock → Mission Control → ☑ Automatically rearrange Spaces** (and create additional desktops in Mission Control).

### Keyboard

Tap the **keyboard** icon in the bottom toolbar to bring up your iPhone's keyboard. The trackpad area stays active above it — you can still move the cursor while typing. Tap **Hide** or swipe the keyboard down to dismiss it.

### Sleep

Tap **moon** (🌙) in the toolbar → confirm → your Mac goes to sleep immediately.

### Disconnect

Tap **✕** in the toolbar to disconnect and return to the server list.

---

## Architecture

```
iPhone (iOS app)          ←→  Mac (MacServer)
────────────────               ──────────────
NWBrowser (Bonjour)   ←→     NWListener port 8080
NWConnection (TCP)    →      ClientSession (per device)
JSON messages + \n    →      InputSimulator (CGEvent)
                      →      SystemController (pmset)
```

### Message protocol

All messages are newline-terminated JSON sent over a plain TCP connection on port 8080.

| Direction | Message | Description |
|-----------|---------|-------------|
| iOS → Mac | `{"type":"auth","pin":"1234"}` | Authentication (sent first) |
| Mac → iOS | `{"type":"authResult","success":true}` | Auth response |
| iOS → Mac | `{"type":"move","dx":5.0,"dy":-3.0}` | Relative cursor movement |
| iOS → Mac | `{"type":"tap"}` | Left click |
| iOS → Mac | `{"type":"rightClick"}` | Right click |
| iOS → Mac | `{"type":"scroll","dx":0,"dy":10}` | Scroll wheel |
| iOS → Mac | `{"type":"keypress","characters":"hello"}` | Text input |
| iOS → Mac | `{"type":"keyCode","code":36}` | Special key (Return=36, Delete=51, Tab=48, Escape=53) |
| iOS → Mac | `{"type":"switchSpace","direction":"left"}` | Switch Mission Control space |
| iOS → Mac | `{"type":"sleep"}` | System sleep |
| iOS → Mac | `{"type":"disconnect"}` | Close session |

---

## Project Structure

```
mac-remote/
├── mac-remote.xcodeproj/          iOS Xcode project
├── mac-remote/                    iOS app source
│   ├── mac_remoteApp.swift        App entry point
│   ├── ContentView.swift          Login / Trackpad router
│   ├── ConnectionManager.swift    Networking + saved servers
│   ├── LoginView.swift            Server discovery + PIN entry
│   ├── TrackpadView.swift         Trackpad UI + gestures
│   ├── KeyboardView.swift         Keyboard input capture
│   └── Assets.xcassets/           App icon + colors
└── MacServer/                     Mac server (Swift Package)
    ├── Package.swift
    ├── MacServer.entitlements
    ├── Resources/
    │   └── AppIcon.icns           Mac app icon
    └── Sources/MacServer/
        ├── main.swift             NSApplication entry
        ├── AppDelegate.swift      Menu bar + PIN dialog
        ├── ServerManager.swift    TCP listener + Bonjour
        ├── InputSimulator.swift   CGEvent mouse/keyboard
        └── SystemController.swift System sleep
```

---

## Building for distribution

### Mac — create a signed .app bundle

The Swift Package builds a CLI binary. To create a proper `.app` bundle with the icon:

1. Open Xcode → **File → New → Project → macOS → App**.
2. Add all files from `MacServer/Sources/MacServer/` to the new target.
3. Drag `MacServer/Resources/AppIcon.icns` into `Assets.xcassets`.
4. Set `LSUIElement = YES` in Info.plist (hides Dock icon).
5. In **Signing & Capabilities**, disable sandbox and add Hardened Runtime.
6. Archive and export with your Developer ID for direct distribution.

### iOS — TestFlight / App Store

Standard Xcode Archive → Distribute App flow. A paid Apple Developer account ($99/year) is required for TestFlight or App Store distribution.

---

## Troubleshooting

### "The operation couldn't be completed (NWError -65555 noauth)" or connection fails to start

This error means a VPN is intercepting traffic before it reaches your local network.

**Fix:**
1. **Disable VPN on both devices** before connecting. The app forces the physical WiFi interface, so any VPN that rewrites the routing table will block Bonjour discovery and TCP connections.
2. **Grant Local Network permission on iPhone:** Go to **Settings → Privacy & Security → Local Network** and make sure the toggle next to **Mac Remote** is on. iOS requires explicit permission for apps to communicate with devices on the local network.

If you need the VPN active for other reasons, split-tunnel mode (where local network traffic bypasses the VPN) may allow the app to work — check your VPN provider's settings.

---

## Privacy

- No data ever leaves your local network.
- No analytics, tracking, or telemetry of any kind.
- The PIN is stored in plain text in `UserDefaults` on both devices. For higher security, change your PIN regularly.

---

## License

MIT License — see [LICENSE](LICENSE) for details.

```
Copyright (c) 2026 Mehrdad Alemzadeh

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```



