import AppKit

// MARK: - Welcome

/// Five-page Getting Started window in the Omnitrix × Liquid-Glass system.
/// The first page is the device hero with a live, switchable wheel preview;
/// pages two through four walk the three surfaces and their modifiers; the
/// last page explains folder access.
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

        // Left column: identity, workflow, actions.
        let brand = text("ZEST", size: 13, weight: .heavy, color: Omnitrix.lime)
        brand.attributedStringValue = NSAttributedString(
            string: "ZEST", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .heavy),
                                         .foregroundColor: Omnitrix.lime,
                                         .kern: 3])
        let title = text("Convert anything,\nright where it lives.", size: 27, weight: .bold,
                         color: .white)
        title.alignment = .left
        title.maximumNumberOfLines = 2

        func benefit(_ symbol: String, _ key: String, _ line: String) -> NSStackView {
            let icon = NSImageView(image: NSImage(systemSymbolName: symbol,
                                                  accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = Omnitrix.lime.withAlphaComponent(0.9)
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let keycap = KeycapView(text: key)
            let label = text(line, size: 12, weight: .regular,
                             color: NSColor(calibratedWhite: 1, alpha: 0.78))
            let row = NSStackView(views: [icon, keycap, label])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            return row
        }
        let rows = NSStackView(views: [
            benefit("arrow.left.arrow.right", Prefs.convertKey.title,
                    "Convert to any format"),
            benefit("wand.and.stars", Prefs.toolsKey.title,
                    "Run tools: crop, compress, redact…"),
            benefit("bolt.fill", Prefs.actionsKey.title,
                    "Act: AirDrop, copy, Terminal…")
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 10

        let start = welcomeButton("Get Started", background: Omnitrix.lime,
                                  foreground: NSColor(srgbRed: 0.06, green: 0.11, blue: 0.05, alpha: 1)) {
            self.show(page: 1)
        }
        let settings = welcomeButton("Settings",
                                     background: NSColor(calibratedWhite: 1, alpha: 0.10),
                                     foreground: .white) {
            self.window?.orderOut(nil)
            NotificationCenter.default.post(name: .zestOpenSettings, object: nil)
        }
        let buttons = NSStackView(views: [start, settings])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let left = NSStackView(views: [brand, title, rows, buttons])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 14
        left.setCustomSpacing(6, after: brand)
        left.setCustomSpacing(18, after: title)
        left.setCustomSpacing(22, after: rows)
        left.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(left)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 44),
            left.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: 0),
            start.widthAnchor.constraint(equalToConstant: 128),
            start.heightAnchor.constraint(equalToConstant: 34),
            settings.heightAnchor.constraint(equalToConstant: 34)
        ])

        // Right: the device itself — a real WheelView the user can flip
        // between the three surfaces.
        let hero = DeviceHero()
        hero.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(hero)
        NSLayoutConstraint.activate([
            hero.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 18),
            hero.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            hero.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -6),
            hero.heightAnchor.constraint(equalToConstant: 330)
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
        icon.contentTintColor = Omnitrix.lime
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
                        color: Omnitrix.limeBright.withAlphaComponent(0.95))

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
        NSGradient(colors: [
            NSColor(srgbRed: 0.118, green: 0.133, blue: 0.125, alpha: 1),
            NSColor(srgbRed: 0.055, green: 0.063, blue: 0.059, alpha: 1)
        ])?.draw(in: bounds, angle: -70)
        // A restrained green bloom behind the device side.
        if let bloom = NSGradient(colors: [
            Omnitrix.limeDeep.withAlphaComponent(0.22), NSColor.clear
        ]) {
            let c = NSPoint(x: bounds.maxX - bounds.width * 0.22, y: bounds.midY)
            bloom.draw(fromCenter: c, radius: 0, toCenter: c,
                       radius: bounds.width * 0.42, options: [])
        }
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

// MARK: - Device hero (intro page)

/// A real WheelView rendered inside the welcome card, with three pills that
/// switch it between the app's actual surfaces. It is the same renderer the
/// overlay uses, at a scale that fits the page.
private final class DeviceHero: NSView {
    private let wheel = WheelView(frame: .zero)
    private let sample = DemoAsset.url()
    private var surfaces: [(mode: WheelMode, choices: [WheelChoice])] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.14).cgColor
        layer?.cornerRadius = 20
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor

        surfaces = Catalog.surfaces(for: [sample]).map {
            (mode: $0.mode, choices: $0.choices)
        }
        wheel.translatesAutoresizingMaskIntoConstraints = false
        wheel.style = .fan
        wheel.fanScale = 0.62
        wheel.surfaces = surfaces
        wheel.emphasize(.tools)
        wheel.count = 1
        wheel.kind = .image
        wheel.fileName = sample.lastPathComponent
        wheel.fileFormat = sample.pathExtension.uppercased()
        wheel.totalBytes = sample.fileSize
        wheel.preview = true
        addSubview(wheel)
        NSLayoutConstraint.activate([
            wheel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            wheel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            wheel.topAnchor.constraint(equalTo: topAnchor, constant: 26),
            wheel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])

        let seg = NSStackView()
        seg.orientation = .horizontal
        seg.spacing = 6
        seg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(seg)
        NSLayoutConstraint.activate([
            seg.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            seg.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
        let modes: [(WheelMode, String)] = [(.tools, "Tools"), (.convert, "Convert"),
                                            (.actions, "Actions")]
        for (mode, label) in modes {
            let pill = NSButton(title: label, target: nil, action: nil)
            pill.isBordered = false
            pill.wantsLayer = true
            pill.layer?.cornerRadius = 9
            pill.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.10).cgColor
            pill.attributedTitle = NSAttributedString(
                string: label,
                attributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                             .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.75)])
            pill.translatesAutoresizingMaskIntoConstraints = false
            pill.widthAnchor.constraint(equalToConstant: 62).isActive = true
            pill.heightAnchor.constraint(equalToConstant: 20).isActive = true
            let handler = WelcomeHandler { [weak self, weak pill] in
                guard let self else { return }
                self.wheel.emphasize(mode)
                self.styleSelection(pill)
                self.wheel.startDeviceAnimation(pulse: true)
            }
            handlers.append(handler)
            pill.target = handler
            pill.action = #selector(WelcomeHandler.fire)
            seg.addArrangedSubview(pill)
            if mode == .tools { styleSelection(pill) }
            pills.append(pill)
        }
    }

    private var handlers: [WelcomeHandler] = []
    private var pills: [NSButton] = []

    private func styleSelection(_ selected: NSButton?) {
        for pill in pills {
            let on = pill == selected
            pill.layer?.backgroundColor = (on
                ? Omnitrix.lime.withAlphaComponent(0.85)
                : NSColor(calibratedWhite: 1, alpha: 0.10)).cgColor
            pill.attributedTitle = NSAttributedString(
                string: pill.title,
                attributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                             .foregroundColor: on
                                 ? NSColor(srgbRed: 0.06, green: 0.11, blue: 0.05, alpha: 1)
                                 : NSColor(calibratedWhite: 1, alpha: 0.75)])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        wheel.center = NSPoint(x: wheel.bounds.midX, y: wheel.bounds.midY)
        wheel.needsDisplay = true
    }
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
        wheel.fileName = sample.lastPathComponent
        wheel.fileFormat = sample.pathExtension.uppercased()
        wheel.totalBytes = sample.fileSize
        wheel.preview = true
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
