# SwiftTerminal Roadmap

Detailed implementation plan based on Blink Shell gap analysis and competitive research.

## MVP — Remaining Items (7-10)

### 7. Multi-tab sessions
**Что:** 2-3 concurrent SSH shells с swipe navigation между ними.
**Зачем:** Blink Shell, Termius и Prompt — все имеют tabs. Без них профессионалы не перейдут.
**Как:**
- `TabSession` модель: массив `SSHService` экземпляров
- UI: горизонтальный `TabView` или кастомный swipe-контейнер
- Каждый таб — свой `TerminalViewRepresentable` + `SSHService`
- Лимит Free: 1 tab, Pro: 3+ tabs
- Индикатор активности в таб-баре (зелёный/красный dot)

### 8. Text selection & copy in terminal
**Что:** Выделение текста в терминале long press + drag, копирование в буфер обмена.
**Зачем:** Без этого невозможно копировать output. Базовый UX.
**Как:**
- SwiftTerm уже поддерживает selection API (`terminal.getSelection()`)
- Добавить gesture recognizer для long press → selection mode
- Context menu: Copy, Select All, Paste
- Haptic feedback при выделении

### 9. Mosh support
**Что:** Mobile Shell — UDP-based протокол, выживает потерю соединения и смену IP.
**Зачем:** iOS убивает TCP через 20-30 секунд в фоне. Mosh — единственное решение для persistent sessions.
**Как:**
- Подключить `mosh-client` через SPM или embedded binary
- Fallback: SSH → Mosh автоматически если сервер поддерживает
- UI: индикатор "Mosh" vs "SSH" в статусбаре терминала
- Требует `mosh-server` на удалённой машине (документировать в provisioning)

### 10. SSH Agent forwarding
**Что:** Проброс SSH ключей через соединение (`-A` флаг).
**Зачем:** Нужен для `git push/pull` на удалённом сервере без копирования ключей.
**Как:**
- Citadel API: проверить поддержку agent forwarding
- Если нет — реализовать SSH agent protocol (RFC 4254 Section 6.1)
- UI: toggle per-server "Forward SSH Agent"
- Security warning при включении (риск если сервер скомпрометирован)

---

## V1.0 — Launch Features (11-15)

### 11. SSH tunneling / Port forwarding
**Что:** Local (-L), Remote (-R) и Dynamic (-D / SOCKS5) port forwarding.
**Зачем:** Blink Shell и Termius имеют это. Нужно для доступа к dev серверам, базам данных, веб-интерфейсам.
**Как:**
- `-L localPort:remoteHost:remotePort` — local forward
- `-R remotePort:localHost:localPort` — reverse forward
- `-D localPort` — SOCKS5 proxy
- Citadel / SwiftNIO SSH channel forwarding API
- UI: список активных tunnels, add/remove, статус

### 12. Custom themes
**Что:** Цветовые схемы терминала: Dark (default), Solarized Dark/Light, Dracula, Nord, Monokai, One Dark.
**Зачем:** Blink Shell — king of customization. Devs хотят свои цвета.
**Как:**
- `TerminalTheme` модель: 16 ANSI цветов + foreground/background/cursor
- JSON/plist конфиг для тем
- SwiftTerm `installColors()` API
- Settings → Appearance → Theme picker с preview
- Pro feature (Free: Dark only)

### 13. Custom fonts
**Что:** Выбор моноширинного шрифта: SF Mono (default), Fira Code, JetBrains Mono, Menlo, Courier New.
**Зачем:** Blink Shell поддерживает кастомные шрифты и даже импорт .ttf/.otf.
**Как:**
- Bundled fonts: SF Mono (system), Menlo (system)
- Downloadable: Fira Code, JetBrains Mono (OFL license, ~200KB each)
- SwiftTerm font API: `terminal.font = UIFont(...)`
- Settings → Appearance → Font picker с preview
- Font size slider (8-24pt)

