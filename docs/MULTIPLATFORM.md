# iPad + Native macOS Support

## Задача
Добавить поддержку iPad (оптимизация layout) и native macOS приложение.

## Текущее состояние

- **iPhone** ✅ — основная платформа
- **iPad** ~80% — `TARGETED_DEVICE_FAMILY: 1,2` уже настроен, ориентации есть, но layout не адаптирован
- **macOS** ❌ — только CLI (`SwiftTerminalCLI`), GUI нет, `SUPPORTS_MACCATALYST = NO`
- **SwiftTerm** ✅ — имеет полный NSView для macOS (`Sources/SwiftTerm/Mac/MacTerminalView.swift`)

## Блокеры для macOS

3 файла содержат UIKit-only код:

| Файл | UIKit зависимости | Строк UIKit кода |
|---|---|---|
| `TerminalView.swift` | `UIViewRepresentable`, `UIFont`, `UIScrollView` properties, `UIPasteboard`, keyboard notifications | ~30 |
| `ClaudeCodeAccessoryView.swift` | `UIInputView`, `UIButton`, `UIMenu`, `UIAction`, `UITextField`, `UIStackView`, `UIDevice.playInputClick()` | ~80 |
| `ClaudeKeyboardView.swift` | `UIView`, `UIButton`, `UIImage`, `UIFont`, `UIDevice.playInputClick()` | ~60 |

Все три уже обёрнуты в `#if canImport(UIKit)` — macOS их просто не скомпилирует.

**Не блокируют macOS** (уже кроссплатформенные):
- Все Services (SSHService, KeychainService, SSHKeyGenerator, ServerStore)
- LockScreenView, ServerListView, AddServerView, SettingsView, ProvisioningView, KeyManagementView
- SwiftTerminalApp.swift (чистый SwiftUI)

**Нужно снять `#if canImport(UIKit)` guard:**
- `Session.swift` — чистый Swift/SwiftTerm, UIKit не нужен
- `SessionManager.swift` — чистый Swift, UIKit не нужен
- `SessionTabStrip.swift` — чистый SwiftUI
- `ActiveTerminalContainerView.swift` — чистый SwiftUI
- `PortForwardView.swift` — содержит `.keyboardType(.numberPad)` и `.textInputAutocapitalization(.never)` — обернуть в `#if os(iOS)`

---

## Path A: iPad Optimization

### A1. Адаптивный layout ServerListView
**Файл:** `Sources/SwiftTerminalCore/Views/ServerListView.swift`
- iPad landscape: `NavigationSplitView` — server list слева, terminal справа
- iPhone: текущий `NavigationStack` (без изменений)
- Detect: `@Environment(\.horizontalSizeClass)` → `.regular` = iPad split

### A2. Terminal font size для iPad
**Файл:** `Sources/SwiftTerminalCore/Views/TerminalView.swift`
- iPhone: 14pt (текущий)
- iPad: 16-17pt
- Detect: `UIDevice.current.userInterfaceIdiom == .pad`

### A3. Keyboard accessory для широкого экрана
**Файл:** `Sources/SwiftTerminalCore/Views/ClaudeCodeAccessoryView.swift`
- iPad: больше кнопок в одном ряду, увеличенные target areas
- Уже есть `frame.width < 380` check (line 85) — расширить для iPad widths

### A4. Multi-tab на iPad
Для будущего: на iPad tabs можно показывать как sidebar или top strip (уже есть `SessionTabStrip.swift`)

---

## Path B: Native macOS App

### B1. Новый macOS target в project.yml
**Файл:** `project.yml`

```yaml
targets:
  SwiftTerminal:
    type: application
    platform: iOS
    # ... existing iOS config ...

  SwiftTerminalMac:
    type: application
    platform: macOS
    deploymentTarget: "15.0"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: co.superduperai.swift-terminal-mac
        PRODUCT_NAME: SwiftTerminal
        DEVELOPMENT_TEAM: 8N495BBBLM
        CODE_SIGN_STYLE: Automatic
        SWIFT_VERSION: "6.0"
        SWIFT_STRICT_CONCURRENCY: complete
        MACOSX_DEPLOYMENT_TARGET: "15.0"
    sources:
      - path: Sources/SwiftTerminal
      - path: Sources/SwiftTerminalCore
    dependencies:
      - package: Citadel
      - package: SwiftTerm
    info:
      path: Sources/SwiftTerminal/Info.plist
      properties:
        CFBundleDisplayName: SwiftTerminal
        CFBundleShortVersionString: "1.0"
        LSMinimumSystemVersion: "15.0"
```

### B2. macOS TerminalView (NSViewRepresentable)
**Файл:** `Sources/SwiftTerminalCore/Views/TerminalView.swift`

Добавить `#if os(macOS)` блок рядом с существующим iOS кодом:

