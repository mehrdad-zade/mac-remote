# Mac Remote

An open-source iOS app that turns your iPhone into a wireless trackpad, keyboard, and remote control for your Mac — all over your local WiFi network with no cloud required.

---

## Features

- **Full-screen trackpad**: drag to move the cursor, tap to click, tap twice to double-click, two-finger drag to scroll, two-finger tap or long press to right-click
- **Stays connected**: sign in once; the app reconnects by itself after you lock and unlock your phone (Face ID) or switch apps, until you tap **Disconnect**
- **Keyboard shortcuts**: Copy, Paste, Cut, Undo, Redo, Select All, Switch App (⌘Tab), Spotlight, Mission Control, Find, New Tab, Close, Quit
- **Modifier keys**: ⌃ ⌥ ⇧ ⌘ combine with arrows, Return, Delete, Tab, Esc, Space, or any typed character (⌘C, ⌃A, ⇧→, …)
- **Volume and media**: volume down / mute / up (hold to repeat), previous / play-pause / next
- **Virtual desktop switching**: move between Mission Control Spaces
- **Wireless keyboard**: type on your iPhone's keyboard and the text appears on your Mac
- **Sleep button**: put your Mac to sleep from anywhere in the room
- **Saved machines**: remembers your Macs; PINs are kept in the iOS Keychain
- **Zero cloud**: everything stays on your local network; Bonjour auto-discovery, no IP addresses to type

---

## Requirements

| Component | Minimum version |
|-----------|----------------|
| iPhone | iOS 15+ (iPhone 6s / 2015 and newer) |
| Mac | macOS 12 Monterey or later, running [MacRemote Server](../mac-remote-server) |
| Network | Both devices on the **same WiFi network** |
| Xcode (to build) | Xcode 27+ |

---

## Mac Setup

Install **MacRemote Server** on the Mac: open `MacRemote.dmg` and run **Install MacRemote.pkg**.
The installer allows MacRemote through the firewall, sets it to start at login and opens the
**MacRemote Setup** window, which walks you through the permissions macOS asks you to approve
(Accessibility, Automation for desktop switching, Login Items) and choosing a PIN.

See the [mac-remote-server README](../mac-remote-server/README.md) for details and for building the installer.

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

1. Make sure MacRemote is running on the Mac (cursor icon in the menu bar).
2. Open **Mac Remote** on your iPhone; your Mac appears in the list within a few seconds.
3. Tap your Mac, enter the 4-digit PIN, tap **Connect**.

You stay signed in. When you lock the phone, switch apps or the Wi-Fi drops, the trackpad stays
on screen with a small **Reconnecting…** banner and the app reconnects by itself as soon as it can.
Relaunching the app also reconnects automatically. If the PIN on the Mac changes, the app asks
for the new one.

### Trackpad controls

| Gesture | Action |
|---------|--------|
| 1-finger drag | Move cursor |
| Tap | Left click |
| Tap twice quickly | Double click (three times: triple click) |
| 2-finger tap | Right click |
| Long press (~0.4s) | Right click |
| 2-finger drag | Scroll |

### Desktop navigation

Tap **‹ Desktop** or **Desktop ›** in the toolbar to switch between Mission Control Spaces.

> You need at least 2 Spaces set up (create additional desktops in Mission Control).

### Volume and media

The bar under the toolbar controls the Mac's volume (hold − or + to keep changing it) and media
playback. With an older Mac server these buttons are greyed out; update MacRemote on the Mac.

### Shortcuts

The scrolling row of buttons sends common shortcuts in one tap. **Switch App** works like
⌘Tab: tap it repeatedly within a second to move through the app switcher; it selects the
highlighted app when you stop.

### Keyboard

Tap the **keyboard** icon to bring up your iPhone's keyboard. Type text and tap send.

Above the keyboard is a row of special keys. **Ctrl**, **⌥ Alt**, **⇧ Shift** and **⌘ Cmd** are
sticky: tap one (or several), then tap a special key or type a character. For example
**⌘ Cmd** then `c` sends ⌘C, **⇧ Shift** then **→** extends a selection. The text field turns
blue while a modifier is armed.

### Sleep

Tap **moon** (🌙) in the toolbar → confirm → your Mac goes to sleep immediately.

### Disconnect

Tap **Disconnect** (⏻) in the toolbar to sign out and return to the server list. The app won't
reconnect until you sign in again.

---

## Architecture

```
iPhone (iOS app)          ←→  Mac (MacRemote Server)
────────────────               ──────────────
NWBrowser (Bonjour)   ←→     NWListener port 8080
NWConnection (TCP)    →      ClientSession (per device)
JSON messages + \n    →      InputSimulator (CGEvent)
                      →      SystemController (pmset)
```

### Message protocol

All messages are newline-terminated JSON sent over a plain TCP connection on port 8080. The full
table is in the [mac-remote-server README](../mac-remote-server/README.md#how-it-works).
The app reads `capabilities` from the auth reply and disables controls an older server doesn't
support, and it sends `ping` every few seconds to notice a dead connection quickly.

---

## Project Structure

```
mac-remote/
├── mac-remote.xcodeproj/          iOS Xcode project
└── mac-remote/                    iOS app source
    ├── mac_remoteApp.swift        App entry point
    ├── ContentView.swift          Login / Trackpad router, app lifecycle
    ├── ConnectionManager.swift    Networking, persistent session, auto-reconnect
    ├── KeychainStore.swift        PIN storage
    ├── LoginView.swift            Server discovery + PIN entry
    ├── TrackpadView.swift         Trackpad, keyboard, shortcuts, media controls
    └── Assets.xcassets/           App icon + colors
```

The Mac server lives in the separate `mac-remote-server` repository.

---

## Building for distribution

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
- On the iPhone the PIN is stored in the Keychain. On the Mac it is stored in the app's preferences.

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



