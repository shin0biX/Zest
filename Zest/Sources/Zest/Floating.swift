import AppKit
import QuickLookThumbnailing

// MARK: - Floating files panel

/// The Float action: a non-activating panel of file thumbnails that can be dragged
/// straight back out to Finder or another app.
final class FloatingFiles {
    static let shared = FloatingFiles()

    private var panels: [NSPanel] = []
    private var lastURLs: [URL] = []
    private var cascade: CGFloat = 0

    static func show(_ urls: [URL]) {
        onMain { shared.present(urls, behavior: Prefs.floatBehavior) }
    }

    private func present(_ urls: [URL], behavior: FloatBehavior) {
        guard !urls.isEmpty else { return }

        var incoming = urls
        if behavior == .addToExisting, let current = panels.last {
            // Re-present the active Float with the union, keeping one panel.
            let existing = Set(lastURLs.map(\.path))
            incoming = lastURLs + urls.filter { !existing.contains($0.path) }
            dismiss(current)
        }
        incoming = incoming.reduce(into: []) { result, url in
            if !result.contains(where: { $0.path == url.path }) { result.append(url) }
        }
        lastURLs = incoming
        build(incoming)
    }

    private func build(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        let width: CGFloat = 304
        let headerHeight: CGFloat = 42
        let rowHeight: CGFloat = 62
        let visibleRows = min(urls.count, 6)
        let height = headerHeight + CGFloat(visibleRows) * rowHeight

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        let title = NSTextField(labelWithString: urls.count == 1
            ? "Floating file"
            : "Floating · \(urls.count) files")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 14, y: height - 28, width: width - 58, height: 18)
        title.autoresizingMask = [.minYMargin]
        effect.addSubview(title)

        let close = ActionButton(frame: NSRect(x: width - 30, y: height - 30, width: 18, height: 18))
        close.image = NSImage(systemSymbolName: "xmark.circle.fill",
                              accessibilityDescription: "Close")
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.target = close
        close.action = #selector(ActionButton.fire)
        close.autoresizingMask = [.minYMargin, .minXMargin]
        close.onPress = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.dismiss(panel)
        }
        effect.addSubview(close)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height - headerHeight))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = urls.count > 6
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .allowed

        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: width,
                                                 height: CGFloat(urls.count) * rowHeight))
        document.autoresizingMask = [.width]
        for (index, url) in urls.enumerated() {
            let row = FloatingRow(url: url,
                                  frame: NSRect(x: 0, y: CGFloat(index) * rowHeight,
                                                width: width, height: rowHeight))
            row.autoresizingMask = [.width]
            row.onClose = { [weak self, weak row, weak panel] in
                guard let self, let row else { return }
                self.lastURLs.removeAll { $0.path == url.path }
                row.removeFromSuperview()
                self.reflow(document, rowHeight: rowHeight)
                if document.subviews.isEmpty, let panel {
                    self.dismiss(panel)
                }
            }
            document.addSubview(row)
        }
        scroll.documentView = document
        effect.addSubview(scroll)

        // Place the panel beside the pointer, clamped to the active screen.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = mouse.x + 18 + cascade
        var y = mouse.y - height - 18 - cascade
        x = min(max(x, screen.minX + 8), screen.maxX - width - 8)
        y = min(max(y, screen.minY + 8), screen.maxY - height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panels.append(panel)
        cascade = cascade >= 88 ? 0 : cascade + 22
        panel.orderFrontRegardless()
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1
        }
    }

    private func reflow(_ document: NSView, rowHeight: CGFloat) {
        var index = 0
        for case let row as FloatingRow in document.subviews {
            row.frame.origin.y = CGFloat(index) * rowHeight
            index += 1
        }
        document.frame.size.height = max(rowHeight, CGFloat(index) * rowHeight)
    }

    private func dismiss(_ panel: NSPanel) {
        panel.orderOut(nil)
        panel.close()
        panels.removeAll { $0 === panel }
        if panels.isEmpty {
            cascade = 0
            lastURLs = []
        }
    }
}

// MARK: - Closure button

private final class ActionButton: NSButton {
    var onPress: (() -> Void)?

    @objc func fire() {
        onPress?()
    }
}

// MARK: - Row

private final class FloatingRow: NSView, NSDraggingSource {
    let url: URL
    var onClose: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    init(url: URL, frame: NSRect) {
        self.url = url
        super.init(frame: frame)
        wantsLayer = true

        iconView.frame = NSRect(x: 10, y: 9, width: 44, height: 44)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = NSWorkspace.shared.icon(forFile: url.path)
        addSubview(iconView)

        titleLabel.frame = NSRect(x: 64, y: 12, width: frame.width - 100, height: 17)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.stringValue = url.lastPathComponent
        titleLabel.autoresizingMask = [.width]
        addSubview(titleLabel)

        detailLabel.frame = NSRect(x: 64, y: 31, width: frame.width - 100, height: 15)
        detailLabel.font = .systemFont(ofSize: 10.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.autoresizingMask = [.width]
        if url.isDirectory {
            detailLabel.stringValue = "Folder"
        } else {
            detailLabel.stringValue = "\(url.pathExtension.uppercased()) · \(Bytes.format(url.fileSize))"
        }
        addSubview(detailLabel)

        let close = NSButton(image: NSImage(systemSymbolName: "xmark",
                                            accessibilityDescription: "Close")!,
                             target: self, action: #selector(closeTapped))
        close.isBordered = false
        close.contentTintColor = .tertiaryLabelColor
        close.frame = NSRect(x: frame.width - 30, y: 21, width: 18, height: 18)
        close.autoresizingMask = [.minXMargin]
        addSubview(close)

        loadThumbnail()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 1, alpha: 0.06).setFill()
        NSBezierPath(roundedRect: NSRect(x: 6, y: 3, width: bounds.width - 12,
                                         height: bounds.height - 6),
                     xRadius: 9, yRadius: 9).fill()
    }

    private func loadThumbnail() {
        guard !url.isDirectory else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 44, height: 44),
            scale: scale,
            representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let self, let image = rep?.nsImage else { return }
            onMain { self.iconView.image = image }
        }
    }

    @objc private func closeTapped() {
        onClose?()
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 {
            NSWorkspace.shared.open(url)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let image = iconView.image ?? NSWorkspace.shared.icon(forFile: url.path)
        let side: CGFloat = 48
        item.setDraggingFrame(NSRect(x: 8, y: 7, width: side, height: side),
                              contents: image)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .copy : .copy
    }
}

// MARK: - Flipped container

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
