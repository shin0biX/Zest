import AppKit

struct DragContext {
    let urls: [URL]
    let anchor: NSPoint          // screen coordinates, AppKit origin
    let kind: Kind?
}

/// Watches for Finder drags without any TCC permission: the left mouse button,
/// the modifier flags, and the global drag pasteboard are all readable by any app.
final class DragWatcher {
    var onArm: ((DragContext, WheelMode) -> Void)?
    var onSwitch: ((WheelMode) -> Void)?
    var onDisarm: (() -> Void)?

    private var timer: Timer?
    private var lastChange = NSPasteboard(name: .drag).changeCount
    private var dragging = false
    private var armed: WheelMode?
    private var lastFlags: NSEvent.ModifierFlags = []
    private var urls: [URL] = []
    private var anchor: NSPoint = .zero
    private var disarmWork: DispatchWorkItem?

    private let dragPasteboard = NSPasteboard(name: .drag)

    func start() {
        stop()
        lastFlags = NSEvent.modifierFlags
        let t = Timer(timeInterval: 1.0 / 45.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        disarmWork?.cancel()
        disarmWork = nil
    }

    private func tick() {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let pressed = (NSEvent.pressedMouseButtons & 1) != 0
        process(flags: flags, pressed: pressed, change: dragPasteboard.changeCount)
    }

    /// Decision logic split from the timer so it can be exercised without a
    /// physical drag. `change` is the drag pasteboard's change count.
    func process(flags: NSEvent.ModifierFlags, pressed: Bool, change: Int) {
        if pressed && !dragging && change != lastChange {
            if let found = readFileURLs(), !found.isEmpty {
                disarmWork?.cancel()
                disarmWork = nil
                dragging = true
                urls = found
                anchor = NSEvent.mouseLocation
                armed = nil
                lastChange = change
                Log.write("Drag start files=\(found.count) anchor=\(Int(anchor.x)),\(Int(anchor.y))")

                // A trigger held before the drag started also arms the wheel.
                if let mode = mode(for: flags) {
                    arm(mode)
                }
            }
        }

        if !pressed {
            if dragging {
                dragging = false
                if armed != nil {
                    scheduleDisarm()
                }
            }
            lastChange = change
            lastFlags = flags
            return
        }

        guard dragging else {
            lastFlags = flags
            return
        }

        lastChange = change

        // Newly tapped trigger switches the wheel; once open it stays open.
        let newlyPressed = flags.subtracting(lastFlags)
        if let mode = mode(for: newlyPressed) ?? (armed == nil ? mode(for: flags) : nil) {
            if armed == nil {
                arm(mode)
            } else if armed != mode {
                armed = mode
                onSwitch?(mode)
            }
        }

        lastFlags = flags
    }

    private func arm(_ mode: WheelMode) {
        armed = mode
        let kind = KindDetector.commonKind(urls)
        let context = DragContext(urls: urls, anchor: anchor, kind: kind)
        onArm?(context, mode)
    }

    /// A mouse-up both ends a cancel and precedes the drop that ends a drag
    /// session. `performDragOperation` is delivered a few milliseconds after
    /// `pressedMouseButtons` drops to zero; closing the overlay immediately
    /// loses that drop. Keep the wheel alive just long enough for the drag
    /// server to deliver it, then close if nothing committed.
    private func scheduleDisarm() {
        disarmWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.armed != nil else { return }
            self.armed = nil
            self.disarmWork = nil
            self.onDisarm?()
        }
        disarmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func mode(for flags: NSEvent.ModifierFlags) -> WheelMode? {
        if flags.contains(Prefs.convertKey.flag) { return .convert }
        if flags.contains(Prefs.toolsKey.flag) { return .tools }
        if flags.contains(Prefs.actionsKey.flag) { return .actions }
        return nil
    }

    private func readFileURLs() -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let items = dragPasteboard.readObjects(
            forClasses: [NSURL.self], options: options) as? [URL],
            !items.isEmpty else { return nil }
        return items
    }
}
