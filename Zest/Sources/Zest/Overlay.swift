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
        return hypot(dx, dy) <= wheel.discRadius
    }

    /// Called shortly after the mouse button is released. A release outside
    /// the wheel is a cancel and closes immediately. A release on the wheel may
    /// be the drop the drag server is about to deliver, so the panel stays up
    /// until `performDragOperation` (which commits and closes) or a fallback
    /// timeout.
    func handleDisarm() {
        guard panel != nil else { return }
        guard isPointerOverWheel else {
            Log.verbose("Wheel disarm outside")
            close()
            return
        }
        closeWork?.cancel()
        Log.verbose("Wheel disarm on wheel; waiting for drop")
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closeWork = nil
            if self.panel != nil { Log.verbose("Wheel disarm timeout") }
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
        wheel.style = Prefs.wheelStyle
        wheel.deviceStyle = Prefs.deviceStyle
        wheel.surfaces = Catalog.surfaces(for: context.urls)
        wheel.emphasize(mode)
        wheel.count = context.urls.count
        wheel.kind = context.kind
        wheel.fileName = context.urls.count == 1
            ? context.urls[0].lastPathComponent
            : "\(context.urls.count) files"
        wheel.fileFormat = context.urls.count == 1
            ? context.urls[0].pathExtension.uppercased()
            : (context.kind?.title.uppercased() ?? "")
        wheel.totalBytes = context.urls.reduce(0) { sum, url in
            sum + (url.isDirectory ? 0 : url.fileSize)
        }
        wheel.demo = demoMode

        var center = NSPoint(x: context.anchor.x - screen.frame.minX,
                             y: context.anchor.y - screen.frame.minY)
        let margin: CGFloat = wheel.discRadius + 14
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
        Log.verbose("Wheel mode=\(wheel.emphasis.rawValue) count=\(ring?.choices.count ?? 0) "
            + "anchor=\(Int(anchor.x)),\(Int(anchor.y)) "
            + "screen=\(Int(screen.frame.width))x\(Int(screen.frame.height)) "
            + "radius=\(Int(ring?.mid ?? 0)) outer=\(Int(wheel.discRadius)) "
            + "rings=\(rings) choices=\(ids)")
    }

    func close() {
        closeWork?.cancel()
        closeWork = nil
        // Petals fold back into the hub while the panel fades.
        wheel?.startFoldAnimation()
        // State tears down immediately; the panel itself fades out over a
        // short, controlled collapse so `isOpen` flips at once.
        if let fading = panel {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                fading.animator().alphaValue = 0
            }, completionHandler: {
                fading.orderOut(nil)
                fading.close()
            })
        }
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
        Log.verbose("Choice \(choice?.id ?? "cancel") mode=\(resolved.rawValue)")
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

/// One petal of the fan wheel. The path, the label anchors, the measured label
/// width and the hit-test all come from this value; nothing else invents a
/// second set of angles. Local coordinates are petal-relative before rotation:
/// +y points outward from the hub, +x is tangential.
struct FanPetalGeometry {
    /// The two shoulder control points as fractions of the inner-to-outer
    /// width change. They are shared by the path builder, the width function
    /// used for label fitting, and therefore the hit-test path. `0.46 / 0.58`
    /// keeps the sides nearly parallel with a slight outward bow, so the
    /// inter-petal channel stays thin and even end to end. Steeper pairs (the
    /// earlier `0.85 / 1.0`) saturate by mid-length and pinch neighbours
    /// together.
    static let shoulderInnerControl: CGFloat = 0.46
    static let shoulderOuterControl: CGFloat = 0.58

    let index: Int
    let angle: CGFloat
    let path: NSBezierPath
    /// Just the outer cap's two curves, open at the shoulders. The rim
    /// specular is stroked along it so the broad end catches the light.
    let capPath: NSBezierPath
    let scale: CGFloat
    let sideInner: CGFloat
    let sideOuter: CGFloat
    let tip: CGFloat
    let innerHalf: CGFloat
    let outerHalf: CGFloat
    let labelRadius: CGFloat
    let labelWidth: CGFloat

    var length: CGFloat { max(1, sideOuter - sideInner) }

    /// Exact half-width of the shoulder cubic at a radial parameter. The
    /// shoulder is a cubic Bezier with x control fractions a and b, so the
    /// width is `inner + (outer - inner) · (3u²t·a + 3ut²·b + t³)`.
    static func halfWidth(at t: CGFloat, inner: CGFloat, outer: CGFloat) -> CGFloat {
        let c = min(max(t, 0), 1)
        let u = 1 - c
        let profile = 3 * u * u * c * shoulderInnerControl
            + 3 * u * c * c * shoulderOuterControl
            + c * c * c
        return inner + (outer - inner) * profile
    }

    func width(at radius: CGFloat) -> CGFloat {
        let t = min(max((radius - sideInner) / length, 0), 1)
        return 2 * Self.halfWidth(at: t, inner: innerHalf, outer: outerHalf)
    }
}

/// The Omnitrix × Liquid-Glass design tokens. One lime accent family on
/// graphite metal and smoky glass; green means activation, nothing else.
enum Omnitrix {
    static let lime = NSColor(srgbRed: 0.498, green: 0.910, blue: 0.290, alpha: 1)
    static let limeBright = NSColor(srgbRed: 0.659, green: 0.953, blue: 0.420, alpha: 1)
    static let limeDeep = NSColor(srgbRed: 0.180, green: 0.478, blue: 0.118, alpha: 1)
    static let limeDark = NSColor(srgbRed: 0.102, green: 0.290, blue: 0.071, alpha: 1)
    static let limeGlass = NSColor(srgbRed: 0.310, green: 0.640, blue: 0.220, alpha: 1)
    static let metalLight = NSColor(srgbRed: 0.290, green: 0.298, blue: 0.314, alpha: 1)
    static let metalDark = NSColor(srgbRed: 0.129, green: 0.133, blue: 0.145, alpha: 1)
    static let iconIdle = NSColor(srgbRed: 0.816, green: 0.835, blue: 0.816, alpha: 1)
    static let iconActive = NSColor(srgbRed: 0.851, green: 1.0, blue: 0.761, alpha: 1)
}

