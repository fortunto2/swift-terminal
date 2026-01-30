#if canImport(UIKit)
import UIKit
import SwiftTerm

/// Keyboard accessory bar for the terminal with Claude Code additions.
///
/// Modeled after SwiftTerm's `TerminalAccessory` layout with dynamic width,
/// auto-repeat arrows, input click sounds, and Claude-specific menus.
///
/// ```
/// Esc │ Ctrl │ Tab │ ~ │ | │ / │ - │ F1..Fn │ ↑ ↓ ← → │ ⌨ │ claude
/// ```
public final class ClaudeCodeAccessoryView: UIInputView, UIInputViewAudioFeedback {

    // MARK: - Properties

    public weak var terminalView: SwiftTerm.TerminalView?

    /// Whether the Ctrl modifier is active (sticky toggle).
    public var controlModifier: Bool = false {
        didSet { controlButton?.isSelected = controlModifier }
    }

    private var controlButton: UIButton?
    private var keyboardButton: UIButton?

    /// All managed subviews (for teardown on rebuild).
    private var allViews: [UIView] = []
    private var leftViews: [UIView] = []
    private var floatViews: [UIView] = []
    private var rightViews: [UIView] = []

    // Auto-repeat state
    private var repeatCommand: (() -> Void)?
    private var repeatTimer: Timer?
    private var repeatTask: Task<Void, Never>?

    private let buttonPad: CGFloat = 4

    // MARK: - UIInputViewAudioFeedback

    public var enableInputClicksWhenVisible: Bool { true }

    // MARK: - Init

