#if canImport(UIKit)
import UIKit
import SwiftTerm

/// Alternate on-screen keyboard with F-keys, brackets, nav keys, and Claude Code shortcuts.
/// Shown when the ⌨ button is tapped in the accessory bar.
///
/// Layout (10 columns × 4 rows):
/// ```
/// F1  F2  F3  F4  F5  F6  F7  F8  F9  F10
///  [   ]   {   }   <   >   &  Ins Home PgUp
///  +   -   *   =   %   `   \  Del  End PgDn
/// ^C  ^D /exit/comp /clr/help/stat/rev /cost/cfg
/// ```
public final class ClaudeKeyboardView: UIView {

    // MARK: - Properties

    public weak var terminalView: SwiftTerm.TerminalView?

    private var buttons: [UIButton] = []

    // MARK: - Init

    public init(frame: CGRect, terminalView: SwiftTerm.TerminalView?) {
        self.terminalView = terminalView
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.12, alpha: 1)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Rebuild on bounds change

    public override var bounds: CGRect {
        didSet {
            if oldValue.size != bounds.size {
                buildUI()
            }
        }
    }

    // MARK: - Key definitions

    /// Each row is an array of (label, action) tuples.
    private struct KeyDef {
        let label: String
        let icon: String?
        let action: @MainActor (ClaudeKeyboardView) -> Void
        let isDark: Bool

        init(_ label: String, icon: String? = nil, isDark: Bool = false,
             action: @escaping @MainActor (ClaudeKeyboardView) -> Void) {
            self.label = label
            self.icon = icon
            self.isDark = isDark
            self.action = action
        }
    }

    private var keyRows: [[KeyDef]] {
        [
            // Row 1: F1-F10
            [
                KeyDef("F1")  { $0.sendEsc(EscapeSequences.cmdF[0]) },
                KeyDef("F2")  { $0.sendEsc(EscapeSequences.cmdF[1]) },
                KeyDef("F3")  { $0.sendEsc(EscapeSequences.cmdF[2]) },
                KeyDef("F4")  { $0.sendEsc(EscapeSequences.cmdF[3]) },
                KeyDef("F5")  { $0.sendEsc(EscapeSequences.cmdF[4]) },
                KeyDef("F6")  { $0.sendEsc(EscapeSequences.cmdF[5]) },
                KeyDef("F7")  { $0.sendEsc(EscapeSequences.cmdF[6]) },
                KeyDef("F8")  { $0.sendEsc(EscapeSequences.cmdF[7]) },
                KeyDef("F9")  { $0.sendEsc(EscapeSequences.cmdF[8]) },
                KeyDef("F10") { $0.sendEsc(EscapeSequences.cmdF[9]) },
            ],
            // Row 2: brackets, angle, amp, ins, home, pgup
            [
                KeyDef("[")    { $0.sendChar("[") },
                KeyDef("]")    { $0.sendChar("]") },
                KeyDef("{")    { $0.sendChar("{") },
                KeyDef("}")    { $0.sendChar("}") },
                KeyDef("<")    { $0.sendChar("<") },
                KeyDef(">")    { $0.sendChar(">") },
                KeyDef("&")    { $0.sendChar("&") },
                KeyDef("ins", isDark: true) { $0.sendEsc(EscapeSequences.cmdInsert) },
                KeyDef("home", isDark: true) { v in
                    let app = v.terminalView?.getTerminal().applicationCursor ?? false
                    v.sendEsc(app ? EscapeSequences.moveHomeApp : EscapeSequences.moveHomeNormal)
                },
                KeyDef("pgup", isDark: true) { $0.sendEsc(EscapeSequences.cmdPageUp) },
            ],
            // Row 3: operators, backtick, backslash, del, end, pgdn
            [
                KeyDef("+")    { $0.sendChar("+") },
                KeyDef("-")    { $0.sendChar("-") },
                KeyDef("*")    { $0.sendChar("*") },
                KeyDef("=")    { $0.sendChar("=") },
                KeyDef("%")    { $0.sendChar("%") },
                KeyDef("`")    { $0.sendChar("`") },
                KeyDef("\\")   { $0.sendChar("\\") },
                KeyDef("del", icon: "delete.forward", isDark: true) { $0.sendEsc(EscapeSequences.cmdDelKey) },
                KeyDef("end", isDark: true) { v in
                    let app = v.terminalView?.getTerminal().applicationCursor ?? false
                    v.sendEsc(app ? EscapeSequences.moveEndApp : EscapeSequences.moveEndNormal)
                },
                KeyDef("pgdn", isDark: true) { $0.sendEsc(EscapeSequences.cmdPageDown) },
            ],
            // Row 4: Claude Code shortcuts
            [
                KeyDef("^C", isDark: true)    { $0.sendBytes([0x03]) },
                KeyDef("^D", isDark: true)    { $0.sendBytes([0x04]) },
                KeyDef("/exit", isDark: true)  { $0.sendText("/exit") },
                KeyDef("/comp", isDark: true)  { $0.sendText("/compact") },
                KeyDef("/clr", isDark: true)   { $0.sendText("/clear") },
                KeyDef("/help", isDark: true)  { $0.sendText("/help") },
                KeyDef("/stat", isDark: true)  { $0.sendText("/status") },
                KeyDef("/rev", isDark: true)   { $0.sendText("/review") },
                KeyDef("/cost", isDark: true)  { $0.sendText("/cost") },
                KeyDef("/cfg", isDark: true)   { $0.sendText("/config") },
            ],
        ]
    }