final class WheelView: NSView {
    /// Radii in points. The fan is the default surface: 496 pt across at
    /// native scale, which leaves the desktop visible around it. Rings are
    /// slightly wider because three labelled surfaces share the disc.
    static let outerRadius: CGFloat = 288
    static let hubRadius: CGFloat = 72

    var outerRadius: CGFloat { Self.outerRadius }
    var innerRadius: CGFloat { Self.hubRadius }
    var discRadius: CGFloat { style == .fan ? fanOuter : Self.outerRadius }

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
    var totalBytes: Int64 = 0
    /// Dynamic hub copy. The controller passes the real file name and
    /// extension; the CLI and the welcome preview pass their sample.
    var fileName: String?
    var fileFormat: String?
    var demo = false
    var preview = false

    /// Fan petals, rebuilt whenever the surface, scale or centre changes.
    /// Drawing and hit-testing both read this array.
    private(set) var fanPetals: [FanPetalGeometry] = []

    /// Device appearance. Presentation only: it selects material and motion
    /// variants inside the drawing code and never touches geometry,
    /// hit-testing, or the catalog.
    var deviceStyle: DeviceStyle = .transformation {
        didSet { needsDisplay = true }
    }

    /// Every lime accent alpha in the renderer scales with this (0…1).
    var glow: CGFloat { CGFloat(Prefs.greenGlow) }

    /// Motion budget: Reduce Motion (system) always clamps to the reduced
    /// profile regardless of the stored preference.
    private var motionReduced: Bool {
        reduceMotion || Prefs.animationIntensity == .reduced
    }
    private var unfoldDuration: TimeInterval {
        Prefs.animationIntensity == .full ? 0.26 : (motionReduced ? 0.10 : 0.18)
    }
    private var unfoldStagger: TimeInterval {
        Prefs.animationIntensity == .full ? 0.012 : (motionReduced ? 0.004 : 0.008)
    }
    private var pulseEnabled: Bool {
        !motionReduced
    }
    /// The rotating bezel ticks only turn under the Full profile.
    private var rotationEnabled: Bool {
        !reduceMotion && Prefs.animationIntensity == .full
            && (deviceStyle == .classic || deviceStyle == .transformation)
    }

    /// Fan geometry scale. The overlay uses 1; the welcome preview shrinks the
    /// same drawing to fit a 370-point card without a second renderer.
    var fanScale: CGFloat = 1 {
        didSet {
            guard oldValue != fanScale else { return }
            rebuildRings()
        }
    }
    private var fanOuter: CGFloat { Self.fanOuterRadius * fanScale }
    private var fanInner: CGFloat { Self.fanInnerRadius * fanScale }
    /// Rings keeps all three surfaces visible. Fan is the single-surface
    /// layout; emphasis picks which surface the fan shows.
    var style: WheelStyle = .rings {
        didSet {
            guard oldValue != style else { return }
            hovered = nil
            rebuildRings()
        }
    }
    var hovered: WheelHit? {
        didSet { if oldValue != hovered { needsDisplay = true } }
    }
    var center: NSPoint = .zero {
        didSet {
            if style == .fan { rebuildFanPetals() }
            needsDisplay = true
        }
    }

    /// Called with the picked choice and the ring it came from. `nil` cancels.
    var onPick: ((WheelChoice?, WheelMode) -> Void)?
    var onHover: ((WheelChoice?) -> Void)?

    private var tracking: NSTrackingArea?
    private var lastHoverSound = Date.distantPast

    // Activation choreography. `activationDate` drives a green pulse through
    // the device; `unfoldDate` staggers the petals out of the hub. Both are
    // nil unless the view lives in a window (CLI renders draw the settled
    // state) and reduced-motion is off. Hit-testing always uses the settled
    // petal paths — the animation is drawing-only and finishes in ~0.45 s.
    private var activationDate: Date?
    private var unfoldDate: Date?
    private var animTimer: Timer?

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 0…1 eased progress for the activation pulse, or 1 when idle.
    var activationPhase: CGFloat {
        guard let start = activationDate else { return 1 }
        let t = CGFloat(max(0, -start.timeIntervalSinceNow) / 0.45)
        guard t < 1 else { return 1 }
        return 1 - pow(1 - t, 2.2)
    }

    /// 0…1 unfold progress for a petal, staggered outward from index 0.
    func unfoldPhase(for index: Int) -> CGFloat {
        guard let start = unfoldDate else { return 1 }
        let stagger = TimeInterval(index) * unfoldStagger
        let t = CGFloat(max(0, (-start.timeIntervalSinceNow - stagger) / unfoldDuration))
        guard t < 1 else { return 1 }
        return 1 - pow(1 - t, 3)
    }

    /// Reverse of the unfold, used while the overlay fades on close.
    private var foldDate: Date?
    func foldPhase(for index: Int) -> CGFloat {
        guard let start = foldDate else { return 0 }
        let reverse = TimeInterval(max(0, fanPetals.count - 1 - index)) * unfoldStagger
        let t = CGFloat(max(0, (-start.timeIntervalSinceNow - reverse) / unfoldDuration))
        guard t < 1 else { return 1 }
        return t
    }

