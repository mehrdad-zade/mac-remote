import SwiftUI
import UIKit

struct TrackpadView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager

    @State private var showKeyboard = false
    @State private var showSleepConfirm = false
    @State private var showDisconnectConfirm = false
    @State private var showQuitConfirm = false
    @State private var ripplePosition: CGPoint = .zero
    @State private var showRipple = false
    @State private var rippleOpacity = 0.0
    @State private var activeModifiers: Set<Int> = []
    @State private var draftText = ""
    @State private var textFieldId = UUID()
    @FocusState private var keyboardFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ambientOrbs

            VStack(spacing: 0) {
                controlBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                mediaBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                shortcutsRow

                if showKeyboard {
                    specialKeysRow
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Trackpad surface
                ZStack {
                    trackpadBackground

                    TrackpadSurface(
                        onMove: { dx, dy in connectionManager.sendMove(dx: dx, dy: dy) },
                        onTap: { pos in handleTap(at: pos) },
                        onRightClick: { connectionManager.sendRightClick() },
                        onScroll: { dx, dy in connectionManager.sendScroll(dx: dx, dy: dy) }
                    )

                    if showRipple {
                        Circle()
                            .strokeBorder(Color.blue.opacity(rippleOpacity), lineWidth: 1.5)
                            .frame(width: 60, height: 60)
                            .position(ripplePosition)
                            .allowsHitTesting(false)
                    }

                    VStack(spacing: 8) {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundStyle(.white.opacity(0.35))
                        Text("Drag to move  •  Tap to click  •  Tap twice to double-click\nTwo fingers to scroll  •  Two-finger tap or hold to right-click")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                    }
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if !connectionManager.isOnline {
                        reconnectingPill
                            .padding(.top, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: connectionManager.isOnline)
            }
        }
        .ignoresSafeArea(.keyboard)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showKeyboard {
                textInputBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: keyboardFocused) { focused in
            if !focused {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    showKeyboard = false
                    activeModifiers.removeAll()
                }
            }
        }
        .onChange(of: draftText) { newValue in
            sendModifiedCharacterIfNeeded(newValue)
        }
        .confirmationDialog("Put Mac to Sleep?", isPresented: $showSleepConfirm, titleVisibility: .visible) {
            Button("Sleep", role: .destructive) {
                connectionManager.sendSleep()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Mac will go to sleep immediately.")
        }
        .confirmationDialog("Disconnect from \(connectionManager.connectedServerName)?",
                            isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                connectionManager.logout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to pick your Mac again to reconnect.")
        }
        .confirmationDialog("Quit the frontmost app?", isPresented: $showQuitConfirm, titleVisibility: .visible) {
            Button("Quit (⌘Q)", role: .destructive) {
                connectionManager.sendKeypress("q", modifiers: [Modifier.command])
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Control bar (top)

    private var controlBar: some View {
        HStack(spacing: 0) {
            // Keyboard toggle — haptic: medium
            toolbarButton(
                icon: showKeyboard ? "keyboard.chevron.compact.down" : "keyboard",
                label: showKeyboard ? "Hide" : "Keyboard",
                color: showKeyboard ? .blue : .white
            ) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let opening = !showKeyboard
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    showKeyboard = opening
                }
                if opening {
                    keyboardFocused = true
                } else {
                    keyboardFocused = false
                    draftText = ""
                    activeModifiers.removeAll()
                }
            }

            toolbarDivider

            // Sleep — haptic: heavy
            toolbarButton(icon: "moon.fill", label: "Sleep", color: .white) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                showSleepConfirm = true
            }

            toolbarDivider

            // Switch space left
            toolbarButton(icon: "chevron.left", label: "Desktop", color: .white) {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                connectionManager.sendSwitchSpace(left: true)
            }

            toolbarDivider

            // Switch space right
            toolbarButton(icon: "chevron.right", label: "Desktop", color: .white) {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                connectionManager.sendSwitchSpace(left: false)
            }

            toolbarDivider

            // Disconnect (sign out) — ends the persistent session
            toolbarButton(icon: "power", label: "Disconnect", color: .red) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showDisconnectConfirm = true
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 0.5, height: 28)
            .padding(.horizontal, 4)
    }

    private func toolbarButton(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 22)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Volume & media bar

    private var mediaBar: some View {
        let available = connectionManager.supports("volume")

        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                RepeatingButton(icon: "speaker.minus.fill") { connectionManager.sendVolume(.down) }
                MediaButton(icon: "speaker.slash.fill") { connectionManager.sendVolume(.mute) }
                RepeatingButton(icon: "speaker.plus.fill") { connectionManager.sendVolume(.up) }

                toolbarDivider

                MediaButton(icon: "backward.fill") { connectionManager.sendMedia(.previous) }
                MediaButton(icon: "playpause.fill") { connectionManager.sendMedia(.playPause) }
                MediaButton(icon: "forward.fill") { connectionManager.sendMedia(.next) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .disabled(!available)
            .opacity(available ? 1 : 0.35)

            if !available && connectionManager.isOnline {
                Text("Update MacRemote on your Mac to use volume and media controls.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Shortcuts row

    private var shortcutsRow: some View {
        let available = connectionManager.supports("modifiers")

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shortcuts) { shortcut in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        perform(shortcut)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: shortcut.icon)
                                .font(.system(size: 12, weight: .medium))
                            Text(shortcut.label)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .disabled(!available)
        .opacity(available ? 1 : 0.35)
    }

    private func perform(_ shortcut: Shortcut) {
        switch shortcut.action {
        case .character(let char, let modifiers):
            connectionManager.sendKeypress(char, modifiers: modifiers)
        case .keyCode(let code, let modifiers):
            connectionManager.sendKeyCode(code, modifiers: modifiers)
        case .appSwitcher:
            connectionManager.sendAppSwitcher()
        case .confirmQuit:
            showQuitConfirm = true
        }
    }

    // Characters are sent (not key codes) so the Mac maps them through its own
    // keyboard layout, e.g. ⌘Z still undoes on a German keyboard.
    private let shortcuts: [Shortcut] = [
        Shortcut(label: "Copy",       icon: "doc.on.doc",           action: .character("c", [Modifier.command])),
        Shortcut(label: "Paste",      icon: "doc.on.clipboard",     action: .character("v", [Modifier.command])),
        Shortcut(label: "Cut",        icon: "scissors",             action: .character("x", [Modifier.command])),
        Shortcut(label: "Undo",       icon: "arrow.uturn.backward", action: .character("z", [Modifier.command])),
        Shortcut(label: "Redo",       icon: "arrow.uturn.forward",  action: .character("z", [Modifier.command, Modifier.shift])),
        Shortcut(label: "Select All", icon: "selection.pin.in.out", action: .character("a", [Modifier.command])),
        Shortcut(label: "Switch App", icon: "square.on.square",     action: .appSwitcher),
        Shortcut(label: "Spotlight",  icon: "magnifyingglass",      action: .keyCode(49, [Modifier.command])),
        Shortcut(label: "Mission Control", icon: "rectangle.3.group", action: .keyCode(126, [Modifier.control])),
        Shortcut(label: "Find",       icon: "text.magnifyingglass", action: .character("f", [Modifier.command])),
        Shortcut(label: "New Tab",    icon: "plus.square.on.square", action: .character("t", [Modifier.command])),
        Shortcut(label: "Close",      icon: "xmark.square",         action: .character("w", [Modifier.command])),
        Shortcut(label: "Quit",       icon: "power",                action: .confirmQuit),
    ]

    // MARK: - Special keys row (shown above system keyboard)

    private var specialKeysRow: some View {
        let modifiersAvailable = connectionManager.supports("modifiers")

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(specialKeys, id: \.label) { key in
                    SpecialKeyButton(
                        key: key,
                        isActive: activeModifiers.contains(key.keyCode),
                        onTap: handleSpecialKey
                    )
                    .disabled(key.isModifier && !modifiersAvailable)
                    .opacity(key.isModifier && !modifiersAvailable ? 0.35 : 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func handleSpecialKey(_ key: SpecialKey) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if key.isModifier {
            if activeModifiers.contains(key.keyCode) {
                activeModifiers.remove(key.keyCode)
            } else {
                activeModifiers.insert(key.keyCode)
            }
        } else {
            connectionManager.sendKeyCode(key.keyCode, modifiers: activeModifiers.sorted())
            activeModifiers.removeAll()
        }
    }

    // MARK: - Text input bar

    private var textInputBar: some View {
        HStack(spacing: 10) {
            draftField
                .focused($keyboardFocused)
                .id(textFieldId)
                .font(.body)
                .foregroundStyle(.white)
                .tint(.blue)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
                    activeModifiers.isEmpty ? Color.white.opacity(0.12) : Color.blue.opacity(0.7),
                    lineWidth: activeModifiers.isEmpty ? 0.5 : 1.5
                ))
                .onSubmit { sendDraftText() }

            Button(action: sendDraftText) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(draftText.isEmpty ? Color.white.opacity(0.25) : Color.blue)
            }
            .buttonStyle(.plain)
            .disabled(draftText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var draftField: some View {
        let placeholder = activeModifiers.isEmpty
            ? "Type a message…"
            : "Type a key for \(modifierSymbols)…"
        if #available(iOS 16.0, *) {
            TextField(placeholder, text: $draftText, axis: .vertical)
                .lineLimit(1...5)
        } else {
            TextField(placeholder, text: $draftText)
        }
    }

    private var modifierSymbols: String {
        let order = [Modifier.control, Modifier.option, Modifier.shift, Modifier.command]
        let symbols = [Modifier.control: "⌃", Modifier.option: "⌥", Modifier.shift: "⇧", Modifier.command: "⌘"]
        return order.filter(activeModifiers.contains).compactMap { symbols[$0] }.joined()
    }

    /// With a modifier armed (e.g. ⌘), the next typed character is sent right away
    /// as a shortcut (⌘C, ⌃A, …) instead of going into the draft.
    private func sendModifiedCharacterIfNeeded(_ text: String) {
        guard !activeModifiers.isEmpty, let char = text.last else { return }
        connectionManager.sendKeypress(String(char), modifiers: activeModifiers.sorted())
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        activeModifiers.removeAll()
        draftText = ""
    }

    private func sendDraftText() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        draftText = ""
        textFieldId = UUID()
        guard !text.isEmpty else { return }
        connectionManager.sendKeypress(text)
        // Re-focus on next run loop after the TextField reinitialises
        Task { @MainActor in
            keyboardFocused = true
        }
    }

    private let specialKeys: [SpecialKey] = [
        SpecialKey(label: "Ctrl",    icon: nil, keyCode: Modifier.control, isModifier: true),
        SpecialKey(label: "⌥ Alt",   icon: nil, keyCode: Modifier.option,  isModifier: true),
        SpecialKey(label: "⇧ Shift", icon: nil, keyCode: Modifier.shift,   isModifier: true),
        SpecialKey(label: "⌘ Cmd",   icon: nil, keyCode: Modifier.command, isModifier: true),
        SpecialKey(label: "←",       icon: "arrow.left",  keyCode: 123),
        SpecialKey(label: "→",       icon: "arrow.right", keyCode: 124),
        SpecialKey(label: "↑",       icon: "arrow.up",    keyCode: 126),
        SpecialKey(label: "↓",       icon: "arrow.down",  keyCode: 125),
        SpecialKey(label: "Return",  icon: "return",      keyCode: 36),
        SpecialKey(label: "Delete",  icon: "delete.left", keyCode: 51),
        SpecialKey(label: "Fwd Del", icon: "delete.right", keyCode: 117),
        SpecialKey(label: "Space",   icon: nil, keyCode: 49),
        SpecialKey(label: "Tab",     icon: nil, keyCode: 48),
        SpecialKey(label: "Esc",     icon: nil, keyCode: 53),
    ]

    // MARK: - Reconnecting indicator

    private var reconnectingPill: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.8)
            Text("Reconnecting to \(connectionManager.connectedServerName)…")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
        .allowsHitTesting(false)
    }

    // MARK: - Trackpad background

    private var trackpadBackground: some View {
        Rectangle()
            .fill(Color.white.opacity(0.03))
            .overlay(
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }

    // MARK: - Tap ripple

    private func handleTap(at point: CGPoint) {
        connectionManager.sendTap()
        ripplePosition = point
        showRipple = true
        rippleOpacity = 0.7
        withAnimation(.easeOut(duration: 0.4)) {
            rippleOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            showRipple = false
        }
    }

    // MARK: - Ambient orbs

    private var ambientOrbs: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.blue.opacity(0.3), .clear],
                                     center: .center, startRadius: 0, endRadius: 200))
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: -150, y: -400)

            Circle()
                .fill(RadialGradient(colors: [.purple.opacity(0.25), .clear],
                                     center: .center, startRadius: 0, endRadius: 180))
                .frame(width: 360, height: 360)
                .blur(radius: 70)
                .offset(x: 180, y: 200)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - TrackpadSurface (UIViewRepresentable)