    // MARK: - Build UI

    private func buildUI() {
        for btn in buttons {
            btn.removeFromSuperview()
        }
        buttons.removeAll()

        let rows = keyRows
        let numCols = 10
        let numRows = rows.count
        let bottomPad: CGFloat = 20
        let slotWidth = frame.width / CGFloat(numCols)
        let slotHeight = (frame.height - bottomPad) / CGFloat(numRows)
        let xpad = min(slotWidth * 0.08, 3.0)
        let ypad = min(slotHeight * 0.08, 3.0)

        for (rowIndex, row) in rows.enumerated() {
            for (colIndex, keyDef) in row.enumerated() {
                let x = CGFloat(colIndex) * slotWidth + xpad
                let y = CGFloat(rowIndex) * slotHeight + ypad
                let w = slotWidth - xpad * 2
                let h = slotHeight - ypad * 2

                let btn = UIButton(type: .roundedRect)
                btn.frame = CGRect(x: x, y: y, width: w, height: h)
                btn.layer.cornerRadius = 5
                btn.layer.masksToBounds = true

                if let icon = keyDef.icon,
                   let img = UIImage(systemName: icon,
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 14)) {
                    btn.setImage(img.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
                } else {
                    btn.setTitle(keyDef.label, for: .normal)
                    btn.titleLabel?.adjustsFontSizeToFitWidth = true
                    btn.titleLabel?.numberOfLines = 1
                    btn.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)
                }

                btn.setTitleColor(.white, for: .normal)
                btn.backgroundColor = keyDef.isDark
                    ? UIColor(white: 0.22, alpha: 1)
                    : UIColor(white: 0.30, alpha: 1)

                btn.tag = rowIndex * numCols + colIndex
                btn.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    UIDevice.current.playInputClick()
                    keyDef.action(self)
                }, for: .touchUpInside)

                addSubview(btn)
                buttons.append(btn)
            }
        }
    }

    // MARK: - Send helpers

    private func sendEsc(_ bytes: [UInt8]) {
        terminalView?.send(bytes)
    }

    private func sendChar(_ char: String) {
        let bytes = Array(char.utf8)
        terminalView?.send(bytes)
    }

    private func sendBytes(_ bytes: [UInt8]) {
        terminalView?.send(bytes)
    }

    /// Send text string followed by newline (for slash commands).
    private func sendText(_ text: String) {
        let bytes = Array((text + "\n").utf8)
        terminalView?.send(bytes)
    }
}
#endif
