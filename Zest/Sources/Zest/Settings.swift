import AppKit
import ServiceManagement

/// Scroll documents use a flipped coordinate system so AppKit starts at the
/// top instead of pinning a taller document to its bottom edge.
private // MARK: - Device style card

/// Settings → Appearance → Device Style: four selectable styles, a live
/// preview using the real `WheelView` renderer, animation intensity, and the
/// green-glow slider. Every control writes through `Prefs` immediately.
final class DeviceStyleCard: NSView {
    private let preview = WheelView(frame: .zero)
    private var cards: [DeviceStyle: NSView] = [:]
    private var glowValue: NSTextField!
    private var handlers: [SettingsHandler] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.03).cgColor

        let sample = DemoAsset.url()
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.style = .fan
        preview.fanScale = 0.34
        preview.deviceStyle = Prefs.deviceStyle
        preview.surfaces = Catalog.surfaces(for: [sample]).map {
            (mode: $0.mode, choices: Array($0.choices.prefix(8)))
        }
        preview.emphasize(.tools)
        preview.count = 1
        preview.kind = .image
        preview.fileName = sample.lastPathComponent
        preview.fileFormat = sample.pathExtension.uppercased()
        preview.totalBytes = sample.fileSize
        preview.preview = true
        addSubview(preview)

        // 2×2 grid of style cards.
        func cardRow(_ styles: [DeviceStyle]) -> NSStackView {
            let row = NSStackView(views: styles.map(styleCard))
            row.orientation = .horizontal
            row.spacing = 8
            row.alignment = .top
            row.translatesAutoresizingMaskIntoConstraints = false
            return row
        }
        let grid = NSStackView(views: [cardRow([.minimal, .classic]),
                                       cardRow([.glass, .transformation])])
        grid.orientation = .vertical
        grid.spacing = 8
        grid.alignment = .leading
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)

        let intensity = SettingsSegmentedControl(
            items: AnimationIntensity.allCases.map(\.title),
            selected: AnimationIntensity.allCases.firstIndex(of: Prefs.animationIntensity) ?? 2)
        let intensityHandler = SettingsHandler { [weak intensity] in
            guard let intensity else { return }
            Prefs.animationIntensity = AnimationIntensity.allCases[intensity.selectedSegment]
            self.refreshPreview()
        }
        handlers.append(intensityHandler)
        intensity.target = intensityHandler
        intensity.action = #selector(SettingsHandler.fire)
        intensity.translatesAutoresizingMaskIntoConstraints = false
        addSubview(intensity)
        let intensityLabel = NSTextField(labelWithString: "Animation")
        intensityLabel.font = .systemFont(ofSize: 11, weight: .medium)
        intensityLabel.textColor = .secondaryLabelColor
        intensityLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(intensityLabel)

        let slider = NSSlider(value: Double(Prefs.greenGlow) * 100, minValue: 0, maxValue: 100,
                              target: nil, action: nil)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.isContinuous = true
        let sliderHandler = SettingsHandler {
            Prefs.greenGlow = slider.doubleValue / 100
            self.glowValue.stringValue = "\(Int(slider.doubleValue))%"
            self.refreshPreview()
        }
        handlers.append(sliderHandler)
        slider.target = sliderHandler
        slider.action = #selector(SettingsHandler.fire)
        addSubview(slider)

        glowValue = NSTextField(labelWithString: "\(Int(Prefs.greenGlow * 100))%")
        glowValue.font = .systemFont(ofSize: 11, weight: .medium)
        glowValue.textColor = .secondaryLabelColor
        glowValue.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glowValue)
        let glowLabel = NSTextField(labelWithString: "Green glow")
        glowLabel.font = .systemFont(ofSize: 11, weight: .medium)
        glowLabel.textColor = .secondaryLabelColor
        glowLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glowLabel)

        func fit(_ v: NSView) {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        [preview, grid, intensity, intensityLabel, slider, glowValue, glowLabel].forEach(fit)

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            preview.leadingAnchor.constraint(equalTo: grid.trailingAnchor, constant: 12),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            preview.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            preview.bottomAnchor.constraint(equalTo: slider.topAnchor, constant: -10),
            preview.widthAnchor.constraint(lessThanOrEqualToConstant: 190),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: slider.topAnchor, constant: -8),

            intensityLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            intensityLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            intensity.leadingAnchor.constraint(equalTo: intensityLabel.trailingAnchor, constant: 8),
            intensity.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            glowLabel.leadingAnchor.constraint(equalTo: intensity.trailingAnchor, constant: 18),
            glowLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            slider.leadingAnchor.constraint(equalTo: glowLabel.trailingAnchor, constant: 8),
            slider.widthAnchor.constraint(equalToConstant: 130),
            slider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            glowValue.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 6),
            glowValue.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
        styleSelection()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func styleCard(_ style: DeviceStyle) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 8

        let title = NSTextField(labelWithString: style.title)
        title.font = .systemFont(ofSize: 11.5, weight: .semibold)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        let blurb = NSTextField(labelWithString: style.blurb)
        blurb.font = .systemFont(ofSize: 9.5)
        blurb.textColor = .secondaryLabelColor
        blurb.lineBreakMode = .byTruncatingTail
        blurb.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)
        container.addSubview(blurb)

        let button = NSButton(title: style.title, target: nil, action: nil)
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: "", attributes: [:])
        button.translatesAutoresizingMaskIntoConstraints = false
        let handler = SettingsHandler { [weak self] in
            Prefs.deviceStyle = style
            self?.styleSelection()
            self?.refreshPreview(pulse: true)
        }
        handlers.append(handler)
        button.target = handler
        button.action = #selector(SettingsHandler.fire)
        container.addSubview(button)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            blurb.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            blurb.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            blurb.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 48),
            container.widthAnchor.constraint(equalToConstant: 148)
        ])
        cards[style] = container
        return container
    }

    private func styleSelection() {
        for (style, view) in cards {
            let on = style == Prefs.deviceStyle
            view.layer?.backgroundColor = (on
                ? Omnitrix.lime.withAlphaComponent(0.14).cgColor
                : NSColor(calibratedWhite: 1, alpha: 0.05).cgColor)
            view.layer?.borderWidth = on ? 1.2 : 1
            view.layer?.borderColor = (on
                ? Omnitrix.lime.withAlphaComponent(0.8).cgColor
                : NSColor(calibratedWhite: 1, alpha: 0.10).cgColor)
        }
    }

    private func refreshPreview(pulse: Bool = false) {
        preview.deviceStyle = Prefs.deviceStyle
        preview.needsDisplay = true
        if pulse { preview.startDeviceAnimation(pulse: true) }
    }

    override func layout() {
        super.layout()
        preview.center = NSPoint(x: preview.bounds.midX, y: preview.bounds.midY)
        preview.needsDisplay = true
    }
}

/// Small target-bridge for Settings controls created outside the window class.
final class SettingsHandler: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Settings primitives

private enum SettingsPalette {
    static var card: NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? NSColor(calibratedWhite: 1, alpha: 0.052)
                        : NSColor(calibratedWhite: 0, alpha: 0.032)
        }
    }

    static var divider: NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? NSColor(calibratedWhite: 1, alpha: 0.065)
                        : NSColor(calibratedWhite: 0, alpha: 0.075)
        }
    }

    static var selectedRow: NSColor {
        NSColor.systemOrange.withAlphaComponent(0.20)
    }

    static var hoverRow: NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? NSColor(calibratedWhite: 1, alpha: 0.055)
                        : NSColor(calibratedWhite: 0, alpha: 0.045)
        }
    }

    static var keycap: NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? NSColor(calibratedWhite: 1, alpha: 0.070)
                        : NSColor(calibratedWhite: 0, alpha: 0.055)
        }
    }

    static var quietText: NSColor { .secondaryLabelColor }
    static var orange: NSColor { .systemOrange }
}

private func settingsFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    .systemFont(ofSize: size, weight: weight)
}

private final class SettingsCardView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        SettingsPalette.card.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
    }
}

private final class SettingsDividerView: NSView {
    enum Axis { case horizontal, vertical }
    let axis: Axis

    init(_ axis: Axis = .horizontal) {
        self.axis = axis
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        axis == .horizontal ? NSSize(width: NSView.noIntrinsicMetric, height: 1)
                            : NSSize(width: 1, height: NSView.noIntrinsicMetric)
    }

