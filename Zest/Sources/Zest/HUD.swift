import AppKit

// MARK: - HUD

final class HUDToken {
    let id = UUID()
    let title: String
    var statusLabel: NSTextField!
    var spinner: NSProgressIndicator!
    var revealButton: NSButton!
    var icon: NSImageView!
    var row: NSView!
    var outputs: [URL] = []
    var finished = false
    var success = false
    init(title: String) { self.title = title }
}

final class HUDController {
    static let shared = HUDController()

    private init() {}

    private var panel: NSPanel?
    private var effect: NSVisualEffectView?
    private var stack: NSStackView?
    private var tokens: [HUDToken] = []
    private var hideWork: DispatchWorkItem?
    private var closeButton: NSButton?
    private let width: CGFloat = 404

    private func ensurePanel() {
        if panel != nil { return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 80),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.animationBehavior = .utilityWindow

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        p.contentView = effect

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])

        let close = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill",
                                            accessibilityDescription: "Close")!,
                             target: self, action: #selector(dismiss))
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.translatesAutoresizingMaskIntoConstraints = false
        close.isHidden = true
        effect.addSubview(close)
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: effect.topAnchor, constant: 8),
            close.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -8),
            close.widthAnchor.constraint(equalToConstant: 18),
            close.heightAnchor.constraint(equalToConstant: 18)
        ])

        self.panel = p
        self.effect = effect
        self.stack = stack
        self.closeButton = close
    }

    func begin(_ title: String) -> HUDToken {
        ensurePanel()
        hideWork?.cancel()
        let token = HUDToken(title: title)

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        row.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(titleLabel)

        let status = NSTextField(labelWithString: "Working…")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(status)

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)
        row.addSubview(spinner)

        let reveal = NSButton(title: "Show", target: self, action: #selector(revealTapped(_:)))
        reveal.bezelStyle = .inline
        reveal.controlSize = .small
        reveal.font = .systemFont(ofSize: 11, weight: .medium)
        reveal.translatesAutoresizingMaskIntoConstraints = false
        reveal.isHidden = true
        reveal.tag = tokens.count
        row.addSubview(reveal)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 3),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: reveal.leadingAnchor, constant: -8),

            status.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            status.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            status.trailingAnchor.constraint(lessThanOrEqualTo: reveal.leadingAnchor, constant: -8),

            spinner.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -2),
            spinner.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),

            reveal.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            reveal.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

        token.row = row
        token.statusLabel = status
        token.spinner = spinner
        token.revealButton = reveal
        token.icon = icon
        tokens.append(token)
        stack?.addArrangedSubview(row)
        row.widthAnchor.constraint(equalToConstant: width - 28).isActive = true

        revealTappedMap[reveal] = token
        layout()
        show()
        return token
    }

    private var revealTappedMap: [NSButton: HUDToken] = [:]

    func setStatus(_ token: HUDToken, _ text: String) {
        token.statusLabel.stringValue = text
    }

    func succeed(_ token: HUDToken, outputs: [URL], note: String? = nil) {
        token.finished = true
        token.success = true
        token.outputs = outputs
        token.spinner.stopAnimation(nil)
        token.spinner.isHidden = true
        token.revealButton.isHidden = outputs.isEmpty
        token.icon.contentTintColor = .systemGreen
        token.icon.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                                   accessibilityDescription: nil)
        if let note {
            token.statusLabel.stringValue = note
        } else if outputs.count == 1 {
            token.statusLabel.stringValue = "Done · \(outputs[0].lastPathComponent)"
        } else {
            token.statusLabel.stringValue = "Done · \(outputs.count) files"
        }
        settle()
    }

    func fail(_ token: HUDToken, message: String) {
        token.finished = true
        token.success = false
        token.spinner.stopAnimation(nil)
        token.spinner.isHidden = true
        token.icon.contentTintColor = .systemRed
        token.icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                   accessibilityDescription: nil)
        token.statusLabel.stringValue = message
        token.statusLabel.textColor = .systemRed
        token.revealButton.isHidden = true
        Log.write("FAILED \(token.title): \(message)")
        settle()
    }

    private func settle() {
        guard tokens.allSatisfy({ $0.finished }) else { return }
        closeButton?.isHidden = false
        if tokens.allSatisfy({ $0.success }) {
            hideWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.dismiss() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: work)
        }
    }

    @objc private func revealTapped(_ sender: NSButton) {
        guard let token = revealTappedMap[sender], !token.outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(token.outputs)
    }

    @objc func dismiss() {
        hideWork?.cancel()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        effect = nil
        stack = nil
        closeButton = nil
        tokens.removeAll()
        revealTappedMap.removeAll()
    }

    private func show() {
        guard let panel else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    private func layout() {
        guard let panel, let effect, let stack else { return }
        effect.layoutSubtreeIfNeeded()
        let height = max(56, stack.fittingSize.height)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: screen.maxX - width - 16,
                           y: screen.minY + 16,
                           width: width,
                           height: height)
        panel.setFrame(frame, display: true)
    }
}