### 14. Pinch-to-zoom in terminal
**Что:** Жест pinch для изменения размера шрифта в реальном времени.
**Зачем:** Удобство на маленьком экране iPhone. Blink Shell и Termius имеют.
**Как:**
- `UIPinchGestureRecognizer` на terminal view
- Изменение font size → SwiftTerm `terminal.font`
- Persist last zoom level per-server
- Min/max limits (6pt - 32pt)

### 15. One-tap snippets / Saved commands
**Что:** Библиотека часто используемых команд с one-tap execution.
**Зачем:** Claude Code UX — быстрый доступ к `claude`, `git status`, `npm run dev` etc.
**Как:**
- `Snippet` модель: name, command, category (Git, Docker, Claude, Custom)
- Pre-built snippets для Claude Code workflow
- UI: floating button → snippet picker → paste в terminal
- Или интеграция в keyboard accessory bar
- Sync snippets через iCloud (V1.1)

---

## V1.1 — Power User Features (16-20)

### 16. Jump hosts / ProxyCommand / Bastion
**Что:** Подключение через промежуточный сервер (bastion/jump host).
**Зачем:** Корпоративные пользователи часто не имеют прямого доступа к серверам.
**Как:**
- Server config: optional "Jump Host" field
- SSH → jump host → SSH → target (nested SSH)
- ProxyCommand equivalent через Citadel channel forwarding
- UI: chain visualization (You → Bastion → Target)

### 17. Files.app integration (File Provider)
**Что:** SFTP доступ к файлам сервера прямо из Files.app.
**Зачем:** iOS native file management. Secure ShellFish — лидер по Files.app.
**Как:**
- File Provider Extension (отдельный target)
- SFTP через Citadel
- Lazy loading: показываем directory listing, скачиваем файлы on demand
- Edit in place: открыть файл в любом приложении → сохранить → upload

### 18. External display support
**Что:** Полноценный терминал на внешнем мониторе (iPad + USB-C → 4K display).
**Зачем:** Blink Shell — единственный SSH клиент с хорошей поддержкой.
**Как:**
- `UIScreen.didConnectNotification` → второй window
- Отдельный `UIWindow` для external display
- Full terminal на мониторе, management UI на iPad
- SceneDelegate multi-scene support

### 19. Cross-device sync
**Что:** Синхронизация серверов, ключей (публичных), сниппетов между устройствами.
**Зачем:** iPad + iPhone workflow. Blink Shell синхронит через iCloud.
**Как:**
- CloudKit / NSUbiquitousKeyValueStore для метаданных
- Приватные ключи НЕ синхронизируются (security) — только public keys
- Server configs, snippets, themes, fonts settings
- Conflict resolution: last-write-wins

### 20. Local UNIX commands
**Что:** Встроенные команды без SSH: `ls`, `cat`, `ping`, `curl`, `python`, `node`.
**Зачем:** Blink Shell имеет полный local shell. Полезно для быстрых операций.
**Как:**
- ios_system library или собственная реализация
- Sandbox limitations: только app container доступен
- Полезно для: ping (диагностика), curl (API testing), file management
- Отдельный "Local" терминал в списке серверов

---

## V2.0 — Advanced Features (21-25)

### 21. Push notifications
**Что:** Уведомления когда Claude Code нуждается во вводе пользователя.
**Зачем:** Основной value prop — "Claude needs your input" notification.
**Как:**
- Background SSH monitoring service
- Pattern matching на SSH output: "waiting for input", prompt patterns
- APNs / local notifications
- Deep link → открыть конкретный терминал

### 22. WebAuthn / FIDO2 / YubiKey
**Что:** Аутентификация через hardware security key.
**Зачем:** Enterprise security. YubiKey support — premium feature.
**Как:**
- ASAuthorizationSecurityKeyPublicKeyCredentialProvider
- NFC + Lightning/USB-C YubiKey
- SSH auth через FIDO2 (OpenSSH 8.2+ `sk-ecdsa-sha2-nistp256@openssh.com`)