    func startDeviceAnimation(pulse: Bool) {
        guard window != nil, !reduceMotion else { return }
        foldDate = nil
        if pulse, pulseEnabled { activationDate = Date() }
        unfoldDate = Date()
        animTimer?.invalidate()
        // The timer also carries the bezel rotation for a short window after
        // activation; then the device settles and redraws stop.
        let rotationWindow: TimeInterval = rotationEnabled ? 2.2 : 0
        let deadline = Date().addingTimeInterval(max(0.5, unfoldDuration
            + TimeInterval(64) * unfoldStagger + rotationWindow))
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.needsDisplay = true
            if Date() > deadline, self.foldDate == nil {
                t.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animTimer = timer
    }

    /// Petals fold back into the hub while the panel fades out.
    func startFoldAnimation() {
        guard window != nil, !motionReduced else { return }
        foldDate = Date()
        animTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.needsDisplay = true
            if self.foldPhase(for: 0) >= 1 { t.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animTimer = timer
    }

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
        if style == .fan {
            let available = surfaces.filter { !$0.choices.isEmpty }
            emphasis = available.contains { $0.mode == mode }
                ? mode : (available.first?.mode ?? mode)
            hovered = nil
            rebuildRings()
            return
        }
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

        if style == .fan {
            let surface = active.first { $0.mode == emphasis } ?? active[0]
            emphasis = surface.mode
            rings = [WheelRing(mode: surface.mode, choices: surface.choices,
                               inner: fanInner, outer: fanOuter)]
            rebuildFanPetals()
            hovered = nil
            startDeviceAnimation(pulse: !rings.isEmpty)
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

    /// Compact wheel: 384 pt across at native scale (~80% of the previous
    /// 480 pt disc). Every fan dimension derives from these two radii.
    static let fanInnerRadius: CGFloat = 68
    static let fanOuterRadius: CGFloat = 192

    /// Ring labels share one font size per ring. Pick the largest size whose
    /// longest title still fits the wedge chord, so shrinking the wheel never
    /// silently truncates a tool name. The UI fit test measures this same font.
    static func labelFont(for choice: WheelChoice, in ring: WheelRing) -> NSFont {
        let available = max(46, 2 * ring.mid * sin(ring.step / 2) - 12)
        let sizes: [CGFloat] = [11.5, 11, 10.5, 10, 9.5, 9, 8.5]
        for size in sizes {
            let font = NSFont.systemFont(ofSize: size, weight: .semibold)
            let widest = ring.choices.map {
                ($0.title as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 0
            if widest <= available { return font }
        }
        return .systemFont(ofSize: 8.5, weight: .semibold)
    }

    /// Fan labels use sentence case and one measured size for the whole
    /// surface. The available width comes from the petal itself, not from an
    /// angular chord guess, so the label fit test and the rendered text share
    /// the same contract.
    static func fanLabelFont(for choices: [WheelChoice], available: CGFloat,
                             scale: CGFloat) -> NSFont {
        fanFont(for: choices, available: available, scale: scale,
                sizes: [12.5, 12, 11.5, 11, 10.5, 10, 9.5, 9, 8.5, 8])
    }

    static func fanFormatFont(for choices: [WheelChoice], available: CGFloat,
                              scale: CGFloat) -> NSFont {
        fanFont(for: choices, available: available, scale: scale,
                sizes: [14.5, 14, 13.5, 13, 12.5, 12, 11.5, 11, 10.5])
    }

    private static func fanFont(for choices: [WheelChoice], available: CGFloat,
                                scale: CGFloat, sizes: [CGFloat]) -> NSFont {
        for size in sizes {
            let font = NSFont.systemFont(ofSize: max(7, size * scale), weight: .semibold)
            let widest = choices.map {
                ($0.title as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 0
            if widest <= available { return font }
        }
        let fallback = sizes.last ?? 9.5
        return .systemFont(ofSize: max(7, fallback * scale), weight: .semibold)
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
        Log.verbose("Drop enter")
        hover(at: convert(sender.draggingLocation, from: nil))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hover(at: convert(sender.draggingLocation, from: nil))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        Log.verbose("Drop exit")
        hovered = nil
        needsDisplay = true
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Log.verbose("Drop perform")
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
    private func wedgePath(ring: WheelRing, index: Int, inset: CGFloat = 0,
                           gapOverride: CGFloat? = nil) -> NSBezierPath {
        let gap = gapOverride ?? min(0.016, ring.step * 0.10)
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

    /// Rebuilds the single source of truth for the fan: the petal paths and
    /// their label metrics. Every fan draw and hit-test reads this array.
    private func rebuildFanPetals() {
        guard style == .fan, let ring = rings.first, !ring.choices.isEmpty else {
            fanPetals = []
            return
        }
        let scale = max(0.5, fanScale)
        fanPetals = (0..<ring.choices.count).map {
            makeFanPetal(ring: ring, index: $0, scale: scale)
        }
    }

    private func makeFanPetal(ring: WheelRing, index: Int,
                              scale: CGFloat) -> FanPetalGeometry {
        let angle = ring.midAngle(index)
        let halfSlot = sin(ring.step / 2)
        let tip = ring.outer - 2 * scale

        // Petals fill 85% of the chord at every count, so low-count fans grow
        // wide paddles that fill the circle instead of floating slim petals
        // over empty space. The cap is a shape guard for very sparse surfaces
        // (three-petal folders) only; it never binds at eight or more. The
        // teardrop silhouette — narrow neck, domed cap — is what keeps wide
        // petals reading as petals. The reference's own bottom pair touches;
        // this geometry never lets a gap close — the uitest seam check holds
        // every pair to a real channel.
        let innerTip = ring.inner - 4 * scale
        let widthCap = 0.62 * (tip - innerTip)
        let capGuess = min(tip * halfSlot * 0.85, widthCap) * 0.58
        let sideGuess = tip - capGuess
        let outerHalf = max(10 * scale, min(sideGuess * halfSlot * 0.85, widthCap))
        let capBulge = outerHalf * 0.58
        let sideOuter = tip - capBulge
        let innerHalf = max(6 * scale, outerHalf * 0.40)

        // The neck starts just under the hub rim so the petals emerge from
        // behind the hub and the flower reads as one piece. The hub is drawn
        // over this part and fan hit-testing treats the hub as a cancel.
        let innerBulge = innerHalf * 0.62
        let sideInner = innerTip + innerBulge
        let length = max(1, sideOuter - sideInner)

        let labelRadius = sideInner + length * 0.73
        let t = min(max((labelRadius - sideInner) / length, 0), 1)
        let half = FanPetalGeometry.halfWidth(at: t, inner: innerHalf,
                                              outer: outerHalf)
        let labelWidth = max(26 * scale, 2 * half - 3 * scale)

        let paths = fanPetalPath(angle: angle, sideInner: sideInner,
                                 sideOuter: sideOuter, tip: tip,
                                 innerTip: innerTip, innerHalf: innerHalf,
                                 outerHalf: outerHalf, innerBulge: innerBulge,
                                 capBulge: capBulge)
        return FanPetalGeometry(index: index, angle: angle,
                                path: paths.body, capPath: paths.cap,
                                scale: scale, sideInner: sideInner,
                                sideOuter: sideOuter, tip: tip,
                                innerHalf: innerHalf, outerHalf: outerHalf,
                                labelRadius: labelRadius,
                                labelWidth: labelWidth)
    }

    /// One elongated glass petal in two shoulder curves and two cap halves.
    /// The shoulder is a cubic whose width profile is shared with the label
    /// fit; the caps are elliptical quarter arcs. Adjacent petals therefore
    /// never share a point, and the wrap boundary uses exactly the same
    /// construction. Also returns the open outer-cap sub-path for the rim
    /// specular, built from the same points.
    private func fanPetalPath(angle: CGFloat, sideInner: CGFloat,
                              sideOuter: CGFloat, tip: CGFloat,
                              innerTip: CGFloat, innerHalf: CGFloat,
                              outerHalf: CGFloat, innerBulge: CGFloat,
                              capBulge: CGFloat)
        -> (body: NSBezierPath, cap: NSBezierPath) {
        let ux = cos(angle)
        let uy = sin(angle)
        let tx = -uy
        let ty = ux
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: center.x + ux * y + tx * x,
                    y: center.y + uy * y + ty * x)
        }

        let k: CGFloat = 0.5522847498 // quarter-circle Bezier constant
        let length = max(1, sideOuter - sideInner)
        let delta = outerHalf - innerHalf
        let innerControl = innerHalf + FanPetalGeometry.shoulderInnerControl * delta
        let outerControl = innerHalf + FanPetalGeometry.shoulderOuterControl * delta
        let path = NSBezierPath()
        path.move(to: p(0, innerTip))

        // Left inner cap, left shoulder, outer cap and back down the right.
        path.curve(to: p(-innerHalf, sideInner),
                   controlPoint1: p(-k * innerHalf, innerTip),
                   controlPoint2: p(-innerHalf, sideInner - k * innerBulge))
        path.curve(to: p(-outerHalf, sideOuter),
                   controlPoint1: p(-innerControl, sideInner + length / 3),
                   controlPoint2: p(-outerControl, sideInner + length * 2 / 3))
        path.curve(to: p(0, tip),
                   controlPoint1: p(-outerHalf, sideOuter + k * capBulge),
                   controlPoint2: p(-k * outerHalf, tip))
        path.curve(to: p(outerHalf, sideOuter),
                   controlPoint1: p(k * outerHalf, tip),
                   controlPoint2: p(outerHalf, sideOuter + k * capBulge))
        path.curve(to: p(innerHalf, sideInner),
                   controlPoint1: p(outerControl, sideInner + length * 2 / 3),
                   controlPoint2: p(innerControl, sideInner + length / 3))
        path.curve(to: p(0, innerTip),
                   controlPoint1: p(innerHalf, sideInner - k * innerBulge),
                   controlPoint2: p(k * innerHalf, innerTip))
        path.close()

        let cap = NSBezierPath()
        cap.move(to: p(-outerHalf, sideOuter))
        cap.curve(to: p(0, tip),
                  controlPoint1: p(-outerHalf, sideOuter + k * capBulge),
                  controlPoint2: p(-k * outerHalf, tip))
        cap.curve(to: p(outerHalf, sideOuter),
                  controlPoint1: p(k * outerHalf, tip),
                  controlPoint2: p(outerHalf, sideOuter + k * capBulge))
        return (path, cap)
    }

    func hit(at point: NSPoint) -> WheelHit? {
        guard !rings.isEmpty else { return nil }
        if style == .fan {
            // The hub is a cancel zone even though the petal necks tuck just
            // under its rim, and the gap between two petals cancels too: hit
            // the drawn silhouette so nothing silently selects a neighbour.
            let dx = point.x - center.x
            let dy = point.y - center.y
            guard hypot(dx, dy) >= fanInner else { return nil }
            for (index, petal) in fanPetals.enumerated() where petal.path.contains(point) {
                return WheelHit(ring: 0, index: index)
            }
            return nil
        }
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

        guard !rings.isEmpty else { return }
        if style == .fan {
            drawFan()
        } else {
            drawRings()
            drawHub()
        }
    }

    private func drawRings() {
        drawActivationPulse()
        for (ringIndex, ring) in rings.enumerated() {
            let emphasized = ring.mode == emphasis
            for (index, choice) in ring.choices.enumerated() {
                let hover = hovered == WheelHit(ring: ringIndex, index: index)
                let path = wedgePath(ring: ring, index: index)
                if hover {
                    // Active slice: green activation glass.
                    NSGradient(colors: [Omnitrix.limeDark, Omnitrix.limeDeep,
                                        Omnitrix.limeGlass],
                               atLocations: [0, 0.6, 1], colorSpace: .deviceRGB)?
                        .draw(in: path.bounds, angle: 90)
                } else if deviceStyle == .glass {
                    NSColor(calibratedWhite: emphasized ? 0.16 : 0.11, alpha: 0.90).setFill()
                    path.fill()
                } else {
                    NSColor(calibratedWhite: emphasized ? 0.13 : 0.08, alpha: 0.97).setFill()
                    path.fill()
                }
                let stroke = hover
                    ? Omnitrix.lime
                    : Omnitrix.lime.withAlphaComponent((emphasized ? 0.32 : 0.14) * glow)
                stroke.setStroke()
                path.lineWidth = hover ? 1.4 : 1
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
        // Green power seam just inside the dial's outer edge — mechanical
        // styles only, scaled by the glow preference.
        if deviceStyle == .classic || deviceStyle == .transformation {
            let seam = NSBezierPath(ovalIn: NSRect(x: center.x - outerRadius + 3,
                                                   y: center.y - outerRadius + 3,
                                                   width: (outerRadius - 3) * 2,
                                                   height: (outerRadius - 3) * 2))
            Omnitrix.lime.withAlphaComponent(0.26 * glow).setStroke()
            seam.lineWidth = 1.2
            seam.stroke()
        } else if deviceStyle == .glass {
            let seam = NSBezierPath(ovalIn: NSRect(x: center.x - outerRadius + 3,
                                                   y: center.y - outerRadius + 3,
                                                   width: (outerRadius - 3) * 2,
                                                   height: (outerRadius - 3) * 2))
            Omnitrix.lime.withAlphaComponent(0.12 * glow).setStroke()
            seam.lineWidth = 1.0
            seam.stroke()
        }
    }

    // MARK: Fan wheel

    /// Fan layout: one surface of matte graphite petals around the file hub.
    /// The three-ring layout stays available in Settings and is still the
    /// default for `WheelView` so the headless geometry tests can exercise
    /// every ring without touching preferences.
    private func drawFan() {
        guard let ring = rings.first else { return }
        if fanPetals.count != ring.choices.count { rebuildFanPetals() }
        guard fanPetals.count == ring.choices.count, !fanPetals.isEmpty else { return }

        drawFanBezel(count: ring.choices.count)
        drawActivationPulse()

        // Neutral shadows separate neighbouring petals; the selected petal
        // wears the device's green activation light as its shadow.
        for (index, petal) in fanPetals.enumerated() {
            let hover = hovered == WheelHit(ring: 0, index: index)
            drawFanPetalShadow(petal, hover: hover)
        }

        let isFormat: Bool
        if let first = ring.choices.first, case .format = first.payload {
            isFormat = true
        } else {
            isFormat = false
        }
        let artScale = max(0.70, fanScale)
        let labelFont = isFormat
            ? Self.fanFormatFont(for: ring.choices, available: fanPetals[0].labelWidth,
                                scale: artScale)
            : Self.fanLabelFont(for: ring.choices, available: fanPetals[0].labelWidth,
                               scale: artScale)

        for (index, choice) in ring.choices.enumerated() {
            guard index < fanPetals.count else { continue }
            let petal = fanPetals[index]
            let hover = hovered == WheelHit(ring: 0, index: index)

            // Unfold: petals grow out of the hub with a short stagger, and
            // fold back on close. Both transforms are drawing-only; the
            // hit-test paths stay settled.
            let phase = unfoldPhase(for: index) * (1 - foldPhase(for: index))
            guard phase > 0.01 else { continue }
            let scale = 0.55 + 0.45 * phase
            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.translateBy(x: center.x, y: center.y)
                ctx.scaleBy(x: scale, y: scale)
                ctx.translateBy(x: -center.x, y: -center.y)
                ctx.setAlpha(phase)
            }
            drawFanPetalBody(petal, hover: hover)
            drawFanContent(choice, petal: petal, hover: hover, font: labelFont)
            NSGraphicsContext.restoreGraphicsState()
        }

        drawFanHub()
    }

    /// The bezel just outside the petals. Minimal skips it, Liquid Glass
    /// draws one thin luminous ring, and the mechanical styles draw segmented
    /// metal whose green insets light up in sequence during activation.
    private func drawFanBezel(count: Int) {
        guard deviceStyle != .minimal else { return }
        let bandInner = fanOuter + 2 * fanScale
        let bandOuter = min(fanOuter + 12 * fanScale, Self.fanOuterRadius * fanScale + 12 * fanScale)
        guard bandOuter > bandInner, count > 0 else { return }

        if deviceStyle == .glass {
            let ring = NSBezierPath(ovalIn: NSRect(
                x: center.x - (bandInner + 2 * fanScale),
                y: center.y - (bandInner + 2 * fanScale),
                width: (bandInner + 2 * fanScale) * 2,
                height: (bandInner + 2 * fanScale) * 2))
            NSColor.white.withAlphaComponent(0.10).setStroke()
            ring.lineWidth = 2.4 * max(0.7, fanScale)
            ring.stroke()
            Omnitrix.lime.withAlphaComponent(0.12 * glow).setStroke()
            ring.lineWidth = 1.1 * max(0.7, fanScale)
            ring.stroke()
            return
        }

        let step = CGFloat.pi * 2 / CGFloat(count)
        let gap: CGFloat = 0.055
        let activation = activationPhase
        // Sequential illumination: segment i lights as the pulse reaches it.
        let sweep: (Int) -> CGFloat = { index in
            let reach = activation * CGFloat(count)
            return max(0, min(1, reach - CGFloat(index)))
        }

        for index in 0..<count {
            let a0 = -CGFloat.pi / 2 + CGFloat(index) * step + gap
            let a1 = -CGFloat.pi / 2 + CGFloat((index + 1)) * step - gap
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: bandOuter,
                           startAngle: a0 * 180 / .pi, endAngle: a1 * 180 / .pi,
                           clockwise: false)
            path.appendArc(withCenter: center, radius: bandInner,
                           startAngle: a1 * 180 / .pi, endAngle: a0 * 180 / .pi,
                           clockwise: true)
            path.close()
            NSGradient(colors: [Omnitrix.metalLight, Omnitrix.metalDark])?
                .draw(in: path.bounds, angle: 90)
            NSColor.black.withAlphaComponent(0.25).setFill()
            path.fill()
            let lit = sweep(index)
            if lit > 0.01 {
                Omnitrix.lime.withAlphaComponent((0.22 + 0.45 * lit) * glow).setFill()
                let insetPath = NSBezierPath()
                let r = bandInner + 1.6 * fanScale
                insetPath.appendArc(withCenter: center, radius: r,
                                    startAngle: a0 * 180 / .pi,
                                    endAngle: a1 * 180 / .pi, clockwise: false)
                insetPath.lineWidth = 1.6 * max(0.7, fanScale)
                insetPath.stroke()
            }
        }

        // Rotating ticks on the inset ring — mechanical life under Full.
        if rotationEnabled, let start = activationDate {
            let elapsed = -start.timeIntervalSinceNow
            let angle = elapsed * 0.35
            let tickCount = count
            for index in 0..<tickCount {
                let a = -CGFloat.pi / 2 + CGFloat(index) * step + angle
                let p0 = fanPoint(a, bandInner + 0.8 * fanScale)
                let p1 = fanPoint(a, bandInner + 2.6 * fanScale)
                let tick = NSBezierPath()
                tick.move(to: p0)
                tick.line(to: p1)
                Omnitrix.lime.withAlphaComponent(0.5 * glow).setStroke()
                tick.lineWidth = 1.1 * max(0.7, fanScale)
                tick.stroke()
            }
        }
    }

    /// A single green pulse travels from the hub to the bezel on activation.
    private func drawActivationPulse() {
        let phase = activationPhase
        guard phase < 1 else { return }
        let radius = fanInner + (fanOuter - fanInner) * phase
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2))
        Omnitrix.lime.withAlphaComponent(0.55 * (1 - phase)).setStroke()
        ring.lineWidth = 2.6 * max(0.7, fanScale)
        ring.stroke()
    }

    private func fanPoint(_ angle: CGFloat, _ radius: CGFloat) -> NSPoint {
        NSPoint(x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius)
    }

    /// One neutral shadow per petal, drawn before any body so a shadow never
    /// falls across a neighbour's face. The selected petal's shadow carries
    /// the device's green activation light.
    private func drawFanPetalShadow(_ petal: FanPetalGeometry, hover: Bool) {
        let shadow = NSShadow()
        if hover {
            shadow.shadowColor = NSColor(srgbRed: 0.20, green: 0.62, blue: 0.10,
                                         alpha: 0.30 + 0.28 * glow)
            shadow.shadowBlurRadius = 13 * petal.scale
        } else {
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 14 * petal.scale
        }
        shadow.shadowOffset = NSSize(width: 0, height: -4 * petal.scale)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.black.withAlphaComponent(0.70).setFill()
        petal.path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// One Liquid-Glass petal: smoky translucent graphite when idle, bright
    /// green activation glass when selected — a lime edge, a green fill, and
    /// a restrained refracted light pool on the cap. Neighbours stay cool and
    /// distinguishable.
    private func drawFanPetalBody(_ petal: FanPetalGeometry, hover: Bool) {
        NSGraphicsContext.saveGraphicsState()
        petal.path.addClip()
        if hover {
            // Selected: translucent green activation glass, shared by every
            // style — green always means the active petal.
            NSGradient(colors: [
                Omnitrix.limeDark,
                Omnitrix.limeDeep,
                Omnitrix.limeGlass
            ], atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)?
                .draw(in: petal.path.bounds, angle: petal.angle * 180 / .pi)
        } else if deviceStyle == .minimal {
            // Minimal: matte graphite, no glass theatre.
            NSGradient(colors: [
                NSColor(srgbRed: 0.114, green: 0.118, blue: 0.122, alpha: 1),
                NSColor(srgbRed: 0.145, green: 0.149, blue: 0.155, alpha: 1),
                NSColor(srgbRed: 0.176, green: 0.180, blue: 0.188, alpha: 1)
            ], atLocations: [0, 0.45, 1], colorSpace: .deviceRGB)?
                .draw(in: petal.path.bounds, angle: petal.angle * 180 / .pi)
        } else if deviceStyle == .glass {
            // Liquid Glass: lighter translucent smoky glass.
            NSGradient(colors: [
                NSColor(srgbRed: 0.145, green: 0.157, blue: 0.152, alpha: 1),
                NSColor(srgbRed: 0.196, green: 0.204, blue: 0.204, alpha: 1),
                NSColor(srgbRed: 0.235, green: 0.243, blue: 0.243, alpha: 1)
            ], atLocations: [0, 0.45, 1], colorSpace: .deviceRGB)?
                .draw(in: petal.path.bounds, angle: petal.angle * 180 / .pi)
        } else {
            // Classic / Transformation: smoky graphite glass, slightly green
            // at the neck where the device's light bleeds out.
            NSGradient(colors: [
                NSColor(srgbRed: 0.118, green: 0.133, blue: 0.125, alpha: 1),
                NSColor(srgbRed: 0.161, green: 0.171, blue: 0.169, alpha: 1),
                NSColor(srgbRed: 0.188, green: 0.196, blue: 0.200, alpha: 1)
            ], atLocations: [0, 0.45, 1], colorSpace: .deviceRGB)?
                .draw(in: petal.path.bounds, angle: petal.angle * 180 / .pi)
        }

        if deviceStyle != .minimal {
            // Glass depth: dark pooling where the neck meets the hub.
            let neckCenter = fanPoint(petal.angle, petal.sideInner + petal.length * 0.05)
            if let neck = NSGradient(colors: [
                NSColor.black.withAlphaComponent(hover ? 0.12 : 0.24), NSColor.clear
            ]) {
                neck.draw(fromCenter: neckCenter, radius: 0,
                          toCenter: neckCenter, radius: petal.length * 0.34, options: [])
            }

            // Refracted light on the rounded cap: lime on the active petal,
            // neutral glass on the rest.
            let bloomCenter = fanPoint(petal.angle, petal.sideOuter - 3 * petal.scale)
            let bloomColor = hover
                ? NSColor(srgbRed: 0.659, green: 0.953, blue: 0.420,
                          alpha: 0.10 + 0.22 * glow)
                : NSColor.white.withAlphaComponent(
                    deviceStyle == .glass ? 0.17 : 0.13)
            if let bloom = NSGradient(colors: [bloomColor, NSColor.clear]) {
                bloom.draw(fromCenter: bloomCenter, radius: 0,
                           toCenter: bloomCenter, radius: petal.outerHalf * 2.6, options: [])
            }

            // A whisper of shared sheen so the whole flower is lit from one side.
            if let sheen = NSGradient(colors: [
                NSColor.white.withAlphaComponent(hover ? 0.08 : 0.06), .clear
            ]) {
                sheen.draw(in: petal.path.bounds, angle: 95)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        if deviceStyle == .glass, !hover {
            // Liquid Glass: a faint green edge kiss on every petal.
            Omnitrix.lime.withAlphaComponent(0.12 * glow).setStroke()
            petal.path.lineWidth = 0.7 * petal.scale
            petal.path.stroke()
        }

        let border = hover ? Omnitrix.lime
            : NSColor(srgbRed: 0.290, green: 0.298, blue: 0.306, alpha: 1)
        border.setStroke()
        petal.path.lineWidth = (hover ? 1.5 : 1.0) * petal.scale
        petal.path.stroke()
        // Lit glass edge just inside the border — lime on the active petal.
        let edge = hover
            ? Omnitrix.limeBright.withAlphaComponent(0.45)
            : NSColor.white.withAlphaComponent(0.14)
        edge.setStroke()
        petal.path.lineWidth = 0.75 * petal.scale
        petal.path.stroke()
    }

    private func drawFanContent(_ choice: WheelChoice, petal: FanPetalGeometry,
                                hover: Bool, font: NSFont) {
        let artScale = max(0.70, fanScale)
        let isFormat: Bool
        if case .format = choice.payload { isFormat = true } else { isFormat = false }

        // Stack content in screen space, not along the petal's radial axis.
        // Every petal then reads icon-over-label like the reference, even at
        // three o'clock and six o'clock. The shared anchor still comes from
        // the petal geometry.
        let anchor = fanPoint(petal.angle, petal.labelRadius)
        if !isFormat {
            let iconPoint = NSPoint(x: anchor.x, y: anchor.y + 12 * artScale)
            let iconSize = (hover ? 22.0 : 20.0) * artScale
            if let image = symbol(choice.symbol, pointSize: iconSize,
                                  color: hover ? Omnitrix.iconActive : Omnitrix.iconIdle) {
                let size = image.size
                image.draw(in: NSRect(x: iconPoint.x - size.width / 2,
                                      y: iconPoint.y - size.height / 2,
                                      width: size.width, height: size.height))
            }
        }

        let labelPoint = isFormat
            ? anchor
            : NSPoint(x: anchor.x, y: anchor.y - 7 * artScale)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: hover
                ? NSColor.white
                : NSColor(srgbRed: 0.941, green: 0.941, blue: 0.949, alpha: 1),
            .paragraphStyle: para,
            .kern: 0.1
        ]
        let lineHeight = font.pointSize * 1.35
        let rect = NSRect(x: labelPoint.x - petal.labelWidth / 2,
                          y: labelPoint.y - lineHeight / 2,
                          width: petal.labelWidth, height: lineHeight)
        (choice.title as NSString).draw(in: rect, withAttributes: attrs)
    }

    private func fanAnnulus(radius outer: CGFloat, inner: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: outer,
                       startAngle: 0, endAngle: 360, clockwise: false)
        path.appendArc(withCenter: center, radius: inner,
                       startAngle: 360, endAngle: 0, clockwise: true)
        path.close()
        return path
    }

    private func drawFanHub() {
        let hubRect = NSRect(x: center.x - fanInner,
                             y: center.y - fanInner,
                             width: fanInner * 2,
                             height: fanInner * 2)
        let circle = NSBezierPath(ovalIn: hubRect)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.50)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor(srgbRed: 0.098, green: 0.102, blue: 0.114, alpha: 0.99).setFill()
        circle.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        NSGradient(colors: [
            NSColor(srgbRed: 0.118, green: 0.122, blue: 0.137, alpha: 1),
            NSColor(srgbRed: 0.078, green: 0.082, blue: 0.098, alpha: 1)
        ])?.draw(in: hubRect, angle: 90)
        // Soft top light so the hub reads as a glass puck.
        if let sheen = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.08), NSColor.clear
        ]) {
            let sheenCenter = NSPoint(x: center.x, y: center.y + fanInner * 0.45)
            sheen.draw(fromCenter: sheenCenter, radius: 0,
                       toCenter: sheenCenter, radius: fanInner, options: [])
        }
        NSGraphicsContext.restoreGraphicsState()

        // Metallic rim: the raised shell edge of the device.
        NSGraphicsContext.saveGraphicsState()
        fanAnnulus(radius: fanInner, inner: fanInner - 5 * max(0.7, fanScale)).addClip()
        NSGradient(colors: [Omnitrix.metalLight, Omnitrix.metalDark])?
            .draw(in: hubRect, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        NSColor(srgbRed: 0.176, green: 0.184, blue: 0.196, alpha: 1).setStroke()
        circle.lineWidth = 1.5
        circle.stroke()

        // Recessed inner well: darker disc set inside the rim.
        let well = fanInner - 5 * max(0.7, fanScale)
        let wellRect = NSRect(x: center.x - well, y: center.y - well,
                              width: well * 2, height: well * 2)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: wellRect).addClip()
        NSGradient(colors: [
            NSColor(srgbRed: 0.086, green: 0.094, blue: 0.090, alpha: 1),
            NSColor(srgbRed: 0.055, green: 0.059, blue: 0.057, alpha: 1)
        ])?.draw(in: wellRect, angle: 90)

        // The Omnitrix hourglass: two green triangles meeting at the centre,
        // faint enough to sit beneath the file information. Classic carries a
        // brighter core; Minimal and Liquid Glass keep a clean puck.
        if deviceStyle == .classic || deviceStyle == .transformation {
            let h = well * 0.94
            let halfW = h * 0.46
            let top = NSBezierPath()
            top.move(to: NSPoint(x: center.x - halfW, y: center.y + h / 2))
            top.line(to: NSPoint(x: center.x + halfW, y: center.y + h / 2))
            top.line(to: NSPoint(x: center.x, y: center.y))
            top.close()
            let bottom = NSBezierPath()
            bottom.move(to: NSPoint(x: center.x - halfW, y: center.y - h / 2))
            bottom.line(to: NSPoint(x: center.x + halfW, y: center.y - h / 2))
            bottom.line(to: NSPoint(x: center.x, y: center.y))
            bottom.close()
            let base = deviceStyle == .classic
                ? CGFloat(0.14 + 0.20 * (1 - activationPhase))
                : CGFloat(0.10 + 0.14 * (1 - activationPhase))
            let pulse = base * glow
            Omnitrix.lime.withAlphaComponent(pulse).setFill()
            top.fill()
            bottom.fill()
            Omnitrix.lime.withAlphaComponent(pulse * 0.6).setStroke()
            top.lineWidth = 1
            top.stroke()
            bottom.lineWidth = 1
            bottom.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Green hairline where the rim meets the well — the powered seam.
        let seam = NSBezierPath(ovalIn: wellRect.insetBy(dx: -0.75, dy: -0.75))
        Omnitrix.lime.withAlphaComponent(0.30 * glow).setStroke()
        seam.lineWidth = 1.1
        seam.stroke()

        let s = max(0.55, fanScale)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingMiddle

        let name: String
        if let fileName, !fileName.isEmpty {
            name = fileName
        } else if count == 1 {
            name = kind?.title ?? "1 File"
        } else {
            name = "\(count) files"
        }
        let format = fileFormat?.isEmpty == false
            ? fileFormat!
            : (kind?.title ?? "")
        var parts: [String] = []
        if count > 1 { parts.append("\(count) files") }
        else if !format.isEmpty { parts.append(format) }
        if totalBytes > 0 { parts.append(Bytes.format(totalBytes)) }
        let meta = parts.joined(separator: " · ")

        let iconSize = 26 * s
        if let image = symbol(kind?.symbol ?? "doc", pointSize: iconSize,
                              color: Omnitrix.iconActive) {
            let size = image.size
            let iconY = center.y + 23 * s
            image.draw(in: NSRect(x: center.x - size.width / 2,
                                  y: iconY - size.height / 2,
                                  width: size.width, height: size.height))
        }

        let nameFont = NSFont.systemFont(ofSize: max(7.5, 14.0 * s), weight: .semibold)
        let nameHeight = nameFont.pointSize * 1.35
        (name as NSString).draw(
            in: NSRect(x: center.x - fanInner + 14 * s,
                       y: center.y - 1 * s - nameHeight / 2,
                       width: 2 * fanInner - 28 * s, height: nameHeight),
            withAttributes: [.font: nameFont,
                             .foregroundColor: NSColor(srgbRed: 0.941, green: 0.941,
                                                       blue: 0.949, alpha: 1),
                             .paragraphStyle: para])

        let metaFont = NSFont.systemFont(ofSize: max(6.5, 10.0 * s), weight: .medium)
        let metaHeight = metaFont.pointSize * 1.35
        (meta as NSString).draw(
            in: NSRect(x: center.x - fanInner + 16 * s,
                       y: center.y - 18 * s - metaHeight / 2,
                       width: 2 * fanInner - 32 * s, height: metaHeight),
            withAttributes: [.font: metaFont,
                             .foregroundColor: NSColor(srgbRed: 0.631, green: 0.631,
                                                       blue: 0.655, alpha: 1),
                             .paragraphStyle: para])
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
                                  color: hover ? .white : Omnitrix.iconIdle) {
                let size = image.size
                image.draw(in: NSRect(x: px - size.width / 2, y: py + 7,
                                      width: size.width, height: size.height))
            }
        }

        let font = Self.labelFont(for: choice, in: ring)
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
        NSColor(calibratedWhite: 0.06, alpha: 0.98).setFill()
        circle.fill()
        let activeMode = hoveredMode ?? emphasis
        _ = activeMode
        (hovered == nil
            ? NSColor(calibratedWhite: 1, alpha: 0.14)
            : Omnitrix.lime.withAlphaComponent(0.8)).setStroke()
        circle.lineWidth = 1.5
        circle.stroke()

        let cancelHighlight = hovered == nil && !demo && !preview
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

        let hint = preview ? "Hover to explore"
            : (demo ? "Click to pick" : (hovered == nil ? "Release to cancel" : "Release to apply"))
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