```swift
#if os(macOS)
import AppKit
import SwiftTerm

public struct TerminalViewRepresentable: NSViewRepresentable {
    let session: Session
    var containerSize: CGSize
    let terminalViewRef: TerminalViewRef

    public func makeCoordinator() -> Coordinator { ... }

    public func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let tv = SwiftTerm.TerminalView(frame: .zero)
        tv.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.terminalDelegate = context.coordinator
        // SSH output → feed
        // No inputAccessoryView on macOS (hardware keyboard)
        // No scroll bounce settings (NSView, not UIScrollView)
        return tv
    }

    public func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) { }

    public class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        // Same delegate methods as iOS
        // clipboardCopy: NSPasteboard instead of UIPasteboard
    }
}
#endif
```

SwiftTerm's macOS `TerminalView` наследует от `NSView` (не `NSScrollView`), поэтому:
- Нет `bounces`, `alwaysBounceVertical` и т.д.
- Scrolling через NSScroller (встроен в SwiftTerm)
- Нет `inputAccessoryView` — macOS использует hardware keyboard
- Нет keyboard show/hide notifications

### B3. macOS Keyboard — без accessory bar
На macOS нет виртуальной клавиатуры → `ClaudeCodeAccessoryView` и `ClaudeKeyboardView` НЕ нужны.

Вместо них:
- **Menu bar** — стандартное macOS меню (Edit → Send Ctrl+C, Send Escape, etc.)
- **Touch Bar** (опционально, если MacBook Pro) — кнопки Esc, Ctrl, arrows
- **Keyboard shortcuts** — Cmd+T (new tab), Cmd+W (close tab), Cmd+K (clear)

### B4. macOS Clipboard
**Файлы:** `TerminalView.swift`, `KeyManagementView.swift`

```swift
#if os(macOS)
NSPasteboard.general.setString(text, forType: .string)
#else
UIPasteboard.general.string = text
#endif
```

`KeyManagementView.swift` уже имеет `#if canImport(UIKit)` — добавить `#else` с `NSPasteboard`.

### B5. macOS Window & Scene
**Файл:** `Sources/SwiftTerminal/SwiftTerminalApp.swift`

```swift
@main
struct SwiftTerminalApp: App {
    var body: some Scene {
        WindowGroup {
            LockScreenView()
                .environment(serverStore)
        }
        #if os(macOS)
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { ... }
                    .keyboardShortcut("t")
            }
        }
        #endif
    }
}
```

### B6. macOS-specific UX
- **Title bar** — показывать `user@host` в window title
- **Multiple windows** — каждый сервер в своём окне (macOS паттерн)
- **Tabs** — native macOS window tabs (`.windowStyle(.automatic)`)
- **Touch Bar** — Esc, Ctrl+C, arrows (если поддерживается)
- **Menu bar shortcuts** — Cmd+K clear, Cmd+N new connection

---

## Файлы для изменения

| Файл | Изменение | Path A (iPad) | Path B (macOS) |
|---|---|---|---|
| `project.yml` | Добавить macOS target | — | ✅ |
| `Sources/SwiftTerminal/SwiftTerminalApp.swift` | Window size, commands | — | ✅ |
| `Sources/SwiftTerminalCore/Views/TerminalView.swift` | NSViewRepresentable + font size | ✅ font | ✅ NSView |
| `Sources/SwiftTerminalCore/Views/ClaudeCodeAccessoryView.swift` | iPad layout | ✅ width | — (не нужен) |
| `Sources/SwiftTerminalCore/Views/ServerListView.swift` | NavigationSplitView | ✅ split | ✅ split |
| `Sources/SwiftTerminalCore/Views/KeyManagementView.swift` | NSPasteboard | — | ✅ |
| `Sources/SwiftTerminalCore/Models/Session.swift` | Снять UIKit guard | — | ✅ |
| `Sources/SwiftTerminalCore/Services/SessionManager.swift` | Снять UIKit guard | — | ✅ |
| `Sources/SwiftTerminalCore/Views/SessionTabStrip.swift` | Снять UIKit guard | — | ✅ |
| `Sources/SwiftTerminalCore/Views/ActiveTerminalContainerView.swift` | Снять UIKit guard | — | ✅ |
| `Sources/SwiftTerminalCore/Views/PortForwardView.swift` | `#if os(iOS)` для keyboard modifiers | — | ✅ |

## Порядок реализации

1. **docs/MULTIPLATFORM.md** — сохранить план ✅
2. **iPad** (Path A) — A1 → A2 → A3 (минимум изменений, быстрый результат)
3. **macOS** (Path B) — B1 → B2 → B4 → B5 → B3 → B6

## Верификация

### iPad
- `xcodegen generate`
- Build на iPad simulator
- Проверить landscape split view
- Проверить keyboard accessory на широком экране

### macOS
- `xcodegen generate`
- Build macOS target: `xcodebuild -project SwiftTerminal.xcodeproj -scheme SwiftTerminalMac -destination 'platform=macOS' build`
- Запустить на Mac
- Проверить: SSH подключение, терминал, clipboard, window resize
- Проверить: меню, keyboard shortcuts