### 23. Tailscale integration
**Что:** Подключение к серверам через Tailscale VPN mesh network.
**Зачем:** Tailscale популярен у devs. Прямой доступ к машинам без public IP.
**Как:**
- Tailscale iOS SDK / MagicDNS
- Auto-discover Tailscale machines
- Connect через Tailscale IP (100.x.x.x)
- Или: просто документация "add Tailscale VPN, use Tailscale IPs"

### 24. GitHub/GitLab integration
**Что:** Быстрый доступ к repos, PRs, issues прямо из приложения.
**Зачем:** Claude Code workflow включает GitHub. Quick actions: clone, PR review.
**Как:**
- OAuth2 authentication
- GitHub API: repos list, create PR, view issues
- Quick clone → SSH terminal
- GitHub Codespaces integration

### 25. VS Code Server / Codespaces
**Что:** Запуск VS Code Server на удалённом сервере, доступ через WebView.
**Зачем:** Blink Shell интегрирован с VS Code. Если это совместимо с Claude Code focus.
**Как:**
- `code-server` auto-install на provisioned VPS
- WKWebView → localhost tunnel → code-server UI
- Или: SSH port forward + Safari
- Оценить: не отвлекает ли от Claude Code фокуса

---

## Gap Analysis: SwiftTerminal vs Blink Shell

| Feature | Blink Shell | SwiftTerminal | Gap |
|---------|-------------|---------------|-----|
| SSH | ✅ | ✅ | — |
| Mosh | ✅ | ❌ → MVP #9 | Critical |
| Multi-tab | ✅ | ❌ → MVP #7 | Critical |
| Custom themes | ✅ | ❌ → V1.0 #12 | High |
| Custom fonts | ✅ | ❌ → V1.0 #13 | High |
| SSH tunnels | ✅ | ❌ → V1.0 #11 | High |
| Files.app | ✅ | ❌ → V1.1 #17 | Medium |
| External display | ✅ | ❌ → V1.1 #18 | Medium |
| Local shell | ✅ | ❌ → V1.1 #20 | Medium |
| VS Code | ✅ | ❌ → V2.0 #25 | Low |
| Agent forwarding | ✅ | ❌ → MVP #10 | High |
| Jump hosts | ✅ | ❌ → V1.1 #16 | Medium |
| **VPS provisioning** | ❌ | ✅ | **Our advantage** |
| **Claude Code UX** | ❌ | ✅ | **Our advantage** |
| **Keyboard bar** | ❌ | ✅ | **Our advantage** |
| **Biometric lock** | ❌ | ✅ | **Our advantage** |
| **Voice dictation** | ❌ | ✅ | **Our advantage** |
| **Slash command menus** | ❌ | ✅ | **Our advantage** |
| **Debug overlay** | ❌ | ✅ (DEBUG) | **Our advantage** |

## Priority Order (MVP remaining)

