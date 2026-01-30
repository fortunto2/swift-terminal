#if canImport(UIKit)
import UIKit

/// Custom keyboard accessory for terminal with Claude Code shortcuts.
///
/// Single row: Esc | Tab | Ctrl | ^C | ^D | arrows | "/" dropdown | "claude" dropdown
public final class ClaudeCodeAccessoryView: UIInputView {

    // MARK: - Types

    private enum KeyAction {
        case bytes([UInt8])
        case text(String)
        case ctrlToggle
        case ctrlCombo(UInt8)
    }

    // MARK: - Properties

    private let onInput: (Data) -> Void
    private var ctrlActive = false
    private var ctrlButton: UIButton?

    // MARK: - Init

    public init(onInput: @escaping (Data) -> Void) {
        self.onInput = onInput
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44),
                   inputViewStyle: .keyboard)
        self.allowsSelfSizing = true
        self.translatesAutoresizingMaskIntoConstraints = false
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Layout

    private func setupViews() {
        backgroundColor = UIColor(white: 0.12, alpha: 1)

        let keys: [UIView] = [
            makeKey("Esc", .bytes([0x1B])),
            makeKey("Tab", .bytes([0x09])),
            makeKey("Ctrl", .ctrlToggle, tint: .systemOrange),
            makeKey("^C", .ctrlCombo(0x03), tint: .systemRed),
            makeKey("^D", .ctrlCombo(0x04), tint: .systemRed),
            makeSeparator(),
            makeKey("\u{2191}", .bytes([0x1B, 0x5B, 0x41])),
            makeKey("\u{2193}", .bytes([0x1B, 0x5B, 0x42])),
            makeKey("\u{2190}", .bytes([0x1B, 0x5B, 0x44])),
            makeKey("\u{2192}", .bytes([0x1B, 0x5B, 0x43])),
            makeSeparator(),
            makeSlashMenu(),
            makeClaudeMenu(),
        ]

        let stack = UIStackView(arrangedSubviews: keys)
        stack.axis = .horizontal
        stack.spacing = 3
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        let h = heightAnchor.constraint(equalToConstant: 44)
        h.priority = .required
        h.isActive = true
    }

    // MARK: - Key Builders

    private func makeKey(_ label: String, _ action: KeyAction, tint: UIColor? = nil) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = label
        config.baseForegroundColor = .white
        config.baseBackgroundColor = tint ?? UIColor(white: 0.25, alpha: 1)
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var a = attr
            a.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)
            return a
        }

        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in
            self?.handleKey(action)
        }, for: .touchUpInside)

        if case .ctrlToggle = action {
            ctrlButton = button
        }

        return button
    }

    private func makeSeparator() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.3, alpha: 1)
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 1),
            v.heightAnchor.constraint(equalToConstant: 24),
        ])
        return v
    }

    /// "/" button that shows a dropdown of slash commands.
    private func makeSlashMenu() -> UIButton {
        let commands: [(String, String)] = [
            ("/exit", "/exit"),
            ("/compact", "/compact"),
            ("/clear", "/clear"),
            ("/help", "/help"),
            ("/status", "/status"),
            ("/review", "/review"),
            ("/cost", "/cost"),
            ("/config", "/config"),
        ]

        let menuItems = commands.map { (label, cmd) in
            UIAction(title: label, image: UIImage(systemName: "chevron.right")) { [weak self] _ in
                self?.sendText(cmd)
            }
        }

        let menu = UIMenu(title: "Claude Commands", children: menuItems)

        var config = UIButton.Configuration.filled()
        config.title = "/"
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor(white: 0.25, alpha: 1)
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var a = attr
            a.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .bold)
            return a
        }

        let button = UIButton(configuration: config)
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        return button
    }

    /// "claude" button that shows a dropdown with launch options.
    private func makeClaudeMenu() -> UIButton {
        let options: [(String, String)] = [
            ("claude", "claude"),
            ("claude --skip-permissions", "claude --dangerously-skip-permissions"),
            ("claude --continue", "claude --continue"),
            ("claude --resume", "claude --resume"),
        ]

        let menuItems = options.map { (label, cmd) in
            UIAction(title: label, image: UIImage(systemName: "brain")) { [weak self] _ in
                self?.sendText(cmd)
            }
        }

        let menu = UIMenu(title: "Launch Claude", children: menuItems)

        var config = UIButton.Configuration.filled()
        config.title = "claude"
        config.baseForegroundColor = .white
        config.baseBackgroundColor = .systemPurple
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var a = attr
            a.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)
            return a
        }

        let button = UIButton(configuration: config)
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        return button
    }

    // MARK: - Input Handling

    private func handleKey(_ action: KeyAction) {
        switch action {
        case .bytes(let bytes):
            if ctrlActive, bytes.count == 1, let byte = bytes.first {
                send([byte & 0x1F])
                deactivateCtrl()
            } else {
                send(bytes)
            }
        case .text(let string):
            sendText(string)
        case .ctrlToggle:
            ctrlActive.toggle()
            updateCtrlAppearance()
        case .ctrlCombo(let byte):
            send([byte])
            deactivateCtrl()
        }
    }

    private func sendText(_ string: String) {
        if let data = (string + "\n").data(using: .utf8) {
            onInput(data)
        }
    }

    private func send(_ bytes: [UInt8]) {
        onInput(Data(bytes))
    }

    private func deactivateCtrl() {
        if ctrlActive {
            ctrlActive = false
            updateCtrlAppearance()
        }
    }

    private func updateCtrlAppearance() {
        guard let btn = ctrlButton else { return }
        var config = btn.configuration ?? .filled()
        if ctrlActive {
            config.baseBackgroundColor = .white
            config.baseForegroundColor = .black
        } else {
            config.baseBackgroundColor = .systemOrange
            config.baseForegroundColor = .white
        }
        btn.configuration = config
    }
}
#endif