    override func draw(_ dirtyRect: NSRect) {
        SettingsPalette.divider.setFill()
        if axis == .horizontal {
            NSRect(x: 0, y: floor(bounds.midY), width: bounds.width, height: 1).fill()
        } else {
            NSRect(x: floor(bounds.midX), y: 0, width: 1, height: bounds.height).fill()
        }
    }
}

private final class SettingsTabButton: NSButton {
    var selected = false { didSet { needsDisplay = true } }
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityLabel(title)
        setAccessibilityRole(.radioButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let width = (title as NSString).size(withAttributes: [.font: settingsFont(12, .medium)]).width
        return NSSize(width: ceil(width) + 22, height: 24)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        if selected {
            SettingsPalette.orange.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        } else if hovered {
            NSColor(calibratedWhite: 1, alpha: 0.075).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        }

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: settingsFont(12, selected ? .semibold : .medium),
            .foregroundColor: selected ? NSColor.white : NSColor.labelColor.withAlphaComponent(0.88),
            .paragraphStyle: para
        ]
        let height = (title as NSString).size(withAttributes: attrs).height
        (title as NSString).draw(in: NSRect(x: 0, y: (bounds.height - height) / 2,
                                            width: bounds.width, height: height + 1),
                                 withAttributes: attrs)
    }
}

/// A compact segmented control with an orange selected segment. AppKit's
/// native segmented control follows the system accent, which is blue on many
/// Macs; this window stays orange regardless of that system setting.
private final class SettingsSegmentedControl: NSControl {
    private let items: [String]
    private(set) var selectedIndex: Int

    var selectedSegment: Int {
        get { selectedIndex }
        set {
            selectedIndex = min(max(0, newValue), max(0, items.count - 1))
            needsDisplay = true
        }
    }

    init(items: [String], selected: Int) {
        self.items = items
        self.selectedIndex = min(max(0, selected), max(0, items.count - 1))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        focusRingType = .none
    }

    required init?(coder: NSCoder) { fatalError() }

    private var widths: [CGFloat] {
        items.map { item in
            let width = (item as NSString).size(withAttributes: [.font: settingsFont(11.5, .medium)]).width
            return max(54, ceil(width) + 24)
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: widths.reduce(0, +) + 2, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        SettingsPalette.keycap.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()

        var x: CGFloat = 1
        for (index, item) in items.enumerated() {
            let width = widths[index]
            let rect = NSRect(x: x, y: 1, width: width, height: bounds.height - 2)
            if index == selectedIndex {
                SettingsPalette.orange.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            }

            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: settingsFont(11.5, index == selectedIndex ? .semibold : .regular),
                .foregroundColor: index == selectedIndex ? NSColor.white
                                                         : NSColor.labelColor.withAlphaComponent(0.85),
                .paragraphStyle: para
            ]
            let height = (item as NSString).size(withAttributes: attrs).height
            (item as NSString).draw(in: NSRect(x: rect.minX, y: rect.midY - height / 2,
                                               width: rect.width, height: height + 1),
                                    withAttributes: attrs)
            x += width
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        var x: CGFloat = 1
        for (index, _) in items.enumerated() {
            let width = widths[index]
            if point.x >= x && point.x < x + width {
                selectedSegment = index
                sendAction(action, to: target)
                return
            }
            x += width
        }
    }
}

private final class SettingsCheckButton: NSButton {
    init(title: String, on: Bool) {
        super.init(frame: .zero)
        self.title = title
        setButtonType(.toggle)
        state = on ? .on : .off
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        font = settingsFont(12.5)
        alignment = .left
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 26) }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: 1, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        if state == .on {
            SettingsPalette.orange.setFill()
            path.fill()
            // `NSButton` draws in a flipped context, so the vertical
            // offsets invert here. In screen terms the elbow sits below
            // the two ends.
            let down: CGFloat = isFlipped ? 1 : -1
            let check = NSBezierPath()
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: NSPoint(x: box.minX + 4.2, y: box.midY + 0.2 * down))
            check.line(to: NSPoint(x: box.minX + 6.9, y: box.midY + 2.7 * down))
            check.line(to: NSPoint(x: box.maxX - 3.5, y: box.midY - 3.4 * down))
            NSColor.white.setStroke()
            check.stroke()
        } else {
            NSColor(calibratedWhite: 1, alpha: 0.24).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: settingsFont(12.5),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para
        ]
        let height = (title as NSString).size(withAttributes: attrs).height
        (title as NSString).draw(in: NSRect(x: 25, y: (bounds.height - height) / 2,
                                            width: max(0, bounds.width - 25), height: height + 1),
                                 withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        needsDisplay = true
    }
}

private final class SettingsFormatRow: NSButton {
    let ext: String
    var selected = false { didSet { needsDisplay = true } }
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(title: String, ext: String) {
        self.ext = ext
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 23) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0, dy: 1)
        if selected {
            SettingsPalette.selectedRow.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        } else if hovered {
            SettingsPalette.hoverRow.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        }

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: settingsFont(12),
            .foregroundColor: selected ? NSColor.labelColor
                                       : NSColor.labelColor.withAlphaComponent(0.86),
            .paragraphStyle: para
        ]
        let height = (title as NSString).size(withAttributes: attrs).height
        (title as NSString).draw(in: NSRect(x: 8, y: (bounds.height - height) / 2,
                                            width: max(0, bounds.width - 12), height: height + 1),
                                 withAttributes: attrs)
    }
}

private final class SettingsPillButton: NSButton {
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let width = (title as NSString).size(withAttributes: [.font: settingsFont(12.5, .semibold)]).width
        return NSSize(width: ceil(width) + 34, height: 28)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill = hovered ? SettingsPalette.orange.blended(withFraction: 0.08, of: .white)
                           : SettingsPalette.orange
        (fill ?? SettingsPalette.orange).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2,
                     yRadius: bounds.height / 2).fill()

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: settingsFont(12.5, .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para
        ]
        let height = (title as NSString).size(withAttributes: attrs).height
        (title as NSString).draw(in: NSRect(x: 0, y: (bounds.height - height) / 2,
                                            width: bounds.width, height: height + 1),
                                 withAttributes: attrs)
    }
}

// MARK: - Settings window

/// Five-tab settings window: General, Formats, Compatibility, Folders, About.
/// Everything is programmatic AppKit and every value lands in the
/// `com.zest.app` suite immediately.
final class SettingsWindow: NSWindowController, NSSearchFieldDelegate {
    private enum Tab: Int, CaseIterable {
        case general, formats, compatibility, folders, about

        var title: String {
            switch self {
            case .general: return "General"
            case .formats: return "Formats"
            case .compatibility: return "Compatibility"
            case .folders: return "Folders"
            case .about: return "About"
            }
        }
    }

    private let root = NSView()
    private let effect = NSVisualEffectView()
    private let tabStack = NSStackView()
    private var tabButtons: [SettingsTabButton] = []
    private let contentHost = NSView()
    private var handlers: [SettingsControlHandler] = []
    private var selectedTab: Tab = .general

    private var selectedFormat = "jpg"
    private var formatSearch: NSSearchField?
    private var formatListStack: NSStackView?
    private var formatRows: [String: SettingsFormatRow] = [:]
    private var formatDetailHost: NSView?
    private var formatDetailScroll: NSScrollView?
    private var aboutEngineStack: NSStackView?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Zest Settings"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        build()
        applyAppearance()
        show(tab: .general)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Shell

    private func build() {
        guard let window else { return }
        window.contentView = root
        root.wantsLayer = true

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(effect)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            effect.topAnchor.constraint(equalTo: root.topAnchor),
            effect.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        // The titlebar is part of the content view, so the tab row starts just
        // under the traffic lights.
        tabStack.orientation = .horizontal
        tabStack.alignment = .centerY
        tabStack.spacing = 8
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        for tab in Tab.allCases {
            let button = SettingsTabButton(title: tab.title)
            button.tag = tab.rawValue
            button.target = self
            button.action = #selector(tabPressed(_:))
            tabButtons.append(button)
            tabStack.addArrangedSubview(button)
        }
        root.addSubview(tabStack)

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentHost)