1. **Multi-tab** (#7) — без табов app не launch-ready
2. **Text selection** (#8) — базовый UX, блокер для App Store
3. **Mosh** (#9) — iOS killer feature, без него SSH бесполезен в фоне
4. **Agent forwarding** (#10) — git workflow на сервере

---

## SwiftTerm Audit (January 2026)

### Current Version
**[SwiftTerm 1.5.1 fork](https://github.com/fortunto2/SwiftTerm)**, branch `stable-1.5.1-sync-output`.
Package.swift: `branch: "stable-1.5.1-sync-output"`.
Upstream latest: ~1.9.x.

### Наш форк: что добавлено
На базе стабильной 1.5.1 (до regression #405) добавлены:
- **DEC Private Mode 2026 (Synchronized Output)** — при batch redraw (Claude Code, TUI apps) копит dirty regions и рендерит атомарно, убирает visual tearing. Спецификация: [synchronized-output](https://gist.github.com/christianparpart/d8a62cc1ab659194571ec44513cb14d7).
- **Emoji copy fix (#414)** — cherry-pick: wide characters (emoji) копировались с null bytes, теперь заменяются на spaces.

### Стратегия обновления
**Не обновлять upstream до фикса #405.** Баг "Window Resize on Coding Agents (Claude Code)" появился в 1.6.0: при resize окна ломается reflow → двойные строки, бесконечный скролл. Reopened 25 Jan 2026, фикса нет.

**Plan A** (текущий): Оставаться на форке 1.5.1 + sync output. Cherry-pick нужные фиксы из upstream:
- ~~**#414** — emoji null copy~~ ✅ cherry-picked
- **#441** — text wrapping overflow с Claude Code (закрыт без PR, нельзя cherry-pick)
- **#443** — carriage return buffer corruption on redraw (не баг SwiftTerm, пропускаем)
- **#440** — Ctrl+C не работает (environment-specific, пропускаем)
- **#415/#422** — emoji rendering / CJK cursor drift (конфликт с segment refactor из 1.6.0+, нельзя cherry-pick без resize бага)

**Plan B**: Дождаться фикса #405 в upstream, merge и добавить наш sync output коммит.

### SwiftTerm APIs — Что мы используем

| API | Используем | Файл |
|-----|-----------|------|
| `TerminalView` (UIView) | ✅ | TerminalView.swift |
| `TerminalViewDelegate` | ✅ | TerminalView.swift |
| `feed(byteArray:)` | ✅ | SSH output → экран |
| `send(_:)` | ✅ | Keyboard → SSH |
| `getTerminal()` | ✅ | cols/rows/altBuffer/appCursor |
| `font` | ✅ | Hardcoded 14pt monospace |
| `backgroundColor` | ✅ | Hardcoded black |
| `nativeForegroundColor` | ✅ | Hardcoded green |
| `nativeBackgroundColor` | ✅ | Hardcoded black |
| `isScrollEnabled` | ✅ | Alt buffer toggle |
| `contentOffset/Size` | ✅ | Scroll management |
| `bounces/alwaysBounceVertical` | ✅ | Disabled |
| `inputAccessoryView` | ✅ | ClaudeCodeAccessoryView |
| `inputView` | ✅ | ClaudeKeyboardView |
| `becomeFirstResponder` | ✅ | Keyboard management |
| Delegate: `send(source:data:)` | ✅ | User input → SSH |
| Delegate: `sizeChanged` | ✅ | PTY resize |
| Delegate: `clipboardCopy` | ✅ | Copy to pasteboard |

### SwiftTerm APIs — Что мы НЕ используем (но должны)

| API | Для чего | Roadmap Item |
|-----|---------|-------------|
| `installColors([Color])` | Custom color themes (16 ANSI) | #12 Custom themes |
| `setForegroundColor/setBackgroundColor/setCursorColor` | Per-theme colors | #12 Custom themes |
| `selectAll()` / `selectNone()` / `getSelection()` | Text selection UI | #8 Text selection |
| `selectionActive` (property) | Check if text selected | #8 Text selection |
| `pageUp()` / `pageDown()` | Keyboard scroll shortcuts | Keyboard bar улучшение |
| `scrollUp(lines:)` / `scrollDown(lines:)` | Fine scroll control | Keyboard bar |
| `createImage(source:data:...)` | iTerm2/Sixel image display | **NEW: #26** |
| `createImageFromBitmap(source:bytes:...)` | Kitty graphics protocol | **NEW: #26** |
| Delegate: `requestOpenLink(source:link:params:)` | Clickable URLs in output | **NEW: #27** |
| Delegate: `setTerminalTitle(source:title:)` | Show running command in nav bar | **NEW: #28** |
| Delegate: `hostCurrentDirectoryUpdate` | Track remote cwd | **NEW: #28** |
| Delegate: `iTermContent(source:content:)` | iTerm2 image protocol | **NEW: #26** |
| Delegate: `scrolled(source:position:)` | Custom scroll indicator | UX enhancement |
| Delegate: `rangeChanged(source:startY:endY:)` | Visible range tracking | UX enhancement |

### Новые фичи из SwiftTerm (добавить в Roadmap)

#### #26. Terminal image rendering (Sixel / iTerm2 / Kitty)
**Что:** Отображение изображений прямо в терминале.
**Зачем:** Claude Code и другие CLI tools используют `imgcat` для отображения скриншотов, графиков, диаграмм. SwiftTerm уже поддерживает три протокола: Sixel, iTerm2, Kitty graphics.
**Как:**
- Реализовать delegate `iTermContent(source:content:)` — для iTerm2 protocol
- Реализовать `createImage()` / `createImageFromBitmap()` callbacks
- SwiftTerm парсит escape sequences, нам нужно только отрисовать
- Тест: `imgcat image.png` на сервере

#### #27. Clickable URLs / Hyperlinks
**Что:** Ссылки в terminal output становятся кликабельными.
**Зачем:** Claude Code выводит URLs (GitHub PRs, docs, errors). Сейчас нужно копировать руками.
**Как:**
- Реализовать delegate `requestOpenLink(source:link:params:)`
- Open URL в Safari/in-app browser
- Visual: подчёркивание ссылок (SwiftTerm уже рендерит hyperlink escape codes)
- Long press на ссылке → Copy URL / Open

#### #28. Terminal title & working directory tracking
**Что:** Показывать title терминала (hostname + текущую команду) и текущую директорию.
**Зачем:** Ориентация в multi-tab: видно какой таб что делает. Полезно для Files.app интеграции.
**Как:**
- Реализовать delegate `setTerminalTitle(source:title:)` → nav bar title
- Реализовать delegate `hostCurrentDirectoryUpdate(source:directory:)` → track cwd
- Title format: `user@host: ~/project`
- В multi-tab: показывать title в tab label

#### #29. Session recording (Asciinema)
**Что:** Запись terminal session в `.cast` формат (Asciinema 3.0).
**Зачем:** Запись demo, debugging, sharing Claude Code sessions. SwiftTerm поддерживает (#397).
**Как:**
- SwiftTerm termcast API (asciinema format)
- Record button в toolbar
- Save → Share Sheet → файл .cast
- Playback in-app (nice to have)

#### #30. Option-tap cursor positioning
**Что:** Тап по позиции в терминале перемещает курсор туда (как в Blink Shell).
**Зачем:** Быстрая навигация в command line без стрелок. Issue #236 в SwiftTerm.
**Как:**
- Detect tap position → calculate terminal column/row
- Send arrow key sequences (left/right) to move cursor
- Работает только в normal mode (не в vim/TUI)
- Или: отправить escape sequence `\e[row;colH` если поддерживается

#### #31. OSC 9;4 Progress reporting
**Что:** Прогресс-бар задач в UI терминала (не в тексте, а в нативном UI).
**Зачем:** Claude Code долгие операции → показывать прогресс в статусбаре или tab badge. SwiftTerm issue #447.
**Как:**
- Parse OSC 9;4 escape sequences
- UI: progress bar в nav bar или tab indicator
- Полезно для: npm install, git clone, Claude Code thinking

### Релевантные открытые баги SwiftTerm (следить)

| Issue | Описание | Влияние на нас |
|-------|---------|---------------|
| **#405** | Window resize на Claude Code — reflow сломан с 1.6.0 | **BLOCKER для upgrade** |
| **#451** | Opencode rendering | Может влиять на CLI tools |
| **#450** | Fails to resolve on Swift 6.2.3 | Следить при обновлении Xcode |
| **#423** | Black-on-black text при nativeForegroundColor | Может быть у нас при смене тем |
| **#376** | Keyboard speed response | Latency при быстром вводе |
| **#373** | Performance (reopened) | Большой output может тормозить |
| **#361** | Chinese character overlap при resize | Интернационализация |
| **#292** | iOS keyboard accessory safe area | У нас свой accessory — проверить |
| **#274** | iOS selection extension | Блокер для #8 text selection |
| **#272** | Pinch zoom UI | Полезно для #14 |
| **#271** | Backspace auto-repeat со space | Может быть у нас |
| **#221** | Selection vs mouse events конфликт | Важно для #8 |
| **#202** | Metal renderer | Performance boost |