    public init(terminalView: SwiftTerm.TerminalView) {
        self.terminalView = terminalView
        let width = UIScreen.main.bounds.width
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: 44),
                   inputViewStyle: .keyboard)
        allowsSelfSizing = true
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Rebuild on bounds change

    public override var bounds: CGRect {
        didSet {
            if oldValue.size != bounds.size {
                setupUI()
            }
        }
    }

    // MARK: - Setup UI (dynamic layout)

    private func setupUI() {
        // Tear down previous views
        for v in allViews { v.removeFromSuperview() }
        allViews.removeAll()
        leftViews.removeAll()
        floatViews.removeAll()
        rightViews.removeAll()

        backgroundColor = UIColor(white: 0.12, alpha: 1)

        let useSmall = frame.width < 380

        // --- Left group: Esc, Ctrl, Tab ---
        if useSmall {
            leftViews.append(makeButton("", #selector(escAction), icon: "escape", isDark: true))
            let ctrl = makeButton("", #selector(ctrlAction), icon: "control", isDark: true)
            leftViews.append(ctrl)
            controlButton = ctrl
            leftViews.append(makeButton("", #selector(tabAction), icon: "arrow.right.to.line.compact", isDark: true))
        } else {
            leftViews.append(makeButton("Esc", #selector(escAction), isDark: true))
            let ctrl = makeButton("Ctrl", #selector(ctrlAction), isDark: true)
            leftViews.append(ctrl)
            controlButton = ctrl
            leftViews.append(makeButton("", #selector(tabAction), icon: "arrow.right.to.line.compact", isDark: true))
        }

        // --- Right group: ← ↑ ↓ → ⌨ claude ---
        rightViews.append(makeAutoRepeatButton("arrow.left", #selector(leftAction)))
        rightViews.append(makeAutoRepeatButton("arrow.up", #selector(upAction)))
        rightViews.append(makeAutoRepeatButton("arrow.down", #selector(downAction)))
        rightViews.append(makeAutoRepeatButton("arrow.right", #selector(rightAction)))

        keyboardButton = makeButton("", #selector(toggleKeyboardAction),
                                    icon: "keyboard.chevron.compact.down", isDark: true)
        rightViews.append(keyboardButton!)

        rightViews.append(makeClaudeMenuButton())

        // --- Calculate widths ---
        let minWidth: CGFloat = useSmall ? 20 : (UIDevice.current.userInterfaceIdiom == .phone ? 22 : 32)

        // Size left/right views
        let importantCount: CGFloat = CGFloat(leftViews.count + rightViews.count)
        let maxFuncWidth = (minWidth + buttonPad) * 10
        let maxImportantSpace = frame.width - maxFuncWidth - buttonPad
        let extraPerKey: CGFloat = maxImportantSpace > 0 ? maxImportantSpace / importantCount : 0

        func sizeView(_ view: UIView, important: Bool) {
            view.sizeToFit()
            if useSmall {
                view.frame.size = CGSize(width: 20, height: view.frame.height)
            }
            let targetWidth = important ? max(extraPerKey, minWidth) : minWidth
            if view.frame.width < targetWidth {
                view.frame = CGRect(origin: view.frame.origin,
                                    size: CGSize(width: targetWidth, height: frame.height - 8))
            }
        }

        leftViews.forEach { sizeView($0, important: true) }
        rightViews.forEach { sizeView($0, important: true) }
        let fixedSpace = (leftViews + rightViews).reduce(0.0) { $0 + $1.frame.width + buttonPad }

        // --- Float group: ~ | / - F1..F10 ---
        floatViews.append(makeButton("~", #selector(tildeAction)))
        floatViews.append(makeButton("|", #selector(pipeAction)))
        floatViews.append(makeSlashMenuButton())
        floatViews.append(makeButton("-", #selector(dashAction)))

        floatViews.forEach { sizeView($0, important: true) }
        let floatFixedSpace = floatViews.reduce(fixedSpace) { $0 + $1.frame.width + buttonPad }

        // Add F-keys if space allows
        var remaining = frame.width - floatFixedSpace
        if UIDevice.current.userInterfaceIdiom == .phone && frame.width > 500 {
            remaining -= 50
        }

        let fKeySelectors: [(String, Selector)] = [
            ("F1", #selector(f1Action)), ("F2", #selector(f2Action)),
            ("F3", #selector(f3Action)), ("F4", #selector(f4Action)),
            ("F5", #selector(f5Action)), ("F6", #selector(f6Action)),
            ("F7", #selector(f7Action)), ("F8", #selector(f8Action)),
            ("F9", #selector(f9Action)), ("F10", #selector(f10Action)),
        ]
        for (title, sel) in fKeySelectors {
            remaining -= minWidth + buttonPad
            if remaining > 0 {
                let btn = makeButton(title, sel)
                floatViews.append(btn)
            }
        }

        // Size the F-key (non-important) float views
        let fKeyStart = 4 // first 4 are ~, |, /, -
        for i in fKeyStart..<floatViews.count {
            sizeView(floatViews[i], important: false)
        }

        // --- Add all views ---
        allViews.append(contentsOf: leftViews)
        allViews.append(contentsOf: floatViews)
        allViews.append(contentsOf: rightViews)

        for v in allViews {
            addSubview(v)
        }

        layoutSubviews()
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        let dh = allViews.reduce(CGFloat(0)) { max($0, $1.frame.size.height) }

        // Left + float: flow from left
        var x: CGFloat = 2
        for view in leftViews + floatViews {
            let w = view.frame.size.width
            view.frame = CGRect(x: x, y: 4, width: w, height: dh)
            x += w + buttonPad
        }

        // Right: flow from right
        var rx = frame.width - 2
        for view in rightViews.reversed() {
            let w = view.frame.size.width
            view.frame = CGRect(x: rx - w, y: 4, width: w, height: dh)
            rx -= w + buttonPad
        }
    }

    // MARK: - Button Builders

    private func makeButton(_ title: String, _ action: Selector,
                            icon: String = "", isDark: Bool = false) -> UIButton {
        let useSmall = frame.width < 380
        let b = HighlightButton(type: .roundedRect)
        b.layer.cornerRadius = 5
        b.layer.masksToBounds = true
        b.addTarget(self, action: action, for: .touchDown)
        b.setTitle(title, for: .normal)

        let bgColor = isDark ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.30, alpha: 1)
        b.normalColor = bgColor
        b.backgroundColor = bgColor
        b.setTitleColor(.white, for: .normal)
        b.setTitleColor(.white, for: .selected)

        if useSmall {
            b.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        } else {
            b.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        }

        if !icon.isEmpty {
            if let img = UIImage(systemName: icon,
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 14)) {
                b.setImage(img.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
            }
        }
        return b
    }

    private func makeAutoRepeatButton(_ iconName: String, _ action: Selector) -> UIButton {
        let b = makeButton("", action, icon: iconName)
        b.addTarget(self, action: #selector(cancelRepeatTimer), for: .touchUpOutside)
        b.addTarget(self, action: #selector(cancelRepeatTimer), for: .touchCancel)
        b.addTarget(self, action: #selector(cancelRepeatTimer), for: .touchUpInside)
        return b
    }

    /// "/" button with a dropdown menu of Claude slash commands.
    private func makeSlashMenuButton() -> UIButton {
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
                self?.clickAndSendText(cmd)
            }
        }

        let b = makeButton("/", #selector(noop))
        b.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .bold)
        b.menu = UIMenu(title: "Claude Commands", children: menuItems)
        b.showsMenuAsPrimaryAction = true
        // Remove touchDown target since menu handles interaction
        b.removeTarget(self, action: #selector(noop), for: .touchDown)
        return b
    }

    /// "claude" button with a dropdown menu for launching Claude.
    private func makeClaudeMenuButton() -> UIButton {
        let options: [(String, String)] = [
            ("claude", "claude"),
            ("claude --skip-permissions", "claude --dangerously-skip-permissions"),
            ("claude --continue", "claude --continue"),
            ("claude --resume", "claude --resume"),
        ]

        let menuItems = options.map { (label, cmd) in
            UIAction(title: label, image: UIImage(systemName: "brain")) { [weak self] _ in
                self?.clickAndSendText(cmd)
            }
        }

        let b = makeButton("claude", #selector(noop), isDark: true)
        if let hb = b as? HighlightButton {
            hb.normalColor = .systemPurple
        }
        b.backgroundColor = .systemPurple
        b.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        b.menu = UIMenu(title: "Launch Claude", children: menuItems)
        b.showsMenuAsPrimaryAction = true
        b.removeTarget(self, action: #selector(noop), for: .touchDown)
        return b
    }

    @objc private func noop() {}

    // MARK: - Key Actions

    private func clickAndSend(_ bytes: [UInt8]) {
        UIDevice.current.playInputClick()
        if controlModifier, bytes.count == 1, let b = bytes.first {
            // Apply Ctrl modifier: byte & 0x1F
            terminalView?.send([b & 0x1F])
            controlModifier = false
        } else {
            terminalView?.send(bytes)
        }
    }

    private func clickAndSendText(_ text: String) {
        UIDevice.current.playInputClick()
        let bytes = Array((text + "\n").utf8)
        terminalView?.send(bytes)
    }

    @objc private func escAction() { clickAndSend([0x1B]) }
    @objc private func tabAction() { clickAndSend([0x09]) }
    @objc private func tildeAction() { clickAndSend([UInt8(ascii: "~")]) }
    @objc private func pipeAction() { clickAndSend([UInt8(ascii: "|")]) }
    @objc private func dashAction() { clickAndSend([UInt8(ascii: "-")]) }

    @objc private func f1Action()  { clickAndSend(EscapeSequences.cmdF[0]) }
    @objc private func f2Action()  { clickAndSend(EscapeSequences.cmdF[1]) }
    @objc private func f3Action()  { clickAndSend(EscapeSequences.cmdF[2]) }
    @objc private func f4Action()  { clickAndSend(EscapeSequences.cmdF[3]) }
    @objc private func f5Action()  { clickAndSend(EscapeSequences.cmdF[4]) }
    @objc private func f6Action()  { clickAndSend(EscapeSequences.cmdF[5]) }
    @objc private func f7Action()  { clickAndSend(EscapeSequences.cmdF[6]) }
    @objc private func f8Action()  { clickAndSend(EscapeSequences.cmdF[7]) }
    @objc private func f9Action()  { clickAndSend(EscapeSequences.cmdF[8]) }
    @objc private func f10Action() { clickAndSend(EscapeSequences.cmdF[9]) }

    @objc private func ctrlAction() {
        UIDevice.current.playInputClick()
        controlModifier.toggle()
    }

    // MARK: - Arrow Keys (auto-repeat)

    private func sendArrow(app: [UInt8], normal: [UInt8]) {
        let appCursor = terminalView?.getTerminal().applicationCursor ?? false
        terminalView?.send(appCursor ? app : normal)
    }

    @objc private func upAction() {
        startRepeat { [weak self] in
            self?.sendArrow(app: EscapeSequences.moveUpApp, normal: EscapeSequences.moveUpNormal)
        }
    }

    @objc private func downAction() {
        startRepeat { [weak self] in
            self?.sendArrow(app: EscapeSequences.moveDownApp, normal: EscapeSequences.moveDownNormal)
        }
    }

    @objc private func leftAction() {
        startRepeat { [weak self] in
            self?.sendArrow(app: EscapeSequences.moveLeftApp, normal: EscapeSequences.moveLeftNormal)
        }
    }

    @objc private func rightAction() {
        startRepeat { [weak self] in
            self?.sendArrow(app: EscapeSequences.moveRightApp, normal: EscapeSequences.moveRightNormal)
        }
    }

    private func startRepeat(_ action: @escaping () -> Void) {
        UIDevice.current.playInputClick()
        action()
        repeatCommand = action
        repeatTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !(self.repeatTask?.isCancelled ?? true) else { return }
            nonisolated(unsafe) let cmd = self.repeatCommand
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                cmd?()
            }
        }
    }

    @objc private func cancelRepeatTimer() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatCommand = nil
        repeatTask?.cancel()
        repeatTask = nil
    }

    // MARK: - Keyboard Toggle

    @objc private func toggleKeyboardAction() {
        UIDevice.current.playInputClick()
        guard let tv = terminalView else { return }
        let wasResponder = tv.isFirstResponder
        if wasResponder { _ = tv.resignFirstResponder() }

        if tv.inputView == nil {
            let size = CGSize(width: UIScreen.main.bounds.width,
                              height: max(UIScreen.main.bounds.height / 5, 140))
            tv.inputView = ClaudeKeyboardView(
                frame: CGRect(origin: .zero, size: size),
                terminalView: terminalView
            )
        } else {
            tv.inputView = nil
        }

        if wasResponder { _ = tv.becomeFirstResponder() }
    }
}

// MARK: - HighlightButton (selected state coloring)

private final class HighlightButton: UIButton {
    var normalColor: UIColor?

    override var isSelected: Bool {
        didSet {
            backgroundColor = isSelected ? UIView().tintColor : normalColor
        }
    }
}
#endif