        NSLayoutConstraint.activate([
            tabStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            tabStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 34),
            tabStack.heightAnchor.constraint(equalToConstant: 24),

            contentHost.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            contentHost.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            contentHost.topAnchor.constraint(equalTo: tabStack.bottomAnchor, constant: 10),
            contentHost.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
    }

    @objc private func tabPressed(_ sender: SettingsTabButton) {
        guard let tab = Tab(rawValue: sender.tag) else { return }
        show(tab: tab)
    }

    private func show(tab: Tab) {
        selectedTab = tab
        for button in tabButtons { button.selected = button.tag == tab.rawValue }
        handlers.removeAll()
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        formatSearch = nil
        formatListStack = nil
        formatRows.removeAll()
        formatDetailHost = nil
        formatDetailScroll = nil
        aboutEngineStack = nil

        let view: NSView
        switch tab {
        case .general: view = buildGeneral()
        case .formats: view = buildFormats()
        case .compatibility: view = buildCompatibility()
        case .folders: view = buildFolders()
        case .about: view = buildAbout()
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentHost.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor)
        ])
    }

    // MARK: Binding and layout helpers

    private func bind(_ control: NSControl, _ action: @escaping () -> Void) {
        let handler = SettingsControlHandler(action)
        handlers.append(handler)
        control.target = handler
        control.action = #selector(SettingsControlHandler.fire)
    }

    private func label(_ text: String, size: CGFloat = 12,
                       weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = settingsFont(size, weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func hint(_ text: String, size: CGFloat = 10.5) -> NSTextField {
        let field = label(text, size: size, color: .secondaryLabelColor)
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    private func append(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func scrollStack(spacing: CGFloat = 8) -> (NSScrollView, NSStackView) {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .allowed

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -14),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        return (scroll, stack)
    }

    private func sectionHeader(_ text: String) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let field = label(text, size: 10.5, weight: .medium, color: .secondaryLabelColor)
        wrap.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 15),
            field.centerYAnchor.constraint(equalTo: wrap.centerYAnchor, constant: 2),
            wrap.heightAnchor.constraint(equalToConstant: 28)
        ])
        return wrap
    }

    private func subsectionHeader(_ text: String) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let field = label(text, size: 11.5, weight: .semibold)
        wrap.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 15),
            field.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: 25)
        ])
        return wrap
    }

    private func divider(_ axis: SettingsDividerView.Axis = .horizontal) -> SettingsDividerView {
        SettingsDividerView(axis)
    }

    private func row(_ text: String, control: NSView, height: CGFloat = 31) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let name = label(text, size: 12.5)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        wrap.addSubview(name)
        wrap.addSubview(control)
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 15),
            name.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -8),
            control.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -15),
            control.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: height)
        ])
        return wrap
    }

    private func noteRow(_ text: String) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let field = hint(text)
        wrap.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 15),
            field.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -15),
            field.topAnchor.constraint(equalTo: wrap.topAnchor),
            field.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -9)
        ])
        return wrap
    }

    private func checkRow(_ title: String, _ value: Bool,
                          _ action: @escaping (Bool) -> Void) -> NSView {
        let button = SettingsCheckButton(title: title, on: value)
        bind(button) { action(button.state == .on) }
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 15),
            button.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -15),
            button.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: 27)
        ])
        return wrap
    }

    private func popup(_ items: [String], selected: Int, width: CGFloat,
                       _ action: @escaping (Int) -> Void) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.addItems(withTitles: items)
        button.selectItem(at: min(max(0, selected), max(0, items.count - 1)))
        button.controlSize = .small
        button.font = settingsFont(12)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        bind(button) { action(button.indexOfSelectedItem) }
        return button
    }

    private func segmented(_ items: [String], selected: Int,
                           _ action: @escaping (Int) -> Void) -> SettingsSegmentedControl {
        let control = SettingsSegmentedControl(items: items, selected: selected)
        bind(control) { action(control.selectedSegment) }
        return control
    }

    private func linkButton(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.focusRingType = .none
        button.translatesAutoresizingMaskIntoConstraints = false
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: settingsFont(10.5, .semibold),
            .foregroundColor: SettingsPalette.orange
        ])
        return button
    }

    // MARK: General

    private func buildGeneral() -> NSView {
        let (scroll, stack) = scrollStack()
        let actualLogin = SMAppService.mainApp.status == .enabled
        if Prefs.launchAtLogin != actualLogin { Prefs.launchAtLogin = actualLogin }

        let card = SettingsCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false

        append(sectionHeader("Appearance"), to: list)
        append(row("Style", control: segmented(
            AppearanceStyle.allCases.map(\.title),
            selected: Prefs.appearance == .glass ? 0 : 1) { index in
                Prefs.appearance = index == 0 ? .glass : .solid
                self.applyAppearance()
            }), to: list)
        append(divider(), to: list)
        append(row("Wheel", control: segmented(
            WheelStyle.allCases.map(\.title),
            selected: Prefs.wheelStyle == .fan ? 0 : 1) { index in
                Prefs.wheelStyle = index == 0 ? .fan : .rings
            }), to: list)
        append(noteRow("Fan shows one surface at a time. Rings shows all three surfaces together."), to: list)

        let deviceCard = DeviceStyleCard()
        deviceCard.translatesAutoresizingMaskIntoConstraints = false
        append(deviceCard, to: list)
        NSLayoutConstraint.activate([
            deviceCard.widthAnchor.constraint(equalTo: list.widthAnchor, constant: -30)
        ])

        append(divider(), to: list)
        append(sectionHeader("General"), to: list)
        append(checkRow("Launch at login", Prefs.launchAtLogin) { value in
            self.setLaunchAtLogin(value)
        }, to: list)
        append(checkRow("Sound and haptic feedback", Prefs.playSound) { value in
            Prefs.playSound = value
        }, to: list)

        append(divider(), to: list)
        append(subsectionHeader("Drag Modifiers"), to: list)
        append(modifierRow("Conversion wheel", current: Prefs.convertKey,
                           surface: .convert), to: list)
        append(modifierRow("Tools wheel", current: Prefs.toolsKey,
                           surface: .tools), to: list)
        append(modifierRow("Actions wheel", current: Prefs.actionsKey,
                           surface: .actions), to: list)
        append(noteRow("Tap the chosen modifier combination while dragging files."), to: list)

        append(divider(), to: list)
        append(row("Float Behaviour", control: popup(
            FloatBehavior.allCases.map(\.title),
            selected: Prefs.floatBehavior == .newFloat ? 0 : 1,
            width: 210) { index in
                Prefs.floatBehavior = index == 0 ? .newFloat : .addToExisting
            }), to: list)
        append(row("Terminal app", control: popup(
            TerminalChoice.allCases.map(\.title),
            selected: TerminalChoice.allCases.firstIndex(of: Prefs.terminalApp) ?? 0,
            width: 190) { index in
                Prefs.terminalApp = TerminalChoice.allCases[index]
            }), to: list)
        append(row("Name collisions", control: popup(
            ["Keep both", "Replace"],
            selected: Prefs.collisionPolicy == "replace" ? 1 : 0,
            width: 190) { index in
                Prefs.collisionPolicy = index == 1 ? "replace" : "keepBoth"
            }), to: list)

        append(divider(), to: list)
        append(subsectionHeader("Keyboard Control"), to: list)
        append(checkRow("Enable keyboard control", Prefs.keyboardControl) { value in
            self.setKeyboardControl(value)
        }, to: list)
        append(noteRow("Requires Accessibility permission for Zest. Arrow keys, Return and Escape move and commit the wheel."), to: list)

        card.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            list.topAnchor.constraint(equalTo: card.topAnchor),
            list.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return scroll
    }

    private enum ModifierSurface {
        case convert, tools, actions
    }

    private func modifierRow(_ title: String, current: TriggerKey,
                             surface: ModifierSurface) -> NSView {
        let control = popup(TriggerKey.allCases.map(\.settingsTitle),
                            selected: TriggerKey.allCases.firstIndex(of: current) ?? 0,
                            width: 190) { index in
            self.setTrigger(TriggerKey.allCases[index], surface: surface)
        }
        return row(title, control: control)
    }

    private func setTrigger(_ key: TriggerKey, surface: ModifierSurface) {
        var values: [ModifierSurface: TriggerKey] = [
            .convert: Prefs.convertKey,
            .tools: Prefs.toolsKey,
            .actions: Prefs.actionsKey
        ]
        values[surface] = key
        guard Set(values.values.map(\.rawValue)).count == values.count else {
            Alert.show("That key is already in use",
                       detail: "Pick a different modifier for each surface.")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.show(tab: self.selectedTab)
            }
            return
        }
        switch surface {
        case .convert: Prefs.convertKey = key
        case .tools: Prefs.toolsKey = key
        case .actions: Prefs.actionsKey = key
        }
        NotificationCenter.default.post(name: .zestSettingsChanged, object: nil)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Prefs.launchAtLogin = enabled
        } catch {
            Prefs.launchAtLogin = SMAppService.mainApp.status == .enabled
            Alert.show("Couldn't update the login item", detail: error.localizedDescription)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.show(tab: .general)
            }
        }
    }

    private func setKeyboardControl(_ enabled: Bool) {
        if enabled {
            guard KeyTap.shared.start() else {
                Prefs.keyboardControl = false
                KeyTap.requestPermission()
                Alert.show("Accessibility is required",
                           detail: "Grant Zest access in System Settings → Privacy & Security → Accessibility, then try again.")
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.show(tab: self.selectedTab)
                }
                return
            }
            Prefs.keyboardControl = true
        } else {
            KeyTap.shared.stop()
            Prefs.keyboardControl = false
        }
    }

    // MARK: Formats

    private struct FormatGroup {
        let title: String
        let formats: [(ext: String, title: String)]
    }

    private let formatGroups: [FormatGroup] = [
        FormatGroup(title: "Images", formats: [
            ("jpg", "JPG"), ("png", "PNG"), ("webp", "WEBP"), ("heic", "HEIC"),
            ("tiff", "TIFF"), ("svg", "SVG"), ("avif", "AVIF"), ("bmp", "BMP")
        ]),
        FormatGroup(title: "Documents", formats: [
            ("pdf", "PDF"), ("docx", "DOCX"), ("pages", "PAGES"), ("ppt", "PPT"),
            ("pptx", "PPTX"), ("txt", "TXT"), ("md", "MD"), ("rtf", "RTF"),
            ("rtfd", "RTFD"), ("textclipping", "TEXTCLIPPING"),
            ("html", "HTML"), ("epub", "EPUB")
        ]),
        FormatGroup(title: "Spreadsheets", formats: [
            ("xlsx", "XLSX"), ("xls", "XLS"), ("ods", "ODS"),
            ("csv", "CSV"), ("tsv", "TSV")
        ]),
        FormatGroup(title: "Audio", formats: [
            ("mp3", "MP3"), ("m4a", "M4A"), ("wav", "WAV"), ("flac", "FLAC"),
            ("ogg", "OGG"), ("opus", "OPUS"), ("aiff", "AIFF"), ("wma", "WMA")
        ]),
        FormatGroup(title: "Video", formats: [
            ("mp4", "MP4"), ("mov", "MOV"), ("mkv", "MKV"), ("webm", "WEBM"),
            ("avi", "AVI"), ("wmv", "WMV"), ("gif", "GIF")
        ]),
        FormatGroup(title: "Subtitles", formats: [
            ("srt", "SRT"), ("vtt", "VTT")
        ]),
        FormatGroup(title: "Archives", formats: [
            ("zip", "ZIP"), ("tar", "TAR"), ("gz", "GZIP"), ("rar", "RAR")
        ])
    ]

    private var allFormatExts: [String] {
        formatGroups.flatMap { $0.formats.map(\.ext) }
    }

    private func buildFormats() -> NSView {
        let split = NSView()
        split.translatesAutoresizingMaskIntoConstraints = false

        let search = NSSearchField()
        search.placeholderString = "Search"
        search.font = settingsFont(12)
        search.controlSize = .small
        search.sendsSearchStringImmediately = true
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false
        formatSearch = search

        let leftScroll = NSScrollView()
        leftScroll.translatesAutoresizingMaskIntoConstraints = false
        leftScroll.drawsBackground = false
        leftScroll.hasVerticalScroller = true
        leftScroll.autohidesScrollers = true
        leftScroll.scrollerStyle = .overlay

        let leftDocument = FlippedDocumentView()
        leftDocument.translatesAutoresizingMaskIntoConstraints = false
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false
        leftDocument.addSubview(list)
        leftScroll.documentView = leftDocument
        formatListStack = list
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: leftDocument.leadingAnchor, constant: 4),
            list.trailingAnchor.constraint(equalTo: leftDocument.trailingAnchor, constant: -4),
            list.topAnchor.constraint(equalTo: leftDocument.topAnchor, constant: 2),
            list.bottomAnchor.constraint(equalTo: leftDocument.bottomAnchor, constant: -8),
            leftDocument.widthAnchor.constraint(equalTo: leftScroll.contentView.widthAnchor)
        ])

        let detailScroll = NSScrollView()
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        detailScroll.drawsBackground = false
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.scrollerStyle = .overlay

        let detailDocument = FlippedDocumentView()
        detailDocument.translatesAutoresizingMaskIntoConstraints = false
        let detailHost = NSView()
        detailHost.translatesAutoresizingMaskIntoConstraints = false
        detailDocument.addSubview(detailHost)
        detailScroll.documentView = detailDocument
        formatDetailHost = detailHost
        formatDetailScroll = detailScroll
        NSLayoutConstraint.activate([
            detailHost.leadingAnchor.constraint(equalTo: detailDocument.leadingAnchor),
            detailHost.trailingAnchor.constraint(equalTo: detailDocument.trailingAnchor),
            detailHost.topAnchor.constraint(equalTo: detailDocument.topAnchor),
            detailHost.bottomAnchor.constraint(equalTo: detailDocument.bottomAnchor),
            detailDocument.widthAnchor.constraint(equalTo: detailScroll.contentView.widthAnchor)
        ])

        let verticalRule = divider(.vertical)
        split.addSubview(search)
        split.addSubview(leftScroll)
        split.addSubview(verticalRule)
        split.addSubview(detailScroll)

        NSLayoutConstraint.activate([
            search.leadingAnchor.constraint(equalTo: split.leadingAnchor),
            search.trailingAnchor.constraint(equalTo: split.leadingAnchor, constant: 154),
            search.topAnchor.constraint(equalTo: split.topAnchor),
            search.heightAnchor.constraint(equalToConstant: 24),

            leftScroll.leadingAnchor.constraint(equalTo: split.leadingAnchor),
            leftScroll.widthAnchor.constraint(equalToConstant: 154),
            leftScroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            leftScroll.bottomAnchor.constraint(equalTo: split.bottomAnchor),

            verticalRule.leadingAnchor.constraint(equalTo: leftScroll.trailingAnchor, constant: 4),
            verticalRule.widthAnchor.constraint(equalToConstant: 1),
            verticalRule.topAnchor.constraint(equalTo: split.topAnchor),
            verticalRule.bottomAnchor.constraint(equalTo: split.bottomAnchor),

            detailScroll.leadingAnchor.constraint(equalTo: verticalRule.trailingAnchor, constant: 14),
            detailScroll.trailingAnchor.constraint(equalTo: split.trailingAnchor),
            detailScroll.topAnchor.constraint(equalTo: split.topAnchor),
            detailScroll.bottomAnchor.constraint(equalTo: split.bottomAnchor)
        ])

        rebuildFormatList(filter: "")
        selectFormat(selectedFormat)
        return split
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field === formatSearch else { return }
        rebuildFormatList(filter: field.stringValue)
    }

    private func rebuildFormatList(filter: String) {
        guard let list = formatListStack else { return }
        for view in list.arrangedSubviews {
            list.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        formatRows.removeAll()

        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var added = 0
        for group in formatGroups {
            let matches = group.formats.filter {
                query.isEmpty || $0.title.lowercased().contains(query) || $0.ext.contains(query)
            }
            guard !matches.isEmpty else { continue }
            append(formatGroupHeader(group.title), to: list)
            for format in matches {
                let row = SettingsFormatRow(title: format.title, ext: format.ext)
                row.selected = format.ext == selectedFormat
                bind(row) { [weak self] in
                    self?.selectFormat(format.ext)
                }
                formatRows[format.ext] = row
                append(row, to: list)
                added += 1
            }
        }

        if added == 0 {
            let empty = NSView()
            empty.translatesAutoresizingMaskIntoConstraints = false
            let field = label("No formats match.", size: 11.5, color: .secondaryLabelColor)
            empty.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: empty.leadingAnchor, constant: 8),
                field.topAnchor.constraint(equalTo: empty.topAnchor, constant: 12),
                field.bottomAnchor.constraint(equalTo: empty.bottomAnchor, constant: -12)
            ])
            append(empty, to: list)
        }
    }

    private func formatGroupHeader(_ title: String) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let field = label(title, size: 9.5, weight: .semibold, color: .secondaryLabelColor)
        wrap.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 8),
            field.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: 25)
        ])
        return wrap
    }

    private func selectFormat(_ ext: String) {
        selectedFormat = ext
        for (key, row) in formatRows {
            row.selected = key == ext
        }
        guard let host = formatDetailHost else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        let detail = buildFormatDetail(ext)
        detail.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(detail)
        NSLayoutConstraint.activate([
            detail.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            detail.topAnchor.constraint(equalTo: host.topAnchor),
            detail.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        if let scroll = formatDetailScroll {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    private func isOutputFormat(_ ext: String) -> Bool {
        let output = Set([
            "jpg", "png", "webp", "heic", "tiff", "avif", "bmp", "gif",
            "pdf", "docx", "txt", "md", "rtf", "html", "epub",
            "xlsx", "ods", "csv", "tsv",
            "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma",
            "mp4", "mov", "mkv", "webm", "avi", "wmv",
            "srt", "vtt", "zip", "tar", "gz"
        ])
        if ext == "pages" { return Capability.pagesOutput }
        return output.contains(ext)
    }

    private func outputFormats(for ext: String) -> [Fmt] {
        let group = formatGroups.first { $0.formats.contains { $0.ext == ext } }?.title
        let formats: [Fmt]
        switch group {
        case "Images": formats = Catalog.imageOut
        case "Documents": formats = ext == "pdf" ? Catalog.pdfOut : Catalog.documentOut
        case "Spreadsheets": formats = Catalog.sheetOut
        case "Audio": formats = Catalog.audioOut
        case "Video": formats = Catalog.videoOut
        case "Subtitles": formats = Catalog.subtitleOut
        case "Archives": formats = Catalog.archiveOut
        default: formats = []
        }
        var seen = Set<String>()
        return formats.filter { fmt in
            let lower = fmt.ext.lowercased()
            guard !seen.contains(lower) else { return false }
            seen.insert(lower)
            return true
        }
    }

    private func formatSummary(_ ext: String) -> String {
        guard isOutputFormat(ext) else {
            if ext == "pages" {
                return "Input-only in this build. Pages output requires /Applications/Pages.app."
            }
            return "Input-only format. Choose an output format to configure its defaults."
        }
        let outputs = outputFormats(for: ext)
            .filter { $0.ext.lowercased() != ext }
            .map { $0.ext.uppercased() }
        guard !outputs.isEmpty else {
            return "Input and output format."
        }
        let joined: String
        if outputs.count == 1 {
            joined = outputs[0]
        } else {
            joined = outputs.dropLast().joined(separator: ", ") + " and " + outputs.last!
        }
        return "Input and output format. Converts to \(joined)."
    }

    private func buildFormatDetail(_ ext: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0

        let heading = label("\(ext.uppercased()) Settings", size: 16.5, weight: .semibold)
        let summary = hint(formatSummary(ext), size: 10.5)
        summary.maximumNumberOfLines = 3
        let header = NSStackView(views: [heading, summary])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        header.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        summary.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        append(verticalGap(12), to: stack)

        guard isOutputFormat(ext) else {
            append(noteBlock("Conversion defaults are configured on the output format you choose."), to: stack)
            return stack
        }

        var rows: [NSView] = []
        let imageLossy = ["jpg", "webp", "heic", "avif"]
        let imageMetadata = ["jpg", "png", "webp", "heic", "tiff", "avif", "gif"]
        let imageCompression = ["jpg", "png"]
        let imageSizing = ["jpg", "png"]
        let audioLossy = ["mp3", "m4a", "ogg", "opus", "wma"]
        let audioDepth = ["wav", "aiff"]
        let video = ["mp4", "mov", "mkv", "webm", "avi", "wmv"]

        if imageLossy.contains(ext) {
            let presets = QualityPreset.allCases
            rows.append(detailRow("Quality", control: popup(
                presets.map(\.title),
                selected: presets.firstIndex(of: Prefs.qualityPreset(for: ext)) ?? 2,
                width: 150) { index in
                    Prefs.setQualityPreset(presets[index], for: ext)
                }))
        }
        if imageMetadata.contains(ext) {
            rows.append(detailCheck("Preserve metadata", Prefs.preserveMetadata(for: ext)) { value in
                Prefs.setPreserveMetadata(value, for: ext)
            })
        }
        if audioLossy.contains(ext) {
            let rates = ["128", "192", "256", "320"]
            rows.append(detailRow("Audio bitrate", control: popup(
                rates.map { "\($0) kbps" },
                selected: rates.firstIndex(of: Prefs.audioBitrate(for: ext)) ?? 1,
                width: 150) { index in
                    Prefs.setAudioBitrate(rates[index], for: ext)
                }))
        }
        if audioDepth.contains(ext) {
            let depths = ["16", "24", "32"]
            rows.append(detailRow("Audio bit depth", control: popup(
                depths.map { "\($0)-bit" },
                selected: depths.firstIndex(of: Prefs.audioBitDepth(for: ext)) ?? 0,
                width: 150) { index in
                    Prefs.setAudioBitDepth(depths[index], for: ext)
                }))
        }
        if video.contains(ext) {
            let presets = QualityPreset.allCases
            rows.append(detailRow("Quality", control: popup(
                presets.map(\.title),
                selected: presets.firstIndex(of: Prefs.videoQuality(for: ext)) ?? 2,
                width: 150) { index in
                    Prefs.setVideoQuality(presets[index], for: ext)
                }))
            let heights = VideoHeightPreset.allCases
            rows.append(detailRow("Maximum height", control: popup(
                heights.map(\.title),
                selected: heights.firstIndex(of: Prefs.videoHeight(for: ext)) ?? 0,
                width: 150) { index in
                    Prefs.setVideoHeight(heights[index], for: ext)
                }))
        }
        if ext == "gif" {
            let fps = [8, 10, 12, 15, 20, 24]
            let widths = [480, 720, 1080, 1280]
            rows.append(detailRow("Frame rate", control: popup(
                fps.map { "\($0) fps" },
                selected: fps.firstIndex(of: Prefs.gifFPS(for: ext)) ?? 2,
                width: 150) { index in
                    Prefs.setGIF(fps: fps[index], width: Prefs.gifWidth(for: ext), for: ext)
                }))
            rows.append(detailRow("Maximum width", control: popup(
                widths.map { "\($0) px" },
                selected: widths.firstIndex(of: Prefs.gifWidth(for: ext)) ?? 1,
                width: 150) { index in
                    Prefs.setGIF(fps: Prefs.gifFPS(for: ext), width: widths[index], for: ext)
                }))
        }
        if ["docx", "pages", "epub"].contains(ext) {
            let layouts = [("Editable paragraphs", "editable"), ("Flowing text", "flowing")]
            rows.append(detailRow("PDF layout", control: popup(
                layouts.map(\.0),
                selected: layouts.firstIndex { $0.1 == Prefs.pdfLayout(for: ext) } ?? 0,
                width: 150) { index in
                    Prefs.setPDFLayout(layouts[index].1, for: ext)
                }))
        }
        if ext == "epub" {
            let layouts = [("Flowing text", "flowing"), ("Fixed layout", "fixed")]
            rows.append(detailRow("EPUB layout", control: popup(
                layouts.map(\.0),
                selected: layouts.firstIndex { $0.1 == Prefs.epubLayout(for: ext) } ?? 0,
                width: 150) { index in
                    Prefs.setEPUBLayout(layouts[index].1, for: ext)
                }))
        }

        if !rows.isEmpty {
            append(detailSectionHeader("Conversion Settings"), to: stack)
            for rowView in rows { append(rowView, to: stack) }
            append(restoreRow("Restore Defaults") { [weak self] in
                Prefs.resetFormatDefaults(ext)
                self?.selectFormat(ext)
            }, to: stack)
        }

        if imageCompression.contains(ext) || imageSizing.contains(ext) {
            append(verticalGap(8), to: stack)
            append(divider(), to: stack)
            append(verticalGap(8), to: stack)
            append(detailSectionHeader("Image Compression"), to: stack)
            if imageCompression.contains(ext) {
                let current = Prefs.imageCompression(for: ext) == "strong" ? 1 : 0
                append(detailRow("Compression", control: segmented(
                    ["Balanced", "Strong"], selected: current) { index in
                        Prefs.setImageCompression(index == 1 ? "strong" : "balanced", for: ext)
                    }), to: stack)
            }
            if imageSizing.contains(ext) {
                let presets = ImageSizePreset.allCases
                append(detailRow("Image size", control: popup(
                    presets.map(\.title),
                    selected: presets.firstIndex(of: Prefs.imageSize(for: ext)) ?? 0,
                    width: 190) { index in
                        Prefs.setImageSize(presets[index], for: ext)
                    }), to: stack)
            }
            append(restoreRow("Restore Compression Defaults") { [weak self] in
                Prefs.resetImageDefaults(ext)
                self?.selectFormat(ext)
            }, to: stack)
        }

        if rows.isEmpty && !imageCompression.contains(ext) && !imageSizing.contains(ext) {
            append(noteBlock("This output format has no adjustable conversion defaults in this build."), to: stack)
        }

        append(verticalGap(10), to: stack)
        append(noteBlock("Per-format defaults are read when a conversion starts."), to: stack)
        return stack
    }

    private func detailSectionHeader(_ text: String) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let field = label(text, size: 12.5, weight: .semibold)
        wrap.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            field.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: 27)
        ])
        return wrap
    }

    private func detailRow(_ title: String, control: NSView) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let name = label(title, size: 12.5)
        wrap.addSubview(name)
        wrap.addSubview(control)
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            name.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -6),
            control.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: 30)
        ])
        return wrap
    }

    private func detailCheck(_ title: String, _ value: Bool,
                             _ action: @escaping (Bool) -> Void) -> NSView {
        let button = SettingsCheckButton(title: title, on: value)
        bind(button) { action(button.state == .on) }
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: -1),
            button.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: 28)
        ])
        return wrap
    }

    private func restoreRow(_ title: String, _ action: @escaping () -> Void) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let button = linkButton(title)
        bind(button) { action() }
        wrap.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: 27)
        ])
        return wrap
    }

    private func noteBlock(_ text: String) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let field = hint(text)
        wrap.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            field.topAnchor.constraint(equalTo: wrap.topAnchor),
            field.bottomAnchor.constraint(equalTo: wrap.bottomAnchor)
        ])
        return wrap
    }

    private func verticalGap(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    // MARK: Compatibility

    private func buildCompatibility() -> NSView {
        let (scroll, stack) = scrollStack(spacing: 8)
        let header = sectionTitleRow("Format Compatibility", symbol: "square.grid.3x3")
        append(header, to: stack)
        let note = hint("Generated from the live catalog. Formats gated by missing engines are hidden. A dash means the source would be written to itself.")
        append(note, to: stack)

        let groups: [(String, String, [Kind], [String])] = [
            ("Images", "photo", [.image],
             ["jpg", "png", "webp", "heic", "tiff", "svg", "avif", "bmp"]),
            ("Documents", "doc.text", [.document],
             ["pdf", "docx", "pages", "ppt", "pptx", "txt", "md", "rtf",
              "rtfd", "textclipping", "html", "epub"]),
            ("Spreadsheets", "tablecells", [.sheet],
             ["xlsx", "xls", "ods", "csv", "tsv"]),
            ("Subtitles", "captions.bubble", [.subtitle], ["srt", "vtt"]),
            ("Audio", "waveform", [.audio],
             ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]),
            ("Video", "film", [.video],
             ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif"]),
            ("Archives", "archivebox", [.archive], ["zip", "tar", "gz", "rar"])
        ]

        for group in groups {
            var outputs: [String] = []
            for kind in group.2 {
                for fmt in Catalog.formats(for: kind) {
                    let lower = fmt.ext.lowercased()
                    if !outputs.contains(lower) { outputs.append(lower) }
                }
            }
            guard !outputs.isEmpty else { continue }

            append(compatibilityGroupHeader(group.0, symbol: group.1), to: stack)

            let gridRows: [[NSView]] = [
                [compatCell("", bold: true, align: .right)]
                    + outputs.map { compatCell($0.uppercased(), bold: true,
                                               color: .secondaryLabelColor) }
            ] + group.3.map { input in
                [compatCell(input.uppercased(), bold: true, align: .right)]
                    + outputs.map { output in
                        if output == input {
                            return compatCell("—", color: .tertiaryLabelColor)
                        }
                        return compatCell("✓", color: .secondaryLabelColor)
                    }
            }

            let grid = NSGridView(views: gridRows)
            grid.rowSpacing = 1
            grid.columnSpacing = 0
            grid.translatesAutoresizingMaskIntoConstraints = false
            grid.column(at: 0).xPlacement = .trailing
            grid.column(at: 0).width = 43
            for column in 1..<grid.numberOfColumns {
                grid.column(at: column).xPlacement = .center
                grid.column(at: column).width = 34
            }

            let card = SettingsCardView()
            card.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(grid)
            NSLayoutConstraint.activate([
                grid.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 9),
                grid.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -9),
                grid.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                grid.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
            ])
            append(card, to: stack)
        }

        let footer = hint("Engines that cannot run on this Mac are omitted. Compatibility reflects the current catalog, not a promise about third-party apps.")
        append(footer, to: stack)
        return scroll
    }

    private func sectionTitleRow(_ title: String, symbol: String) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let field = label(title, size: 12, weight: .semibold)
        wrap.addSubview(icon)
        wrap.addSubview(field)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 15),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            field.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: 23)
        ])
        return wrap
    }

    private func compatibilityGroupHeader(_ title: String, symbol: String) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .medium)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let field = label(title, size: 11.5, weight: .semibold)
        wrap.addSubview(icon)
        wrap.addSubview(field)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            field.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: 21)
        ])
        return wrap
    }

    private func compatCell(_ text: String, bold: Bool = false,
                            color: NSColor = .labelColor,
                            align: NSTextAlignment = .center) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = settingsFont(9.5, bold ? .semibold : .regular)
        field.textColor = color
        field.alignment = align
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    // MARK: Folders

    private func buildFolders() -> NSView {
        let (scroll, stack) = scrollStack(spacing: 8)
        append(sectionTitleRow("Folder Access", symbol: "folder"), to: stack)

        let accessCard = SettingsCardView()
        accessCard.translatesAutoresizingMaskIntoConstraints = false
        let access = NSStackView()
        access.orientation = .vertical
        access.alignment = .leading
        access.spacing = 0
        access.translatesAutoresizingMaskIntoConstraints = false
        let description = hint("Zest saves results beside the originals. It is unsandboxed, so macOS does not ask for folder bookmarks or Full Disk Access on the normal drag path.")
        description.maximumNumberOfLines = 4
        access.addArrangedSubview(description)
        description.widthAnchor.constraint(equalTo: access.widthAnchor).isActive = true
        access.setCustomSpacing(18, after: description)

        let status = label("No folder permissions required.", size: 12, weight: .medium)
        let statusWrap = NSView()
        statusWrap.translatesAutoresizingMaskIntoConstraints = false
        statusWrap.addSubview(status)
        NSLayoutConstraint.activate([
            status.centerXAnchor.constraint(equalTo: statusWrap.centerXAnchor),
            status.topAnchor.constraint(equalTo: statusWrap.topAnchor),
            status.bottomAnchor.constraint(equalTo: statusWrap.bottomAnchor),
            statusWrap.heightAnchor.constraint(equalToConstant: 46)
        ])
        access.addArrangedSubview(statusWrap)
        statusWrap.widthAnchor.constraint(equalTo: access.widthAnchor).isActive = true

        let openHome = linkButton("Open Home Folder")
        let home = FileManager.default.homeDirectoryForCurrentUser
        bind(openHome) { NSWorkspace.shared.open(home) }
        let linkWrap = NSView()
        linkWrap.translatesAutoresizingMaskIntoConstraints = false
        linkWrap.addSubview(openHome)
        NSLayoutConstraint.activate([
            openHome.trailingAnchor.constraint(equalTo: linkWrap.trailingAnchor),
            openHome.topAnchor.constraint(equalTo: linkWrap.topAnchor),
            openHome.bottomAnchor.constraint(equalTo: linkWrap.bottomAnchor),
            linkWrap.heightAnchor.constraint(equalToConstant: 23)
        ])
        access.addArrangedSubview(linkWrap)
        linkWrap.widthAnchor.constraint(equalTo: access.widthAnchor).isActive = true

        accessCard.addSubview(access)
        NSLayoutConstraint.activate([
            access.leadingAnchor.constraint(equalTo: accessCard.leadingAnchor, constant: 15),
            access.trailingAnchor.constraint(equalTo: accessCard.trailingAnchor, constant: -15),
            access.topAnchor.constraint(equalTo: accessCard.topAnchor, constant: 15),
            access.bottomAnchor.constraint(equalTo: accessCard.bottomAnchor, constant: -12)
        ])
        append(accessCard, to: stack)

        append(verticalGap(5), to: stack)
        append(sectionTitleRow("Useful Locations", symbol: "externaldrive"), to: stack)
        let locations = SettingsCardView()
        locations.translatesAutoresizingMaskIntoConstraints = false
        let locationList = NSStackView()
        locationList.orientation = .vertical
        locationList.alignment = .leading
        locationList.spacing = 0
        locationList.translatesAutoresizingMaskIntoConstraints = false
        append(locationRow("Home", path: home.path,
                           open: { NSWorkspace.shared.open(home) }), to: locationList)
        append(divider(), to: locationList)
        append(locationRow("Log", path: Log.url.path,
                           open: { NSWorkspace.shared.activateFileViewerSelecting([Log.url]) }), to: locationList)
        append(divider(), to: locationList)
        let temp = FileManager.default.temporaryDirectory
        append(locationRow("Temporary", path: temp.path,
                           open: { NSWorkspace.shared.open(temp) }), to: locationList)
        locations.addSubview(locationList)
        NSLayoutConstraint.activate([
            locationList.leadingAnchor.constraint(equalTo: locations.leadingAnchor),
            locationList.trailingAnchor.constraint(equalTo: locations.trailingAnchor),
            locationList.topAnchor.constraint(equalTo: locations.topAnchor),
            locationList.bottomAnchor.constraint(equalTo: locations.bottomAnchor)
        ])
        append(locations, to: stack)

        append(verticalGap(5), to: stack)
        append(sectionTitleRow("Output Behaviour", symbol: "arrow.up.forward.square"), to: stack)
        let outputCard = SettingsCardView()
        outputCard.translatesAutoresizingMaskIntoConstraints = false
        let outputList = NSStackView()
        outputList.orientation = .vertical
        outputList.alignment = .leading
        outputList.spacing = 0
        outputList.translatesAutoresizingMaskIntoConstraints = false
        append(behaviourRow("Single files", value: "Beside the original"), to: outputList)
        append(divider(), to: outputList)
        append(behaviourRow("Folders and archives", value: "Sibling output"), to: outputList)
        append(divider(), to: outputList)
        append(behaviourRow("Name collisions",
                            value: Prefs.collisionPolicy == "replace"
                                ? "Replace existing files" : "Keep both and number"),
               to: outputList)
        outputCard.addSubview(outputList)
        NSLayoutConstraint.activate([
            outputList.leadingAnchor.constraint(equalTo: outputCard.leadingAnchor),
            outputList.trailingAnchor.constraint(equalTo: outputCard.trailingAnchor),
            outputList.topAnchor.constraint(equalTo: outputCard.topAnchor),
            outputList.bottomAnchor.constraint(equalTo: outputCard.bottomAnchor)
        ])
        append(outputCard, to: stack)

        append(verticalGap(5), to: stack)
        append(sectionTitleRow("Permissions", symbol: "lock"), to: stack)
        let permissionsCard = SettingsCardView()
        permissionsCard.translatesAutoresizingMaskIntoConstraints = false
        let permissions = NSStackView()
        permissions.orientation = .vertical
        permissions.alignment = .leading
        permissions.spacing = 3
        permissions.translatesAutoresizingMaskIntoConstraints = false
        for line in [
            "Accessibility: optional, only for keyboard control.",
            "Screen Recording: not used.",
            "Automation: not used. Services and open-with are standard AppKit handoffs.",
            "Network: no sockets, no telemetry, no update checks."
        ] {
            let field = hint(line)
            permissions.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: permissions.widthAnchor).isActive = true
        }
        permissionsCard.addSubview(permissions)
        NSLayoutConstraint.activate([
            permissions.leadingAnchor.constraint(equalTo: permissionsCard.leadingAnchor, constant: 15),
            permissions.trailingAnchor.constraint(equalTo: permissionsCard.trailingAnchor, constant: -15),
            permissions.topAnchor.constraint(equalTo: permissionsCard.topAnchor, constant: 13),
            permissions.bottomAnchor.constraint(equalTo: permissionsCard.bottomAnchor, constant: -13)
        ])
        append(permissionsCard, to: stack)
        return scroll
    }

    private func locationRow(_ title: String, path: String,
                             open: @escaping () -> Void) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let name = label(title, size: 11.5, weight: .medium)
        name.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let value = label(path, size: 10, color: .secondaryLabelColor)
        value.font = .monospacedSystemFont(ofSize: 9.5, weight: .regular)
        value.lineBreakMode = .byTruncatingMiddle
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let link = linkButton("Open")
        bind(link) { open() }
        wrap.addSubview(name)
        wrap.addSubview(value)
        wrap.addSubview(link)
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 15),
            name.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            value.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 8),
            value.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            value.trailingAnchor.constraint(lessThanOrEqualTo: link.leadingAnchor, constant: -8),
            link.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -15),
            link.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            link.widthAnchor.constraint(equalToConstant: 32),
            wrap.heightAnchor.constraint(equalToConstant: 34)
        ])
        return wrap
    }

    private func behaviourRow(_ title: String, value: String) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let name = label(title, size: 12.5)
        let detail = label(value, size: 11.5, color: .secondaryLabelColor)
        detail.alignment = .right
        wrap.addSubview(name)
        wrap.addSubview(detail)
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 15),
            name.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            detail.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -15),
            detail.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 8),
            wrap.heightAnchor.constraint(equalToConstant: 32)
        ])
        return wrap
    }

    // MARK: About

    private func buildAbout() -> NSView {
        let (scroll, stack) = scrollStack(spacing: 8)

        let hero = NSStackView()
        hero.orientation = .vertical
        hero.alignment = .centerX
        hero.spacing = 5
        hero.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = AppIcon.image
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        hero.addArrangedSubview(icon)
        hero.setCustomSpacing(9, after: icon)

        let name = label("Zest", size: 20, weight: .semibold)
        hero.addArrangedSubview(name)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        hero.addArrangedSubview(label("Version \(version) (\(build))", size: 11,
                                     color: .secondaryLabelColor))
        let tagline = label("Local conversion for this Mac.\nNo network, no telemetry, no accounts.",
                            size: 11, color: .secondaryLabelColor)
        tagline.alignment = .center
        tagline.maximumNumberOfLines = 2
        hero.addArrangedSubview(tagline)
        hero.setCustomSpacing(12, after: tagline)

        let welcome = SettingsPillButton(title: "Getting Started…")
        bind(welcome) { WelcomeWindow.shared.show() }
        hero.addArrangedSubview(welcome)

        let links = NSStackView()
        links.orientation = .horizontal
        links.spacing = 12
        links.translatesAutoresizingMaskIntoConstraints = false
        let actions: [(String, () -> Void)] = [
            ("Open Log", { NSWorkspace.shared.open(Log.url) }),
            ("Refresh Engines", {
                ToolFinder.invalidate()
                self.refreshEngineRows()
            })
        ]
        for (title, action) in actions {
            let link = linkButton(title)
            bind(link) { action() }
            links.addArrangedSubview(link)
        }
        hero.addArrangedSubview(links)
        hero.setCustomSpacing(16, after: links)

        let heroWrap = NSView()
        heroWrap.translatesAutoresizingMaskIntoConstraints = false
        heroWrap.addSubview(hero)
        NSLayoutConstraint.activate([
            hero.centerXAnchor.constraint(equalTo: heroWrap.centerXAnchor),
            hero.topAnchor.constraint(equalTo: heroWrap.topAnchor, constant: 12),
            hero.bottomAnchor.constraint(equalTo: heroWrap.bottomAnchor),
            tagline.widthAnchor.constraint(lessThanOrEqualTo: heroWrap.widthAnchor, constant: -60)
        ])
        append(heroWrap, to: stack)

        append(sectionTitleRow("Catalog", symbol: "square.stack.3d.up"), to: stack)
        let stats = SettingsCardView()
        stats.translatesAutoresizingMaskIntoConstraints = false
        let statList = NSStackView()
        statList.orientation = .vertical
        statList.alignment = .leading
        statList.spacing = 0
        statList.translatesAutoresizingMaskIntoConstraints = false
        append(statRow("Format pairs", value: "\(Catalog.optionCount)"), to: statList)
        append(divider(), to: statList)
        append(statRow("Tools", value: "\(Catalog.toolCount)"), to: statList)
        append(divider(), to: statList)
        append(statRow("Actions", value: "\(Catalog.actions.count)"), to: statList)
        stats.addSubview(statList)
        NSLayoutConstraint.activate([
            statList.leadingAnchor.constraint(equalTo: stats.leadingAnchor),
            statList.trailingAnchor.constraint(equalTo: stats.trailingAnchor),
            statList.topAnchor.constraint(equalTo: stats.topAnchor),
            statList.bottomAnchor.constraint(equalTo: stats.bottomAnchor)
        ])
        append(stats, to: stack)

        append(verticalGap(4), to: stack)
        append(sectionTitleRow("Engines", symbol: "cpu"), to: stack)
        let engineCard = SettingsCardView()
        engineCard.translatesAutoresizingMaskIntoConstraints = false
        let engines = NSStackView()
        engines.orientation = .vertical
        engines.alignment = .leading
        engines.spacing = 4
        engines.translatesAutoresizingMaskIntoConstraints = false
        aboutEngineStack = engines
        engineCard.addSubview(engines)
        NSLayoutConstraint.activate([
            engines.leadingAnchor.constraint(equalTo: engineCard.leadingAnchor, constant: 15),
            engines.trailingAnchor.constraint(equalTo: engineCard.trailingAnchor, constant: -15),
            engines.topAnchor.constraint(equalTo: engineCard.topAnchor, constant: 12),
            engines.bottomAnchor.constraint(equalTo: engineCard.bottomAnchor, constant: -12)
        ])
        append(engineCard, to: stack)
        refreshEngineRows()

        append(verticalGap(4), to: stack)
        append(sectionTitleRow("Reset", symbol: "arrow.counterclockwise"), to: stack)
        let resetCard = SettingsCardView()
        resetCard.translatesAutoresizingMaskIntoConstraints = false
        let resetStack = NSStackView()
        resetStack.orientation = .vertical
        resetStack.alignment = .leading
        resetStack.spacing = 5
        resetStack.translatesAutoresizingMaskIntoConstraints = false
        let resetText = hint("Return every preference, format default and modifier to its initial value. Files are not touched.")
        resetText.maximumNumberOfLines = 3
        resetStack.addArrangedSubview(resetText)
        resetText.widthAnchor.constraint(equalTo: resetStack.widthAnchor).isActive = true
        let reset = linkButton("Reset All Settings…")
        bind(reset) { self.resetSettings() }
        resetStack.addArrangedSubview(reset)
        resetCard.addSubview(resetStack)
        NSLayoutConstraint.activate([
            resetStack.leadingAnchor.constraint(equalTo: resetCard.leadingAnchor, constant: 15),
            resetStack.trailingAnchor.constraint(equalTo: resetCard.trailingAnchor, constant: -15),
            resetStack.topAnchor.constraint(equalTo: resetCard.topAnchor, constant: 13),
            resetStack.bottomAnchor.constraint(equalTo: resetCard.bottomAnchor, constant: -13)
        ])
        append(resetCard, to: stack)

        let footer = label("Zest is ad-hoc signed · com.zest.app · everything stays on this Mac.",
                           size: 9.5, color: .tertiaryLabelColor)
        footer.alignment = .center
        append(footer, to: stack)
        return scroll
    }

    private func statRow(_ title: String, value: String) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let name = label(title, size: 12.5)
        let number = label(value, size: 12.5, weight: .medium)
        number.alignment = .right
        wrap.addSubview(name)
        wrap.addSubview(number)
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 15),
            name.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            number.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -15),
            number.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: 32)
        ])
        return wrap
    }

    private func refreshEngineRows() {
        guard let stack = aboutEngineStack else { return }
        stack.subviews.forEach { $0.removeFromSuperview() }
        let rows: [(String, String?)] = [
            ("ffmpeg", ToolFinder.ffmpeg),
            ("ffprobe", ToolFinder.ffprobe),
            ("cwebp", ToolFinder.cwebp),
            ("ExifTool", ToolFinder.exiftool),
            ("LibreOffice", ToolFinder.soffice),
            ("Pages", Capability.pagesOutput ? "/Applications/Pages.app" : nil)
        ]
        for (name, path) in rows {
            let dot = NSTextField(labelWithString: "●")
            dot.font = .systemFont(ofSize: 7)
            dot.textColor = path == nil ? .tertiaryLabelColor : .systemGreen
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
            let key = label(name, size: 11, weight: .medium)
            key.widthAnchor.constraint(equalToConstant: 76).isActive = true
            let value = label(path ?? "not found", size: 9.5,
                              color: path == nil ? .tertiaryLabelColor : .secondaryLabelColor)
            value.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
            value.lineBreakMode = .byTruncatingMiddle
            value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [dot, key, value])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func chooseFFmpeg() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use ffmpeg"
        panel.message = "Choose an ffmpeg executable"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Prefs.setToolOverride("ffmpeg", url.path)
        ToolFinder.invalidate()
        refreshEngineRows()
    }

    private func resetSettings() {
        let alert = NSAlert()
        alert.messageText = "Reset all settings?"
        alert.informativeText = "Every preference, including format defaults and drag modifiers, returns to its initial value. Files are not touched."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Prefs.defaults.removePersistentDomain(forName: "com.zest.app")
        Prefs.register()
        selectedFormat = "jpg"
        applyAppearance()
        show(tab: .general)
        NotificationCenter.default.post(name: .zestSettingsChanged, object: nil)
    }

    // MARK: Test seams

    /// Development-only hook used to photograph one tab of the settings
    /// layout. Not called by the shipping app.
    func showTabForPreview(_ index: Int) {
        show(tab: Tab(rawValue: index) ?? .general)
    }

    /// Renders the current tab to PNG. The glass material is replaced with the
    /// solid window colour because `NSVisualEffectView` does not cache cleanly
    /// into an offscreen bitmap.
    func snapshotForPreview(to url: URL) -> Bool {
        guard let window, let content = window.contentView else { return false }
        window.appearance = NSAppearance(named: .darkAqua)
        let savedEffect = effect.isHidden
        let savedBackground = root.layer?.backgroundColor
        effect.isHidden = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        defer {
            effect.isHidden = savedEffect
            root.layer?.backgroundColor = savedBackground
        }
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            return false
        }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: url)
            return true
        } catch {
            return false
        }
    }

    /// Used by `Zest uitest` to build every tab and every format page in one
    /// process. The settings UI has no other non-interactive entry point.
    func exerciseForTesting() {
        for index in 0..<Tab.allCases.count {
            guard let tab = Tab(rawValue: index) else { continue }
            show(tab: tab)
        }
        guard let formats = Tab(rawValue: Tab.formats.rawValue) else { return }
        show(tab: formats)
        for ext in allFormatExts {
            selectFormat(ext)
        }
    }

    // MARK: Appearance

    private func applyAppearance() {
        guard let window else { return }
        switch Prefs.appearance {
        case .glass:
            effect.isHidden = false
            root.layer?.backgroundColor = NSColor.clear.cgColor
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
        case .solid:
            effect.isHidden = true
            root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = false
        }
    }
}

// MARK: - Control handler

private final class SettingsControlHandler: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire() {
        action()
    }
}

extension Notification.Name {
    static let zestSettingsChanged = Notification.Name("ZestSettingsChanged")
}
