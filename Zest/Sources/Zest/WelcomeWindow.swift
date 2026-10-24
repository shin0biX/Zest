import AppKit

// MARK: - Welcome

/// Five-page Getting Started window. The first page is the orange Tangerine
/// welcome; pages two through four show the fan wheel in each mode and name
/// the modifier that arms it; the last page explains folder access.
final class WelcomeWindow: NSWindowController {
    static let shared = WelcomeWindow()

    private let root = NSView()
    private var page = 0
    private var handlers: [WelcomeHandler] = []
    private let pageCount = 5

    private init() {
        let panel = WelcomePanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 470),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.title = "Welcome to Zest"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.center()
        panel.onCancel = { [weak panel] in panel?.orderOut(nil) }
        super.init(window: panel)
        root.wantsLayer = true
        panel.contentView = root
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        show(page: 0)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Pages

    private func show(page: Int) {
        self.page = page
        handlers.removeAll()
        root.subviews.forEach { $0.removeFromSuperview() }

        switch page {
        case 0: buildIntro()
        case 1: buildFeaturePage(index: 1, mode: .convert, step: "STEP 1 OF 3",
                                 title: "Convert",
                                 body: "Drag files in Finder, then tap \(Prefs.convertKey.title) before you drop. Pick a format from the fan. The wheel stays exactly where you armed it.")
        case 2: buildFeaturePage(index: 2, mode: .tools, step: "STEP 2 OF 3",
                                 title: "Transform",
                                 body: "Tap \(Prefs.toolsKey.title) for tools: compress, resize, crop, Add BG, annotate, redact, metadata, collage, QR and the media trims. The same wheel carries every kind.")
        case 3: buildFeaturePage(index: 3, mode: .actions, step: "STEP 3 OF 3",
                                 title: "Act",
                                 body: "Tap \(Prefs.actionsKey.title) for AirDrop, Float, Copy, Move, Copy Path, Terminal and Reveal. Pick an action and release.")
        default: buildAccessPage()
        }
        addDots()
        addNavigation()
    }

