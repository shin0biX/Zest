import AppKit
import QuartzCore

// MARK: - Overlay panel

final class OverlayPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        // Escape is delivered by the optional key tap; this covers the demo window.
        onCancel?()
    }
}

// MARK: - Overlay controller

final class OverlayController {
    var onCommit: ((DragContext, WheelChoice, WheelMode) -> Void)?

    private var panel: OverlayPanel?
    private var wheel: WheelView?
    private var context: DragContext?
    private var mode: WheelMode = .convert
    private var demoMode = false
    private var screen: NSScreen?
    private var closeWork: DispatchWorkItem?

    var isOpen: Bool { panel != nil }

    /// True while the pointer sits anywhere on the wheel disc. A mouse-up there
    /// is a drop in flight, not a cancel outside the wheel.
    var isPointerOverWheel: Bool {
        guard let wheel, let window = wheel.window else { return false }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let local = wheel.convert(inWindow, from: nil)
        let dx = local.x - wheel.center.x
        let dy = local.y - wheel.center.y
        return hypot(dx, dy) <= wheel.outerRadius
    }

    /// Called shortly after the mouse button is released. A release outside
    /// the wheel is a cancel and closes immediately. A release on the wheel may
    /// be the drop the drag server is about to deliver, so the panel stays up
    /// until `performDragOperation` (which commits and closes) or a fallback
    /// timeout.
    func handleDisarm() {
        guard panel != nil else { return }
        guard isPointerOverWheel else {
            Log.write("Wheel disarm outside")
            close()
            return
        }
        closeWork?.cancel()
        Log.write("Wheel disarm on wheel; waiting for drop")
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closeWork = nil
            if self.panel != nil { Log.write("Wheel disarm timeout") }
            self.close()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func arm(context: DragContext, mode: WheelMode) {
        demoMode = false
        present(context: context, mode: mode)
    }

    func presentDemo() {
        demoMode = true
        let sample = DemoAsset.url()
        let context = DragContext(urls: [sample], anchor: NSEvent.mouseLocation,
                                  kind: .image)
        present(context: context, mode: .convert)
    }

    private func present(context: DragContext, mode: WheelMode) {
        guard panel == nil else { return }
        closeWork?.cancel()
        closeWork = nil
        self.context = context
        self.mode = mode

        let screen = NSScreen.screens.first { $0.frame.contains(context.anchor) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let panel = OverlayPanel(contentRect: screen.frame,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.onCancel = { [weak self] in self?.close() }

        let wheel = WheelView(frame: NSRect(origin: .zero, size: screen.frame.size))
        wheel.autoresizingMask = [.width, .height]
        wheel.surfaces = Catalog.surfaces(for: context.urls)
        wheel.emphasize(mode)
        wheel.count = context.urls.count
        wheel.kind = context.kind
        wheel.demo = demoMode

        var center = NSPoint(x: context.anchor.x - screen.frame.minX,
                             y: context.anchor.y - screen.frame.minY)
        let margin: CGFloat = wheel.outerRadius + 14
        center.x = min(max(center.x, min(margin, screen.frame.width / 2)),
                       max(screen.frame.width - margin, screen.frame.width / 2))
        center.y = min(max(center.y, min(margin, screen.frame.height / 2)),
                       max(screen.frame.height - margin, screen.frame.height / 2))
        wheel.center = center

        wheel.onPick = { [weak self] choice, choiceMode in
            self?.commit(choice, mode: choiceMode)
        }
        wheel.onHover = { _ in }

        panel.contentView = wheel

        self.panel = panel
        self.wheel = wheel
        self.screen = screen
        logWheel(wheel, anchor: context.anchor, screen: screen)

        if demoMode {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            panel.orderFrontRegardless()
        }

        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func setMode(_ mode: WheelMode) {
        guard let context, let wheel, let panel, let screen else { return }
        self.mode = mode
        wheel.emphasize(mode)
        wheel.hovered = nil
        wheel.needsDisplay = true
        panel.invalidateShadow()
        logWheel(wheel, anchor: context.anchor, screen: screen)
    }

    /// One machine-readable line per arm and per mode switch. The external drag
    /// harness reads the anchor, screen, emphasized ring radius, and choice ids.
    private func logWheel(_ wheel: WheelView, anchor: NSPoint, screen: NSScreen) {
        let ring = wheel.ring(for: wheel.emphasis) ?? wheel.rings.first
        let ids = ring?.choices.map(\.id).joined(separator: ",") ?? ""
        let rings = wheel.rings.map { "\($0.mode.rawValue):\($0.choices.count)" }
            .joined(separator: ",")
        Log.write("Wheel mode=\(wheel.emphasis.rawValue) count=\(ring?.choices.count ?? 0) "
            + "anchor=\(Int(anchor.x)),\(Int(anchor.y)) "
            + "screen=\(Int(screen.frame.width))x\(Int(screen.frame.height)) "
            + "radius=\(Int(ring?.mid ?? 0)) outer=\(Int(WheelView.outerRadius)) "
            + "rings=\(rings) choices=\(ids)")
    }

    func close() {
        closeWork?.cancel()
        closeWork = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        wheel = nil
        context = nil
        screen = nil
    }

    /// Keyboard navigation from the optional event tap (Accessibility).
    /// Returns true when the key was consumed.
    func handleKey(_ code: UInt16) -> Bool {
        guard panel != nil, let wheel else { return false }
        switch code {
        case 53: // escape
            close()
            return true
        case 123, 126: // left / up
            wheel.step(-1)
            return true
        case 124, 125: // right / down
            wheel.step(1)
            return true
        case 36, 76: // return / enter
            if let choice = wheel.hoveredChoice {
                commit(choice, mode: wheel.hoveredMode ?? mode)
            } else {
                close()
            }
            return true
        default:
            return false
        }
    }

    private func commit(_ choice: WheelChoice?, mode: WheelMode? = nil) {
        let ctx = context
        let resolved = mode ?? self.mode
        Log.write("Choice \(choice?.id ?? "cancel") mode=\(resolved.rawValue)")
        close()
        guard let ctx, let choice else { return }
        onCommit?(ctx, choice, resolved)
    }
}

// MARK: - Wheel view

struct WheelHit: Equatable {
    let ring: Int
    let index: Int
}

struct WheelRing {
    let mode: WheelMode
    let choices: [WheelChoice]
    let inner: CGFloat
    let outer: CGFloat

    var mid: CGFloat { (inner + outer) / 2 }
    var step: CGFloat { .pi * 2 / CGFloat(max(1, choices.count)) }
    /// Wedge 0 is centered at the top, then clockwise.
    var startAngle: CGFloat { .pi / 2 + step / 2 }
    func midAngle(_ index: Int) -> CGFloat {
        startAngle - (CGFloat(index) + 0.5) * step
    }
}

final class WheelView: NSView {
    /// Radii in points. The outer disc is large enough to hold three labelled
    /// rings (formats, tools, actions) at once.
    static let outerRadius: CGFloat = 340
    static let hubRadius: CGFloat = 84

    var outerRadius: CGFloat { Self.outerRadius }
    var innerRadius: CGFloat { Self.hubRadius }

    /// Outermost first. Assigned by the controller from `Catalog.surfaces`.
    var surfaces: [(mode: WheelMode, choices: [WheelChoice])] = [] {
        didSet { rebuildRings() }
    }
    private(set) var rings: [WheelRing] = []

    /// The ring the trigger modifier selected. It is drawn brighter; every
    /// ring stays visible and hit-testable.
    private(set) var emphasis: WheelMode = .convert
    var count: Int = 1
    var kind: Kind?
    var demo = false
    var showBackdrop = true
    var hovered: WheelHit? {
        didSet { if oldValue != hovered { needsDisplay = true } }
    }
    var center: NSPoint = .zero {
        didSet { needsDisplay = true }
    }

    /// Called with the picked choice and the ring it came from. `nil` cancels.
    var onPick: ((WheelChoice?, WheelMode) -> Void)?
    var onHover: ((WheelChoice?) -> Void)?

    private var tracking: NSTrackingArea?
    private var lastHoverSound = Date.distantPast

    /// The choices of the emphasized ring, kept for callers that only need the
    /// armed surface (logging and the external harness).
    var choices: [WheelChoice] { ring(for: emphasis)?.choices ?? rings.first?.choices ?? [] }

    var hoveredChoice: WheelChoice? {
        guard let hovered, hovered.ring < rings.count,
              hovered.index < rings[hovered.ring].choices.count else { return nil }
        return rings[hovered.ring].choices[hovered.index]
    }

    var hoveredMode: WheelMode? {
        guard let hovered, hovered.ring < rings.count else { return nil }
        return rings[hovered.ring].mode
    }

    func ring(for mode: WheelMode) -> WheelRing? { rings.first { $0.mode == mode } }

    func emphasize(_ mode: WheelMode) {
        emphasis = rings.contains { $0.mode == mode } ? mode : (rings.first?.mode ?? mode)
        needsDisplay = true
    }

    private func rebuildRings() {
        let active = surfaces.filter { !$0.choices.isEmpty }
        guard !active.isEmpty else {
            rings = []
            needsDisplay = true
            return
        }
        let width = (Self.outerRadius - Self.hubRadius) / CGFloat(active.count)
        rings = active.enumerated().map { index, surface in
            let outer = Self.outerRadius - CGFloat(index) * width
            return WheelRing(mode: surface.mode, choices: surface.choices,
                             inner: outer - width, outer: outer)
        }
        if !rings.contains(where: { $0.mode == emphasis }) {
            emphasis = rings[0].mode
        }
        if let hovered, hovered.ring >= rings.count { self.hovered = nil }
        needsDisplay = true
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Drag destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Log.write("Drop enter")
        hover(at: convert(sender.draggingLocation, from: nil))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hover(at: convert(sender.draggingLocation, from: nil))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        Log.write("Drop exit")
        hovered = nil
        needsDisplay = true
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Log.write("Drop perform")
        let point = convert(sender.draggingLocation, from: nil)
        hover(at: point)
        onPick?(choice(at: point), hoveredMode ?? emphasis)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeAlways, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    // MARK: Geometry

    /// A wedge from `inner` to `outer`, centred on `startAngle - (index+0.5)·step`.
    /// The outer arc runs counter-clockwise from the lower angle to the higher
    /// one; the inner arc runs back clockwise. Running either arc the long way
    /// round paints the whole annulus and buries every other slice.
    private func wedgePath(ring: WheelRing, index: Int, inset: CGFloat = 0) -> NSBezierPath {
        let gap = min(0.016, ring.step * 0.10)
        let a0 = ring.startAngle - CGFloat(index + 1) * ring.step + gap / 2
        let a1 = ring.startAngle - CGFloat(index) * ring.step - gap / 2
        let rOut = ring.outer - 3 - inset
        let rIn = ring.inner + 3 + inset
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: rOut,
                       startAngle: a0 * 180 / .pi, endAngle: a1 * 180 / .pi,
                       clockwise: false)
        path.line(to: NSPoint(x: center.x + cos(a1) * rIn,
                              y: center.y + sin(a1) * rIn))
        path.appendArc(withCenter: center, radius: rIn,
                       startAngle: a1 * 180 / .pi, endAngle: a0 * 180 / .pi,
                       clockwise: true)
        path.close()
        return path
    }

    func hit(at point: NSPoint) -> WheelHit? {
        guard !rings.isEmpty else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let r = hypot(dx, dy)
        guard r >= Self.hubRadius, r <= Self.outerRadius,
              let ringIndex = rings.firstIndex(where: { r >= $0.inner - 0.5 && r <= $0.outer + 0.5 })
        else { return nil }
        let ring = rings[ringIndex]
        var theta = atan2(dy, dx)
        if theta < 0 { theta += .pi * 2 }
        var delta = (ring.startAngle - theta).truncatingRemainder(dividingBy: .pi * 2)
        if delta < 0 { delta += .pi * 2 }
        let index = Int(delta / ring.step)
        return index < ring.choices.count ? WheelHit(ring: ringIndex, index: index) : nil
    }

    func hover(at point: NSPoint) {
        guard !rings.isEmpty else { return }
        let hit = self.hit(at: point)
        if hit != hovered {
            hovered = hit
            playHoverFeedback()
            onHover?(hoveredChoice)
        }
    }

    func choice(at point: NSPoint) -> WheelChoice? {
        guard let hit = hit(at: point), hit.ring < rings.count,
              hit.index < rings[hit.ring].choices.count else { return nil }
        return rings[hit.ring].choices[hit.index]
    }

    func mode(at point: NSPoint) -> WheelMode? {
        guard let hit = hit(at: point), hit.ring < rings.count else { return nil }
        return rings[hit.ring].mode
    }

    private func playHoverFeedback() {
        guard Prefs.playSound else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHoverSound) > 0.045 else { return }
        lastHoverSound = now
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        if showBackdrop { drawBackdrop(ctx) }
        guard !rings.isEmpty else { return }
        drawRings()
        drawHub()
    }

    private func drawBackdrop(_ ctx: CGContext) {
        let glowRect = NSRect(x: center.x - outerRadius - 26,
                              y: center.y - outerRadius - 26,
                              width: (outerRadius + 26) * 2,
                              height: (outerRadius + 26) * 2)
        let gradient = NSGradient(colors: [
            NSColor(calibratedWhite: 0, alpha: 0.30),
            NSColor(calibratedWhite: 0, alpha: 0.0)
        ])!
        gradient.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)
        _ = ctx
    }

    private func drawRings() {
        for (ringIndex, ring) in rings.enumerated() {
            let emphasized = ring.mode == emphasis
            for (index, choice) in ring.choices.enumerated() {
                let hover = hovered == WheelHit(ring: ringIndex, index: index)
                let accent = ring.mode.accent
                let path = wedgePath(ring: ring, index: index)
                let fill = hover
                    ? accent.withAlphaComponent(0.96)
                    : NSColor(calibratedWhite: emphasized ? 0.13 : 0.08, alpha: 0.92)
                fill.setFill()
                path.fill()
                let stroke = hover
                    ? NSColor(calibratedWhite: 1, alpha: 0.32)
                    : accent.withAlphaComponent(emphasized ? 0.36 : 0.18)
                stroke.setStroke()
                path.lineWidth = 1
                path.stroke()
                drawContent(choice, ring: ring, index: index, hover: hover)
            }
        }

        NSColor(calibratedWhite: 1, alpha: 0.09).setStroke()
        for ring in rings where ring.outer < outerRadius - 1 {
            let circle = NSBezierPath(ovalIn: NSRect(x: center.x - ring.outer,
                                                     y: center.y - ring.outer,
                                                     width: ring.outer * 2,
                                                     height: ring.outer * 2))
            circle.lineWidth = 1
            circle.stroke()
        }
        let rim = NSBezierPath(ovalIn: NSRect(x: center.x - outerRadius,
                                              y: center.y - outerRadius,
                                              width: outerRadius * 2,
                                              height: outerRadius * 2))
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
        rim.lineWidth = 1.5
        rim.stroke()
    }

    private func drawContent(_ choice: WheelChoice, ring: WheelRing,
                             index: Int, hover: Bool) {
        let angle = ring.midAngle(index)
        let px = center.x + cos(angle) * ring.mid
        let py = center.y + sin(angle) * ring.mid
        let available = max(46, 2 * ring.mid * sin(ring.step / 2) - 12)
        let accent = ring.mode.accent

        switch choice.payload {
        case .format(let fmt):
            drawBadge(fmt.ext, at: NSPoint(x: px, y: py + 14), hover: hover, accent: accent)
        case .tool, .action:
            if let image = symbol(choice.symbol, pointSize: hover ? 19 : 17,
                                  color: hover ? .white : accent.withAlphaComponent(0.92)) {
                let size = image.size
                image.draw(in: NSRect(x: px - size.width / 2, y: py + 7,
                                      width: size.width, height: size.height))
            }
        }

        let font = NSFont.systemFont(ofSize: choice.title.count > 10 ? 10.5 : 11.5,
                                     weight: .semibold)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: hover ? NSColor.white : NSColor(calibratedWhite: 1, alpha: 0.90),
            .paragraphStyle: para
        ]
        let rect = NSRect(x: px - available / 2, y: py - 22,
                          width: available, height: 16)
        (choice.title as NSString).draw(in: rect, withAttributes: attrs)
    }

    /// Formats get an extension badge instead of a symbol: eight image formats
    /// sharing one `photo` glyph is unreadable at a glance.
    private func drawBadge(_ ext: String, at point: NSPoint, hover: Bool, accent: NSColor) {
        let label = ext == "gz" ? "GZIP" : ext.uppercased()
        let text = label as NSString
        let font = NSFont.systemFont(ofSize: 9, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: hover ? accent : accent.withAlphaComponent(0.95)
        ]
        let textSize = text.size(withAttributes: attrs)
        let width = min(52, max(28, textSize.width + 12))
        let rect = NSRect(x: point.x - width / 2, y: point.y - 9, width: width, height: 18)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        (hover ? NSColor.white : accent.withAlphaComponent(0.18)).setFill()
        path.fill()
        accent.withAlphaComponent(hover ? 0.9 : 0.55).setStroke()
        path.lineWidth = 1
        path.stroke()
        text.draw(in: NSRect(x: point.x - textSize.width / 2,
                             y: point.y - textSize.height / 2,
                             width: textSize.width, height: textSize.height),
                  withAttributes: attrs)
    }

    private func drawHub() {
        let hubRect = NSRect(x: center.x - innerRadius,
                             y: center.y - innerRadius,
                             width: innerRadius * 2,
                             height: innerRadius * 2)
        let circle = NSBezierPath(ovalIn: hubRect)
        NSColor(calibratedWhite: 0.06, alpha: 0.96).setFill()
        circle.fill()
        let activeMode = hoveredMode ?? emphasis
        (hovered == nil
            ? NSColor(calibratedWhite: 1, alpha: 0.14)
            : activeMode.accent.withAlphaComponent(0.8)).setStroke()
        circle.lineWidth = 1.5
        circle.stroke()

        let cancelHighlight = hovered == nil && !demo
        let title = cancelHighlight ? "CANCEL" : activeMode.title.uppercased()
        let titleColor = cancelHighlight
            ? NSColor(calibratedRed: 1, green: 0.42, blue: 0.38, alpha: 1)
            : activeMode.accent
        let para = NSMutableParagraphStyle()
        para.alignment = .center

        (title as NSString).draw(
            in: NSRect(x: center.x - 60, y: center.y + 30, width: 120, height: 14),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .bold),
                             .foregroundColor: titleColor,
                             .paragraphStyle: para,
                             .kern: 1.2])

