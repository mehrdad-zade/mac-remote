import SwiftUI
import UIKit

// MARK: - Custom UITextField that intercepts all key input

final class RemoteKeyboardField: UITextField {
    var onKeyInput: ((String) -> Void)?

    // Always report hasText = true so deleteBackward fires even when text field is empty
    override var hasText: Bool { true }

    override func insertText(_ text: String) {
        onKeyInput?(text)
        // Do NOT call super — we don't want visible text in the field
    }

    override func deleteBackward() {
        onKeyInput?("\u{08}") // ASCII backspace
    }
}

// MARK: - UIViewRepresentable wrapper

struct KeyboardCapture: UIViewRepresentable {
    var isActive: Bool
    var onCharacters: (String) -> Void
    var onSpecialKey: (Int) -> Void

    func makeUIView(context: Context) -> RemoteKeyboardField {
        let field = RemoteKeyboardField()
        field.onKeyInput = context.coordinator.handleKey
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.keyboardType = .default
        field.returnKeyType = .default
        field.backgroundColor = .clear
        return field
    }

    func updateUIView(_ uiView: RemoteKeyboardField, context: Context) {
        context.coordinator.onCharacters = onCharacters
        context.coordinator.onSpecialKey = onSpecialKey
        uiView.onKeyInput = context.coordinator.handleKey

        if isActive && !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isActive && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCharacters: onCharacters, onSpecialKey: onSpecialKey)
    }

    // macOS virtual key codes for special keys
    final class Coordinator: NSObject {
        var onCharacters: (String) -> Void
        var onSpecialKey: (Int) -> Void

        init(onCharacters: @escaping (String) -> Void, onSpecialKey: @escaping (Int) -> Void) {
            self.onCharacters = onCharacters
            self.onSpecialKey = onSpecialKey
        }

        func handleKey(_ text: String) {
            switch text {
            case "\u{08}": onSpecialKey(51) // Delete / Backspace
            case "\n":     onSpecialKey(36) // Return
            case "\t":     onSpecialKey(48) // Tab
            case "\u{1B}": onSpecialKey(53) // Escape
            default:       onCharacters(text)
            }
        }
    }
}