    private func buildIntro() {
        let backdrop = GradientBackdrop()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: root.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        let title = text("Welcome to Zest", size: 40, weight: .bold, color: .white)
        title.alignment = .center
        let subtitle = text("Convert anything, right where it lives.", size: 15,
                            weight: .medium, color: NSColor(calibratedWhite: 1, alpha: 0.84))
        subtitle.alignment = .center

        let center = NSStackView(views: [title, subtitle])
        center.orientation = .vertical
        center.alignment = .centerX
        center.spacing = 8
        center.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(center)
        NSLayoutConstraint.activate([
            center.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            center.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -18),
            title.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -80)
        ])

        let start = welcomeButton("Get Started", background: .white,
                                  foreground: NSColor(calibratedRed: 0.91, green: 0.35, blue: 0.13, alpha: 1)) {
            self.show(page: 1)
        }
        start.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(start)
        NSLayoutConstraint.activate([
            start.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            start.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -44),
            start.widthAnchor.constraint(equalToConstant: 148),
            start.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func buildFeaturePage(index: Int, mode: WheelMode, step: String,
                                  title: String, body: String) {
        let backdrop = SolidBackdrop()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: root.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        let preview = WelcomeWheelPreview(mode: mode)
        preview.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(preview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            preview.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: 2),
            preview.widthAnchor.constraint(equalToConstant: 370),
            preview.heightAnchor.constraint(equalToConstant: 370)
        ])

        let stepLabel = text(step, size: 10, weight: .bold,
                             color: NSColor(calibratedWhite: 1, alpha: 0.45))
        stepLabel.attributedStringValue = NSAttributedString(
            string: step,
            attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .bold),
                         .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.45),
                         .kern: 1.5])

        let heading = text(title, size: 30, weight: .bold, color: .white)
        let description = text(body, size: 13, weight: .regular,
                               color: NSColor(calibratedWhite: 1, alpha: 0.78))
        description.maximumNumberOfLines = 6
        description.lineBreakMode = .byWordWrapping
        description.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        description.widthAnchor.constraint(equalToConstant: 268).isActive = true

        let modifier: String
        switch mode {
        case .convert: modifier = Prefs.convertKey.title
        case .tools: modifier = Prefs.toolsKey.title
        case .actions: modifier = Prefs.actionsKey.title
        }
        let hold = text("Hold", size: 12, weight: .regular,
                        color: NSColor(calibratedWhite: 1, alpha: 0.62))
        let keycap = KeycapView(text: modifier)
        let whileDragging = text("while you drag", size: 12, weight: .regular,
                                 color: NSColor(calibratedWhite: 1, alpha: 0.62))
        let keyRow = NSStackView(views: [hold, keycap, whileDragging])
        keyRow.orientation = .horizontal
        keyRow.alignment = .centerY
        keyRow.spacing = 8

        let right = NSStackView(views: [stepLabel, heading, description, keyRow])
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 10
        right.setCustomSpacing(2, after: stepLabel)
        right.setCustomSpacing(14, after: heading)
        right.setCustomSpacing(16, after: description)
        right.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(right)
        NSLayoutConstraint.activate([
            right.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 8),
            right.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -38),
            right.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: 4)
        ])
    }

    private func buildAccessPage() {
        let backdrop = SolidBackdrop()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: root.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        let folder = NSImage(systemSymbolName: "folder.badge.gearshape",
                             accessibilityDescription: nil)
        let icon = NSImageView(image: folder ?? NSImage())
        icon.contentTintColor = NSColor(calibratedRed: 0.96, green: 0.48, blue: 0.18, alpha: 1)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 58).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 58).isActive = true

        let heading = text("Folder access", size: 30, weight: .bold, color: .white)
        let body = text("Zest is not sandboxed, so it can write beside your files without a bookmark. If a source lives on an external volume or in iCloud Drive, macOS may ask for access the first time. That prompt is normal and applies only to that folder.",
                        size: 13, weight: .regular,
                        color: NSColor(calibratedWhite: 1, alpha: 0.78))
        body.maximumNumberOfLines = 7
        body.lineBreakMode = .byWordWrapping
        body.widthAnchor.constraint(equalToConstant: 460).isActive = true

        let note = text("Nothing leaves this Mac. No network, no uploads, no telemetry.",
                        size: 11.5, weight: .medium,
                        color: NSColor(calibratedRed: 0.98, green: 0.58, blue: 0.28, alpha: 0.95))

        let open = welcomeButton("Open Home Folder", background: NSColor(calibratedWhite: 1, alpha: 0.10),
                                 foreground: .white) {
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
        }
        let settings = welcomeButton("Open Settings", background: NSColor(calibratedWhite: 1, alpha: 0.10),
                                     foreground: .white) {
            self.window?.orderOut(nil)
            NotificationCenter.default.post(name: .zestOpenSettings, object: nil)
        }
        let buttons = NSStackView(views: [open, settings])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [icon, heading, body, buttons, note])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(18, after: icon)
        stack.setCustomSpacing(10, after: heading)
        stack.setCustomSpacing(20, after: body)
        stack.setCustomSpacing(18, after: buttons)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -4)
        ])
    }

    // MARK: Navigation

    private func addDots() {
        let dots = NSStackView()
        dots.orientation = .horizontal
        dots.spacing = 7
        dots.translatesAutoresizingMaskIntoConstraints = false
        for index in 0..<pageCount {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3.5
            dot.layer?.backgroundColor = (index == page
                ? NSColor(calibratedWhite: 1, alpha: 0.92)
                : NSColor(calibratedWhite: 1, alpha: 0.24)).cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 7).isActive = true
            dots.addArrangedSubview(dot)
        }
        root.addSubview(dots)
        NSLayoutConstraint.activate([
            dots.centerXAnchor.constraint(equalTo: root.centerXAnchor, constant: 28),
            dots.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22)
        ])
    }

    private func addNavigation() {
        guard page > 0 else { return }
        let back = welcomeButton("Back", background: NSColor(calibratedWhite: 1, alpha: 0.10),
                                 foreground: .white) {
            self.show(page: self.page - 1)
        }
        back.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(back)
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            back.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            back.widthAnchor.constraint(equalToConstant: 82),
            back.heightAnchor.constraint(equalToConstant: 32)
        ])

        let isLast = page == pageCount - 1
        let next = welcomeButton(isLast ? "Finish" : "Continue",
                                 background: NSColor(calibratedRed: 0.95, green: 0.43, blue: 0.16, alpha: 1),
                                 foreground: .white) {
            if isLast {
                Prefs.welcomeSeen = true
                self.window?.orderOut(nil)
            } else {
                self.show(page: self.page + 1)
            }
        }
        next.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(next)
        NSLayoutConstraint.activate([
            next.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            next.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            next.widthAnchor.constraint(equalToConstant: isLast ? 96 : 112),
            next.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    // MARK: Helpers

    private func text(_ string: String, size: CGFloat, weight: NSFont.Weight,
                      color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    private func welcomeButton(_ title: String, background: NSColor, foreground: NSColor,
                               action: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = background.cgColor
        button.layer?.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                         .foregroundColor: foreground])
        let handler = WelcomeHandler(action)
        handlers.append(handler)
        button.target = handler
        button.action = #selector(WelcomeHandler.fire)
        return button
    }

    private func bind(_ control: NSControl, action: @escaping () -> Void) {
        let handler = WelcomeHandler(action)
        handlers.append(handler)
        control.target = handler
        control.action = #selector(WelcomeHandler.fire)
    }
}

// MARK: - Window

private final class WelcomePanel: NSWindow {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private final class WelcomeHandler: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

// MARK: - Backdrops

private final class GradientBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.16, alpha: 1),
            NSColor(calibratedRed: 0.89, green: 0.28, blue: 0.13, alpha: 1)
        ])
        gradient?.draw(in: bounds, angle: -28)
    }
}

private final class SolidBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.075, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()
    }
}

// MARK: - Keycap

private final class KeycapView: NSView {
    private let label: NSTextField

    init(text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.12).cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.16).cgColor
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Fan preview

private final class WelcomeWheelPreview: NSView {
    private let wheel = WheelView(frame: .zero)

    init(mode: WheelMode) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.10).cgColor
        layer?.cornerRadius = 24

        let sample = DemoAsset.url()
        wheel.translatesAutoresizingMaskIntoConstraints = false
        wheel.style = .fan
        wheel.fanScale = 0.50
        // The welcome card is a preview, not the full catalog: cap at eight
        // petals so labels stay readable at half scale.
        wheel.surfaces = Catalog.surfaces(for: [sample]).map {
            (mode: $0.mode, choices: Array($0.choices.prefix(8)))
        }
        wheel.emphasize(mode)
        wheel.count = 1
        wheel.kind = .image
        wheel.totalBytes = sample.fileSize
        wheel.preview = true
        wheel.showBackdrop = false
        addSubview(wheel)
        NSLayoutConstraint.activate([
            wheel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            wheel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            wheel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            wheel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        wheel.center = NSPoint(x: wheel.bounds.midX, y: wheel.bounds.midY)
        wheel.needsDisplay = true
    }
}

extension Notification.Name {
    static let zestOpenSettings = Notification.Name("ZestOpenSettings")
}