        let noun = count == 1
            ? (kind?.title ?? "File")
            : "\(count) \(kind?.plural.lowercased() ?? "files")"
        (noun as NSString).draw(
            in: NSRect(x: center.x - 70, y: center.y + 2, width: 140, height: 18),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                             .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.92),
                             .paragraphStyle: para])

        let hint = demo ? "Click to pick" : (hovered == nil ? "Release to cancel" : "Release to apply")
        (hint as NSString).draw(
            in: NSRect(x: center.x - 74, y: center.y - 18, width: 148, height: 14),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .regular),
                             .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.5),
                             .paragraphStyle: para])

        drawRingLegend()
    }

    /// Colour chips for the visible rings so the three surfaces read as one
    /// wheel rather than three overlapping ones.
    private func drawRingLegend() {
        guard rings.count > 1 else { return }
        let font = NSFont.systemFont(ofSize: 8.5, weight: .medium)
        let dot: CGFloat = 5
        let gap: CGFloat = 9
        var widths: [CGFloat] = []
        for ring in rings {
            let text = ring.mode.title as NSString
            widths.append(text.size(withAttributes: [.font: font]).width + dot + 3)
        }
        let total = widths.reduce(0, +) + gap * CGFloat(rings.count - 1)
        var x = center.x - total / 2
        let y = center.y - 38
        for (index, ring) in rings.enumerated() {
            ring.mode.accent.withAlphaComponent(ring.mode == emphasis ? 0.95 : 0.55).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y + 1.5, width: dot, height: dot)).fill()
            (ring.mode.title as NSString).draw(
                in: NSRect(x: x + dot + 3, y: y - 3, width: widths[index], height: 12),
                withAttributes: [.font: font,
                                 .foregroundColor: NSColor(calibratedWhite: 1,
                                                           alpha: ring.mode == emphasis ? 0.7 : 0.42)])
            x += widths[index] + gap
        }
    }

    private func symbol(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = base.withSymbolConfiguration(config) ?? base
        image.isTemplate = false
        return image
    }

    // MARK: Mouse / keyboard

    override func mouseMoved(with event: NSEvent) {
        hover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        guard demo else { return }
        let point = convert(event.locationInWindow, from: nil)
        onPick?(choice(at: point), mode(at: point) ?? emphasis)
    }

    override func keyDown(with event: NSEvent) {
        guard !rings.isEmpty else { return }
        switch event.keyCode {
        case 53: // esc
            onPick?(nil, emphasis)
        case 123, 126: // left / up
            step(-1)
        case 124, 125: // right / down
            step(1)
        case 36, 76: // return / enter
            if let choice = hoveredChoice {
                onPick?(choice, hoveredMode ?? emphasis)
            }
        default:
            super.keyDown(with: event)
        }
    }

    func step(_ delta: Int) {
        let hits = rings.enumerated().flatMap { ringIndex, ring in
            ring.choices.indices.map { WheelHit(ring: ringIndex, index: $0) }
        }
        guard !hits.isEmpty else { return }
        if let hovered, let position = hits.firstIndex(of: hovered) {
            self.hovered = hits[(position + delta + hits.count) % hits.count]
        } else {
            self.hovered = hits[delta >= 0 ? 0 : hits.count - 1]
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

// MARK: - Demo asset

enum DemoAsset {
    static func url() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zest-demo.png")
        if !FileManager.default.fileExists(atPath: url.path) {
            let size = NSSize(width: 1280, height: 800)
            let image = NSImage(size: size)
            image.lockFocus()
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.96, green: 0.55, blue: 0.16, alpha: 1),
                NSColor(calibratedRed: 0.88, green: 0.22, blue: 0.20, alpha: 1)
            ])!
            gradient.draw(in: NSRect(origin: .zero, size: size), angle: -35)
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: 140, y: 160, width: 260, height: 260)).fill()
            image.unlockFocus()
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
        }
        return url
    }
}