struct TrackpadSurface: UIViewRepresentable {
    var onMove: (CGFloat, CGFloat) -> Void
    var onTap: (CGPoint) -> Void
    var onRightClick: () -> Void
    var onScroll: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let singlePan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSinglePan(_:))
        )
        singlePan.minimumNumberOfTouches = 1
        singlePan.maximumNumberOfTouches = 1
        singlePan.delegate = context.coordinator

        let doublePan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoublePan(_:))
        )
        doublePan.minimumNumberOfTouches = 2
        doublePan.maximumNumberOfTouches = 2
        doublePan.delegate = context.coordinator

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.numberOfTouchesRequired = 1
        tap.require(toFail: singlePan)

        // Two-finger tap → right-click, like a Mac trackpad.
        let twoFingerTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTwoFingerTap(_:))
        )
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.require(toFail: doublePan)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.4

        view.addGestureRecognizer(singlePan)
        view.addGestureRecognizer(doublePan)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(twoFingerTap)
        view.addGestureRecognizer(longPress)

        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onMove = onMove
        context.coordinator.onTap = onTap
        context.coordinator.onRightClick = onRightClick
        context.coordinator.onScroll = onScroll
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onMove: onMove, onTap: onTap, onRightClick: onRightClick, onScroll: onScroll)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onMove: (CGFloat, CGFloat) -> Void
        var onTap: (CGPoint) -> Void
        var onRightClick: () -> Void
        var onScroll: (CGFloat, CGFloat) -> Void
        weak var view: UIView?

        init(
            onMove: @escaping (CGFloat, CGFloat) -> Void,
            onTap: @escaping (CGPoint) -> Void,
            onRightClick: @escaping () -> Void,
            onScroll: @escaping (CGFloat, CGFloat) -> Void
        ) {
            self.onMove = onMove
            self.onTap = onTap
            self.onRightClick = onRightClick
            self.onScroll = onScroll
        }

        @objc func handleSinglePan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .changed else { return }
            let translation = recognizer.translation(in: recognizer.view)
            recognizer.setTranslation(.zero, in: recognizer.view)
            onMove(translation.x * 1.5, translation.y * 1.5)
        }

        @objc func handleDoublePan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .changed else { return }
            let translation = recognizer.translation(in: recognizer.view)
            recognizer.setTranslation(.zero, in: recognizer.view)
            onScroll(translation.x * 3, translation.y * 3)
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let location = recognizer.location(in: recognizer.view)
            onTap(location)
        }

        @objc func handleTwoFingerTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onRightClick()
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            // Haptic: heavy impact for right-click
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            onRightClick()
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}

