import SwiftUI
import UIKit

struct ControllerTerminalInputView: UIViewRepresentable {
    let enabled: Bool
    let focusRequest: UInt64
    let onBytes: (Data) -> Void
    let onPaste: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBytes: onBytes, onPaste: onPaste)
    }

    func makeUIView(context: Context) -> TerminalInputTextView {
        let view = TerminalInputTextView()
        view.delegate = context.coordinator
        view.commandHandler = context.coordinator
        view.backgroundColor = .clear
        view.textColor = .clear
        view.tintColor = .clear
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.smartInsertDeleteType = .no
        view.keyboardType = .asciiCapable
        view.returnKeyType = .default
        view.isScrollEnabled = false
        view.accessibilityLabel = "Terminal keyboard input"
        view.inputAccessoryView = context.coordinator.makeAccessory(for: view)
        return view
    }

    func updateUIView(_ view: TerminalInputTextView, context: Context) {
        context.coordinator.onBytes = onBytes
        context.coordinator.onPaste = onPaste
        view.isEditable = enabled
        view.isUserInteractionEnabled = enabled
        if enabled, context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if !enabled, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, TerminalInputCommandHandling {
        var onBytes: (Data) -> Void
        var onPaste: (String) -> Void
        var focusRequest: UInt64 = 0
        private var controlLatched = false
        private var optionLatched = false
        private weak var controlButton: UIButton?
        private weak var optionButton: UIButton?

        init(onBytes: @escaping (Data) -> Void, onPaste: @escaping (String) -> Void) {
            self.onBytes = onBytes
            self.onPaste = onPaste
        }

        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil, !textView.text.isEmpty else { return }
            sendText(textView.text)
            textView.text = ""
        }

        func terminalInput(_ input: TerminalInputCommand) {
            switch input {
            case .bytes(let bytes):
                onBytes(Data(bytes))
            case .paste(let text):
                onPaste(text)
            case .toggleControl:
                controlLatched.toggle()
                updateModifierButtons()
            case .toggleOption:
                optionLatched.toggle()
                updateModifierButtons()
            }
        }

        func sendText(_ text: String) {
            var bytes = Data()
            for scalar in text.unicodeScalars {
                let value = String(scalar)
                if controlLatched,
                   scalar.value < 128,
                   let control = Self.controlByte(UInt8(scalar.value)) {
                    bytes.append(control)
                } else {
                    if optionLatched { bytes.append(0x1B) }
                    bytes.append(contentsOf: value.utf8)
                }
            }
            controlLatched = false
            optionLatched = false
            updateModifierButtons()
            if !bytes.isEmpty { onBytes(bytes) }
        }

        func makeAccessory(for textView: TerminalInputTextView) -> UIView {
            let accessory = UIInputView(frame: .zero, inputViewStyle: .keyboard)
            accessory.translatesAutoresizingMaskIntoConstraints = false
            accessory.heightAnchor.constraint(equalToConstant: 52).isActive = true
            let scroll = UIScrollView()
            scroll.showsHorizontalScrollIndicator = false
            scroll.translatesAutoresizingMaskIntoConstraints = false
            accessory.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: accessory.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: accessory.bottomAnchor),
            ])
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            row.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
                row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
                row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            ])

            row.addArrangedSubview(button("Esc", command: .bytes([0x1B]), textView: textView))
            let control = button("Ctrl", command: .toggleControl, textView: textView)
            let option = button("Alt", command: .toggleOption, textView: textView)
            controlButton = control
            optionButton = option
            row.addArrangedSubview(control)
            row.addArrangedSubview(option)
            row.addArrangedSubview(button("Tab", command: .bytes([0x09]), textView: textView))
            row.addArrangedSubview(button("←", command: .bytes([0x1B, 0x5B, 0x44]), textView: textView, label: "Left arrow"))
            row.addArrangedSubview(button("↑", command: .bytes([0x1B, 0x5B, 0x41]), textView: textView, label: "Up arrow"))
            row.addArrangedSubview(button("↓", command: .bytes([0x1B, 0x5B, 0x42]), textView: textView, label: "Down arrow"))
            row.addArrangedSubview(button("→", command: .bytes([0x1B, 0x5B, 0x43]), textView: textView, label: "Right arrow"))
            return accessory
        }

        private func button(
            _ title: String,
            command: TerminalInputCommand,
            textView: TerminalInputTextView,
            label: String? = nil
        ) -> UIButton {
            var configuration = UIButton.Configuration.tinted()
            configuration.title = title
            configuration.cornerStyle = .small
            let button = UIButton(configuration: configuration)
            button.accessibilityLabel = label ?? title
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            button.addAction(UIAction { [weak textView] _ in
                textView?.commandHandler?.terminalInput(command)
                textView?.becomeFirstResponder()
            }, for: .touchUpInside)
            return button
        }

        private func updateModifierButtons() {
            controlButton?.isSelected = controlLatched
            optionButton?.isSelected = optionLatched
            controlButton?.configuration?.baseBackgroundColor = controlLatched ? .systemGreen : nil
            optionButton?.configuration?.baseBackgroundColor = optionLatched ? .systemGreen : nil
        }

        private static func controlByte(_ value: UInt8) -> UInt8? {
            let upper = (0x61...0x7A).contains(value) ? value - 0x20 : value
            guard (0x40...0x5F).contains(upper) else { return nil }
            return upper & 0x1F
        }
    }
}

@MainActor
protocol TerminalInputCommandHandling: AnyObject {
    func terminalInput(_ input: TerminalInputCommand)
}

enum TerminalInputCommand {
    case bytes([UInt8])
    case paste(String)
    case toggleControl
    case toggleOption
}

@MainActor
final class TerminalInputTextView: UITextView {
    weak var commandHandler: TerminalInputCommandHandling?

    override func deleteBackward() {
        if text.isEmpty, markedTextRange == nil {
            commandHandler?.terminalInput(.bytes([0x7F]))
        } else {
            super.deleteBackward()
        }
    }

    override func paste(_ sender: Any?) {
        guard let value = UIPasteboard.general.string, !value.isEmpty else { return }
        commandHandler?.terminalInput(.paste(value))
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            key(UIKeyCommand.inputEscape, bytes: [0x1B], title: "Escape"),
            key("\t", bytes: [0x09], title: "Tab"),
            key(UIKeyCommand.inputUpArrow, bytes: [0x1B, 0x5B, 0x41], title: "Up"),
            key(UIKeyCommand.inputDownArrow, bytes: [0x1B, 0x5B, 0x42], title: "Down"),
            key(UIKeyCommand.inputLeftArrow, bytes: [0x1B, 0x5B, 0x44], title: "Left"),
            key(UIKeyCommand.inputRightArrow, bytes: [0x1B, 0x5B, 0x43], title: "Right"),
        ]
    }

    @objc private func runKeyCommand(_ command: UIKeyCommand) {
        guard let data = command.propertyList as? Data else { return }
        commandHandler?.terminalInput(.bytes(Array(data)))
    }

    private func key(_ input: String, bytes: [UInt8], title: String) -> UIKeyCommand {
        let command = UIKeyCommand(
            title: title,
            action: #selector(runKeyCommand(_:)),
            input: input,
            modifierFlags: [],
            propertyList: Data(bytes)
        )
        command.wantsPriorityOverSystemBehavior = true
        return command
    }
}