// MARK: - Key models

/// macOS virtual key codes of the modifier keys, as the server expects them.
private enum Modifier {
    static let command = 55
    static let shift = 56
    static let option = 58
    static let control = 59
}

private struct Shortcut: Identifiable {
    enum Action {
        case character(String, [Int])
        case keyCode(Int, [Int])
        case appSwitcher
        case confirmQuit
    }

    var id: String { label }
    let label: String
    let icon: String
    let action: Action
}

// MARK: - Special key model + button (extracted to help type-checker)

private struct SpecialKey {
    let label: String
    let icon: String?
    let keyCode: Int
    var isModifier: Bool = false
}

private struct SpecialKeyButton: View {
    let key: SpecialKey
    let isActive: Bool
    let onTap: (SpecialKey) -> Void

    var body: some View {
        Button { onTap(key) } label: {
            keyLabel
                .foregroundStyle(isActive ? Color.black : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(
                    isActive ? Color.clear : Color.white.opacity(0.15),
                    lineWidth: 0.5
                ))
                .animation(.easeInOut(duration: 0.15), value: isActive)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var keyLabel: some View {
        if let icon = key.icon {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
        } else {
            Text(key.label)
                .font(.system(size: 13, weight: .medium))
        }
    }
}

// MARK: - Media buttons

private struct MediaButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Fires once on touch-down, then repeats while held (for volume up/down).
private struct RepeatingButton: View {
    let icon: String
    let action: () -> Void

    @State private var isPressed = false
    @State private var timer: Timer?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled, !isPressed else { return }
                        isPressed = true
                        fire()
                        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                            timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                                fire()
                            }
                        }
                    }
                    .onEnded { _ in stop() }
            )
            .onDisappear { stop() }
    }

    private func fire() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        action()
    }

    private func stop() {
        isPressed = false
        timer?.invalidate()
        timer = nil
    }
}
