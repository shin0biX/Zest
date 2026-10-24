// dragtest.swift — external Finder drag harness for Zest.
//
// A standalone binary. It never links Zest's code: it drives Finder through the
// accessibility API, posts synthetic mouse and modifier events, reads the
// machine-readable lines Zest writes to ~/Library/Logs/Zest.log, and verifies
// the produced files structurally.
//
// The trigger modifier is pressed after mouse-down but before the drag starts.
// A synthetic flagsChanged sent mid-drag is not reliably re-targeted by the
// window server; `Zest uitest` covers mid-drag mode switching instead.
//
// Usage:
//   dragtest basic      one PNG, Shift, pick JPG
//   dragtest tools      one PNG, Command, pick Grayscale
//   dragtest actions    one PNG, Control, pick Copy Path
//   dragtest folder     one folder, Shift, pick ZIP
//   dragtest twopdf     two PNGs selected, Shift, pick PDF
//   dragtest pdfsplit   one 3-page PDF, Command, Split form, Apply
//   dragtest crop       Command, Crop editor, drag a box, Crop
//   dragtest markup     Command, Annotate editor, drag a box, Save
//   dragtest redact     Command, Redact editor, drag a box, Redact
//   dragtest metadata   Command, Metadata editor, Title/Author, Save
//   dragtest collisions keepBoth then replace on the same PNG
//   dragtest float      two PNGs, Control, Float panel, close rows
//   dragtest all        run every scenario in order
//
// Build and run: ./Harness/run.sh [scenario]

import AppKit
import ApplicationServices
import ImageIO
import PDFKit

// MARK: - Failure

struct HarnessFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Constants

let kZestBundle = "com.zest.app"
let kLogURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/Zest.log")
/// Fallbacks for logs written before the multi-ring wheel. Current builds log
/// `radius=` and `outer=` on every Wheel line.
let kFallbackRadius: CGFloat = 150
let kFallbackMargin: CGFloat = 246
let kMainDisplay = CGDisplayBounds(CGMainDisplayID())

// MARK: - Timing

func pause(_ seconds: TimeInterval) {
    usleep(useconds_t(max(0, seconds) * 1_000_000))
}

@discardableResult
func waitFor(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        pause(0.04)
    }
    return condition()
}

func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    guard condition else { throw HarnessFailure(message()) }
}

// MARK: - Accessibility helpers

func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return result == .success ? value : nil
}

func axText(_ element: AXUIElement, _ attribute: String) -> String? {
    guard let value = axValue(element, attribute) else { return nil }
    if let text = value as? String { return text }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    (axValue(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}

func axWindows(_ application: AXUIElement) -> [AXUIElement] {
    (axValue(application, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
}

func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    guard let value = axValue(element, attribute),
          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
    return point
}

func axSize(_ element: AXUIElement) -> CGSize? {
    guard let value = axValue(element, kAXSizeAttribute as String),
          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
    return size
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let origin = axPoint(element, kAXPositionAttribute as String),
          let size = axSize(element) else { return nil }
    return CGRect(origin: origin, size: size)
}

func axFind(_ root: AXUIElement, depth: Int = 12,
            _ matches: (AXUIElement) -> Bool) -> AXUIElement? {
    var budget = 8000
    func walk(_ element: AXUIElement, _ level: Int) -> AXUIElement? {
        guard budget > 0 else { return nil }
        budget -= 1
        if matches(element) { return element }
        guard level < depth else { return nil }
        for child in axChildren(element) {
            if let hit = walk(child, level + 1) { return hit }
        }
        return nil
    }
    return walk(root, 0)
}

// MARK: - Shell

@discardableResult
func shell(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(data: data, encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw HarnessFailure("\(executable) exited \(process.terminationStatus): \(output.suffix(800))")
    }
    return output
}

// MARK: - Log tail

final class LogTail {
    let url: URL
    private var offset: UInt64 = 0

    init(url: URL) {
        self.url = url
        offset = size()
    }

    func mark() { offset = size() }

    private func size() -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// Lines appended since the last call.
    func drain() -> [String] {
        let current = size()
        if current < offset { offset = 0 }
        guard current > offset, let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            let data = handle.readDataToEndOfFile()
            offset += UInt64(data.count)
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").map(String.init)
        } catch {
            return []
        }
    }

    func waitForLine(containing needle: String, timeout: TimeInterval) -> Bool {
        var seen = false
        _ = waitFor(timeout) {
            for line in drain() where line.contains(needle) { seen = true }
            return seen
        }
        return seen
    }

    func recent(_ count: Int = 20) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return Array(text.split(separator: "\n").suffix(count)).map(String.init)
    }
}

// MARK: - Wheel and choice lines

struct WheelLine {
    let mode: String
    let count: Int
    let anchor: CGPoint
    let screenSize: CGSize
    let choices: [String]
    /// Mid radius of the emphasized ring and the disc's outer radius.
    let radius: CGFloat
    let outer: CGFloat

    static func parse(_ line: String) -> WheelLine? {
        guard let range = line.range(of: "Wheel mode=") else { return nil }
        let body = String(line[range.lowerBound...])
        var mode = ""
        var count = 0
        var anchor: CGPoint?
        var screenSize: CGSize?
        var choices: [String] = []
        var radius = kFallbackRadius
        var outer = kFallbackMargin - 14

        for token in body.split(separator: " ").map(String.init) {
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "mode": mode = parts[1]
            case "count": count = Int(parts[1]) ?? 0
            case "anchor":
                let xy = parts[1].split(separator: ",").compactMap { Int($0) }
                if xy.count == 2 { anchor = CGPoint(x: xy[0], y: xy[1]) }
            case "screen":
                let wh = parts[1].split(separator: "x").compactMap { Int($0) }
                if wh.count == 2 { screenSize = CGSize(width: wh[0], height: wh[1]) }
            case "choices":
                choices = parts[1].split(separator: ",").map(String.init)
            case "radius":
                if let value = Double(parts[1]) { radius = CGFloat(value) }
            case "outer":
                if let value = Double(parts[1]) { outer = CGFloat(value) }
            default: break
            }
        }

        guard !mode.isEmpty, let anchor, let screenSize else { return nil }
        return WheelLine(mode: mode, count: count, anchor: anchor,
                         screenSize: screenSize, choices: choices,
                         radius: radius, outer: outer)
    }

    /// Wedge 0 is centered at the top, then clockwise in AppKit coordinates.
    /// Returns the point in CG global coordinates (top-left origin) for `index`
    /// in the emphasized ring.
    func slicePoint(index: Int) throws -> CGPoint {
        guard !choices.isEmpty else { throw HarnessFailure("wheel has no choices") }
        let count = CGFloat(choices.count)
        let step = 2 * CGFloat.pi / count
        let start = CGFloat.pi / 2 + step / 2
        let angle = start - (CGFloat(index) + 0.5) * step
        let margin = outer + 14

        var center = anchor
        center.x = min(max(center.x, min(margin, screenSize.width / 2)),
                       max(screenSize.width - margin, screenSize.width / 2))
        center.y = min(max(center.y, min(margin, screenSize.height / 2)),
                       max(screenSize.height - margin, screenSize.height / 2))

        let appKit = CGPoint(x: center.x + cos(angle) * radius,
                             y: center.y + sin(angle) * radius)
        return CGPoint(x: appKit.x, y: screenSize.height - appKit.y)
    }
}

struct ChoiceLine {
    let id: String
    let mode: String

    static func parse(_ line: String) -> ChoiceLine? {
        guard let range = line.range(of: "Choice ") else { return nil }
        let rest = line[range.upperBound...].split(separator: " ").map(String.init)
        guard let id = rest.first else { return nil }
        var mode = ""
        for token in rest where token.hasPrefix("mode=") {
            mode = String(token.dropFirst("mode=".count))
        }
        return ChoiceLine(id: id, mode: mode)
    }
}

// MARK: - Modifiers

struct Modifier {
    let name: String
    let keyCode: CGKeyCode
    let flag: CGEventFlags

    static let shift = Modifier(name: "shift", keyCode: 56, flag: .maskShift)
    static let command = Modifier(name: "command", keyCode: 55, flag: .maskCommand)
    static let control = Modifier(name: "control", keyCode: 59, flag: .maskControl)

    var nsFlag: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: UInt(flag.rawValue)) }
}

// MARK: - Sample files and structural verifiers

func makePNG(_ url: URL, size: NSSize, color: NSColor) throws {
    let image = NSImage(size: size)
    image.lockFocus()
    color.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: size.width * 0.2, y: size.height * 0.2,
                                width: size.width * 0.3, height: size.height * 0.3)).fill()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw HarnessFailure("could not synthesize \(url.lastPathComponent)")
    }
    try data.write(to: url)
}

func makePDF(_ url: URL, pages: Int) throws {
    let document = PDFDocument()
    for index in 0..<pages {
        let size = NSSize(width: 612, height: 792)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let text = "Zest harness page \(index + 1)" as NSString
        text.draw(at: NSPoint(x: 72, y: 700),
                  withAttributes: [.font: NSFont.systemFont(ofSize: 28),
                                   .foregroundColor: NSColor.black])
        image.unlockFocus()
        guard let page = PDFPage(image: image) else {
            throw HarnessFailure("could not make PDF page")
        }
        document.insert(page, at: document.pageCount)
    }
    guard document.write(to: url) else {
        throw HarnessFailure("could not write \(url.lastPathComponent)")
    }
}

struct ImageInfo {
    let type: String
    let width: Int
    let height: Int
}

func imageInfo(_ url: URL) throws -> ImageInfo {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetCount(source) > 0,
          let type = CGImageSourceGetType(source) as String?,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
        throw HarnessFailure("\(url.lastPathComponent) is not a readable image")
    }
    return ImageInfo(type: type, width: width, height: height)
}

func verifyPDF(_ url: URL, pages: Int) throws {
    guard let document = PDFDocument(url: url) else {
        throw HarnessFailure("\(url.lastPathComponent) is not a readable PDF")
    }
    try require(document.pageCount == pages,
                "\(url.lastPathComponent) has \(document.pageCount) pages, expected \(pages)")
}

func verifyGrayscale(_ url: URL) throws {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw HarnessFailure("\(url.lastPathComponent) is not a readable image")
    }
    let width = 48, height = 48
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: &pixels, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw HarnessFailure("could not create a verification context")
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var maxDelta = 0
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
        maxDelta = max(maxDelta, abs(r - g), abs(g - b))
    }
    try require(maxDelta <= 3, "\(url.lastPathComponent) is not neutral: channel delta \(maxDelta)")
}

func verifyZip(_ url: URL, contains expected: [String]) throws {
    let listing = try shell("/usr/bin/unzip", ["-Z1", url.path])
    let entries = Set(listing.split(separator: "\n").map(String.init))
    for name in expected {
        try require(entries.contains(name),
                    "\(url.lastPathComponent) has no entry \(name); entries: \(entries.sorted())")
    }
}

/// Counts pixels whose red channel dominates. The markup editor's default
/// stroke is systemRed, so a teal source starts near zero and the saved
/// annotation adds hundreds of red pixels.
func pixelCount(_ url: URL,
                where matches: (Int, Int, Int) -> Bool) throws -> Int {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw HarnessFailure("\(url.lastPathComponent) is not a readable image")
    }
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &pixels, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw HarnessFailure("could not create a verification context")
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var count = 0
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
        if matches(r, g, b) { count += 1 }
    }
    return count
}

func redPixelCount(_ url: URL, threshold: Int = 200) throws -> Int {
    try pixelCount(url) { r, g, b in
        r >= threshold && r - g >= 90 && r - b >= 90
    }
}

func blackPixelCount(_ url: URL) throws -> Int {
    try pixelCount(url) { r, g, b in r < 45 && g < 45 && b < 45 }
}

func tiffDescription(_ url: URL) throws -> (description: String?, artist: String?) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
        throw HarnessFailure("\(url.lastPathComponent) has no image properties")
    }
    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
    return (tiff[kCGImagePropertyTIFFImageDescription] as? String,
            tiff[kCGImagePropertyTIFFArtist] as? String)
}

func modificationDate(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}


// MARK: - Harness

final class Harness {
    let runRoot: URL
    let appURL: URL
    let log: LogTail
    let finder: NSRunningApplication
    let finderAX: AXUIElement
    let zest: NSRunningApplication
    let zestAX: AXUIElement

    private var held: CGEventFlags = []
    private var window: AXUIElement?
    private var windowFolder: URL?

    init(runRoot: URL, appURL: URL, relaunch: Bool) throws {
        guard AXIsProcessTrusted() else {
            throw HarnessFailure("""
                Accessibility is not granted to this host. macOS checks the app that \
                launched this harness (Terminal, iTerm2, …), not dragtest itself — \
                a grant on dragtest would not survive a rebuild anyway (ad-hoc \
                signature). System Settings → Privacy & Security → Accessibility → \
                enable the terminal you run Harness/run.sh from, relaunch it, rerun.
                """)
        }
        guard let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            throw HarnessFailure("Finder is not running")
        }
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)

        self.runRoot = runRoot
        self.appURL = appURL
        self.log = LogTail(url: kLogURL)
        self.finder = finder
        self.finderAX = AXUIElementCreateApplication(finder.processIdentifier)

        if relaunch, let running = Harness.runningZest() {
            running.terminate()
            if !waitFor(5, { running.isTerminated }) { running.forceTerminate() }
            _ = waitFor(3, { Harness.runningZest() == nil })
        }

        log.mark()
        var launched = false
        if Harness.runningZest() == nil {
            try Harness.launch(appURL: appURL)
            launched = true
        }
        // A terminated instance can disappear between the check above and the
        // guard below; launch once more rather than failing the whole run.
        if Harness.runningZest() == nil {
            try Harness.launch(appURL: appURL)
            launched = true
        }
        guard let zest = Harness.runningZest() else {
            throw HarnessFailure("Zest is not running")
        }
        if launched { _ = log.waitForLine(containing: "Zest launched.", timeout: 10) }
        self.zest = zest
        self.zestAX = AXUIElementCreateApplication(zest.processIdentifier)
        guard waitFor(10, { axText(self.zestAX, kAXRoleAttribute as String) == "AXApplication" }) else {
            throw HarnessFailure("Zest's accessibility tree did not become available")
        }
    }

    static func runningZest() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: kZestBundle).first
    }

    static func launch(appURL: URL) throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let semaphore = DispatchSemaphore(value: 0)
        var launchError: Error?
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            launchError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 15)
        if let launchError { throw HarnessFailure("launching Zest failed: \(launchError.localizedDescription)") }
        guard waitFor(10, { runningZest() != nil }) else {
            throw HarnessFailure("Zest did not start")
        }
    }

    // MARK: Finder

    func finderWindows() -> [AXUIElement] { axWindows(finderAX) }

    func browserWindow(for folder: URL) -> AXUIElement? {
        let target = folder.standardizedFileURL.path
        return finderWindows().first { window in
            if let document = axText(window, "AXDocument"), !document.isEmpty,
               let url = URL(string: document), url.isFileURL,
               url.standardizedFileURL.path == target {
                return true
            }
            return axText(window, kAXTitleAttribute as String) == folder.lastPathComponent
        }
    }

    func activateFinder() throws {
        finder.activate()
        guard waitFor(4, { NSWorkspace.shared.frontmostApplication?.processIdentifier == finder.processIdentifier }) else {
            throw HarnessFailure("Finder did not come to the front")
        }
    }

    func closeQuickLookIfNeeded() {
        let quickLook = finderWindows().first { axText($0, kAXTitleAttribute as String) == "Quick Look" }
        guard quickLook != nil,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == finder.processIdentifier else {
            return
        }
        postKey(53, down: true)
        postKey(53, down: false)
        pause(0.3)
    }

    func iconList(in window: AXUIElement) -> AXUIElement? {
        axFind(window) { element in
            axText(element, kAXRoleAttribute as String) == "AXList"
                && (axText(element, kAXDescriptionAttribute as String) ?? "")
                    .lowercased().contains("icon")
        }
    }

    func ensureIconView(_ window: AXUIElement) throws {
        if iconList(in: window) != nil { return }
        guard let button = axFind(window, { element in
            let role = axText(element, kAXRoleAttribute as String)
            let description = (axText(element, kAXDescriptionAttribute as String) ?? "").lowercased()
            let title = (axText(element, kAXTitleAttribute as String) ?? "").lowercased()
            return role == "AXRadioButton" && (description == "icon view" || title == "icon view")
        }) else {
            throw HarnessFailure("Finder is not in icon view and no icon-view control was found")
        }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard waitFor(3, { iconList(in: window) != nil }) else {
            throw HarnessFailure("switching Finder to icon view did not take")
        }
    }

    @discardableResult
    func show(_ target: URL) throws -> AXUIElement {
        let folder = target.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
        var found: AXUIElement?
        if !waitFor(6, { found = browserWindow(for: folder); return found != nil }) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
            guard waitFor(6, { found = browserWindow(for: folder); return found != nil }) else {
                throw HarnessFailure("Finder did not show \(folder.path)")
            }
        }
        guard let window = found else { throw HarnessFailure("Finder window vanished") }
        try activateFinder()
        closeQuickLookIfNeeded()
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        try ensureIconView(window)
        self.window = window
        self.windowFolder = folder
        return window
    }

    func imageElement(named name: String, in window: AXUIElement) -> AXUIElement? {
        axFind(window, depth: 16) { element in
            guard axText(element, kAXRoleAttribute as String) == "AXImage" else { return false }
            let names = [
                axText(element, "AXFilename"),
                axText(element, kAXTitleAttribute as String),
                axText(element, kAXDescriptionAttribute as String)
            ]
            return names.contains { $0 == name }
        }
    }

    func waitForFolderIcon(named name: String, timeout: TimeInterval = 5) throws {
        guard let window else { throw HarnessFailure("no Finder window is open") }
        guard waitForIcon(named: name, in: window, timeout: timeout) != nil else {
            throw HarnessFailure("Finder never showed \(name); icons: \(iconNames(in: window))")
        }
    }

    /// The icon's center once its frame has stopped moving. Finder animates
    /// icons into place after files appear; reading a frame too early can make
    /// the synthetic press land on a neighbouring file.
    func iconCenter(named name: String) throws -> CGPoint {
        guard let window else { throw HarnessFailure("no Finder window is open") }
        var last: CGRect?
        var stableSamples = 0
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if let icon = imageElement(named: name, in: window), let frame = axFrame(icon) {
                if let last,
                   abs(last.minX - frame.minX) < 0.5, abs(last.minY - frame.minY) < 0.5,
                   abs(last.width - frame.width) < 0.5, abs(last.height - frame.height) < 0.5 {
                    stableSamples += 1
                    if stableSamples >= 3 {
                        return CGPoint(x: frame.midX, y: frame.midY)
                    }
                } else {
                    stableSamples = 0
                }
                last = frame
            } else {
                last = nil
                stableSamples = 0
            }
            pause(0.1)
        }
        throw HarnessFailure("Finder's icon layout did not settle for \(name); "
            + "icons: \(iconNames(in: window))")
    }

    func waitForIcon(named name: String, in window: AXUIElement,
                     timeout: TimeInterval) -> AXUIElement? {
        var found: AXUIElement?
        _ = waitFor(timeout) {
            found = imageElement(named: name, in: window)
            return found != nil
        }
        return found
    }

    func iconNames(in window: AXUIElement) -> [String] {
        var names: [String] = []
        var budget = 4000
        func walk(_ element: AXUIElement) {
            guard budget > 0 else { return }
            budget -= 1
            if axText(element, kAXRoleAttribute as String) == "AXImage",
               let name = axText(element, "AXFilename") {
                names.append(name)
            }
            for child in axChildren(element) { walk(child) }
        }
        walk(window)
        return names
    }

    // MARK: Selection

    func selectedCount(in window: AXUIElement) -> Int? {
        guard let list = iconList(in: window),
              let selected = axValue(list, kAXSelectedChildrenAttribute as String) as? [AXUIElement] else {
            return nil
        }
        return selected.count
    }

    func select(files: [URL]) throws {
        guard let first = files.first else { throw HarnessFailure("nothing to select") }
        let window = try show(first)

        if files.count == 1 {
            click(try iconCenter(named: first.lastPathComponent))
            if let count = selectedCount(in: window) {
                try require(count == 1, "Finder reports \(count) selected items, expected 1")
            }
            return
        }

        // The scenario folder contains exactly the files to drag. Focus the icon
        // view, then select all with Cmd+A. This is deterministic where
        // AXSelectedChildren and synthetic shift-clicks race with Finder's own
        // activation selection.
        click(try iconCenter(named: first.lastPathComponent))
        postKey(0, down: true, flags: .maskCommand)   // kVK_ANSI_A
        postKey(0, down: false, flags: .maskCommand)
        pause(0.25)
        if selectedCount(in: window) == files.count { return }

        // Fallback: set the icon view's selection directly.
        if setFinderSelection(files, in: window) { return }
        pause(0.4)
        if setFinderSelection(files, in: window) { return }

        if let count = selectedCount(in: window) {
            try require(count == files.count,
                        "Finder reports \(count) selected items, expected \(files.count)")
        }
    }

    /// Set the icon view's AXSelectedChildren directly. Synthetic shift-clicks
    /// are occasionally dropped by Finder while it lays icons out; selection is
    /// setup for the drag, not the behavior under test.
    func setFinderSelection(_ files: [URL], in window: AXUIElement) -> Bool {
        guard let list = iconList(in: window) else { return false }
        var icons: [AXUIElement] = []
        for url in files {
            guard let icon = waitForIcon(named: url.lastPathComponent, in: window, timeout: 3) else {
                return false
            }
            icons.append(icon)
        }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(list, kAXSelectedChildrenAttribute as CFString,
                                             &settable) == .success, settable.boolValue else {
            return false
        }
        let result = AXUIElementSetAttributeValue(list, kAXSelectedChildrenAttribute as CFString,
                                                  icons as CFArray)
        guard result == .success else { return false }
        pause(0.25)
        return selectedCount(in: window) == files.count
    }

    // MARK: Events

    func postMouse(_ type: CGEventType, _ point: CGPoint, flags: CGEventFlags = []) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    func postKey(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode,
                                  keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    func postFlags(_ modifier: Modifier, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: modifier.keyCode,
                                  keyDown: down) else { return }
        event.type = .flagsChanged
        event.flags = held
        event.post(tap: .cghidEventTap)
    }

    func press(_ modifier: Modifier) {
        held.insert(modifier.flag)
        postFlags(modifier, down: true)
        _ = waitFor(1.5) { NSEvent.modifierFlags.contains(modifier.nsFlag) }
    }

    func release(_ modifier: Modifier) {
        held.remove(modifier.flag)
        postFlags(modifier, down: false)
    }

    func click(_ point: CGPoint, flags: CGEventFlags = []) {
        postMouse(.mouseMoved, point, flags: flags)
        pause(0.03)
        postMouse(.leftMouseDown, point, flags: flags)
        pause(0.05)
        postMouse(.leftMouseUp, point, flags: flags)
        pause(0.15)
    }

    /// A plain mouse drag, used inside Zest's own tool canvases.
    func dragMouse(from: CGPoint, to: CGPoint, steps: Int = 12) {
        postMouse(.mouseMoved, from)
        pause(0.05)
        postMouse(.leftMouseDown, from)
        pause(0.08)
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: from.x + (to.x - from.x) * t,
                                y: from.y + (to.y - from.y) * t)
            postMouse(.leftMouseDragged, point)
            pause(0.03)
        }
        pause(0.1)
        postMouse(.leftMouseUp, to)
        pause(0.3)
    }

    func cancelDrag(at point: CGPoint) {
        postMouse(.leftMouseUp, point, flags: held)
        for modifier in [Modifier.shift, .command, .control] where held.contains(modifier.flag) {
            release(modifier)
        }
        pause(0.2)
    }

    // MARK: Drag and choose

    @discardableResult
    func dragAndChoose(trigger: Modifier, expectedMode: String, choice: String,
                       fromIconNamed iconName: String,
                       timeout: TimeInterval = 10,
                       dropAttempt: Int = 1) throws -> WheelLine {
        guard let window else { throw HarnessFailure("no Finder window is open") }

        try activateFinder()
        closeQuickLookIfNeeded()
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)

        let pasteboard = NSPasteboard(name: .drag)
        var start = try iconCenter(named: iconName)
        var current = start
        var dragging = false
        var lastSelection = -1
        var draggedNames: [String] = []
        var mismatch: String?

        for attempt in 1...3 {
            start = try iconCenter(named: iconName)
            current = start
            let initialChange = pasteboard.changeCount
            log.mark()

            postMouse(.mouseMoved, start)
            pause(0.05)
            postMouse(.leftMouseDown, start)
            pause(0.06)
            // Press the trigger before the drag starts. macOS does not reliably
            // re-target a synthetic drag to a panel that appears mid-session, so
            // a mid-drag flagsChanged is flaky in this harness even though real
            // modifier taps work. `uitest` covers mid-drag mode switching.
            press(trigger)
            for step in 1...8 {
                current = CGPoint(x: start.x + CGFloat(step) * 4,
                                  y: start.y + CGFloat(step) * 4)
                postMouse(.leftMouseDragged, current, flags: held)
                pause(0.04)
            }

            dragging = waitFor(2.5) {
                guard pasteboard.changeCount != initialChange else { return false }
                let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
                                                   options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
                return !urls.isEmpty
            }

            if dragging {
                draggedNames = ((pasteboard.readObjects(forClasses: [NSURL.self],
                                                        options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? [])
                    .map(\.lastPathComponent)
                if !draggedNames.isEmpty, !draggedNames.contains(iconName) {
                    // Finder rearranged its icons between reading the frame and
                    // the mouse-down. Drop this session and aim again.
                    mismatch = "Finder dragged \(draggedNames) instead of \(iconName)"
                    cancelDrag(at: current)
                    lastSelection = selectedCount(in: window) ?? -1
                    if attempt < 3 {
                        print("      drag target mismatch: \(mismatch ?? ""); retrying")
                        pause(0.4)
                        click(start)
                        pause(0.2)
                        continue
                    }
                    throw HarnessFailure("\(mismatch ?? "wrong drag target") in 3 attempts")
                }
                break
            }

            // Finder occasionally ignores a synthetic press. Release cleanly,
            // re-select the icon, and try again.
            cancelDrag(at: current)
            lastSelection = selectedCount(in: window) ?? -1
            if attempt < 3 {
                print("      drag start retry \(attempt)/3 for \(iconName) "
                    + "(Finder selection: \(lastSelection))")
                pause(0.4)
                click(start)
                pause(0.2)
            }
        }

        guard dragging else {
            cancelDrag(at: current)
            throw HarnessFailure("Finder did not start a drag for \(iconName) in 3 attempts "
                + "(selection: \(lastSelection)); icons: \(iconNames(in: window))")
        }

        pause(0.2)
        guard NSEvent.modifierFlags.contains(trigger.nsFlag) else {
            cancelDrag(at: current)
            throw HarnessFailure("synthetic \(trigger.name) is not visible to the system")
        }

        var wheel: WheelLine?
        let armed = waitFor(timeout) {
            for line in log.drain() {
                if let parsed = WheelLine.parse(line), parsed.mode == expectedMode {
                    wheel = parsed
                    return true
                }
            }
            return false
        }
        guard armed, let wheel else {
            cancelDrag(at: current)
            throw HarnessFailure("the wheel did not arm in \(expectedMode) mode "
                + "(dragged: \(draggedNames)). Recent log:\n"
                + log.recent(12).joined(separator: "\n"))
        }

        // The panel is ordered front and fades in before it can receive drag
        // updates. A synthetic drag can reach the slice while the window is
        // still being installed, so give the overlay one beat to settle.
        pause(0.35)
        if !NSEvent.modifierFlags.contains(trigger.nsFlag) {
            press(trigger)
        }

        let choices = wheel.choices
        guard choices.contains(choice) else {
            cancelDrag(at: current)
            throw HarnessFailure("the \(expectedMode) wheel has no \(choice) "
                + "for dragged \(draggedNames); choices: \(choices)")
        }
        guard let index = choices.firstIndex(of: choice) else {
            cancelDrag(at: current)
            throw HarnessFailure("could not locate \(choice)")
        }

        try require(abs(wheel.screenSize.width - kMainDisplay.width) < 1
                    && abs(wheel.screenSize.height - kMainDisplay.height) < 1,
                    "the wheel is on \(wheel.screenSize), not the main display \(kMainDisplay.size); "
                    + "move Finder to the main display")

        let target = try wheel.slicePoint(index: index)
        for step in 1...10 {
            let t = CGFloat(step) / 10
            let point = CGPoint(x: current.x + (target.x - current.x) * t,
                                y: current.y + (target.y - current.y) * t)
            postMouse(.leftMouseDragged, point, flags: held)
            pause(0.02)
        }
        pause(0.1)
        postMouse(.leftMouseUp, target, flags: held)

        var choiceLine: ChoiceLine?
        let committed = waitFor(6) {
            for line in log.drain() {
                if let parsed = ChoiceLine.parse(line) {
                    choiceLine = parsed
                    return true
                }
            }
            return false
        }
        let released = held
        for modifier in [Modifier.shift, .command, .control] where released.contains(modifier.flag) {
            release(modifier)
        }

        guard committed, let choiceLine else {
            // A synthetic drag occasionally ends before the panel receives
            // draggingEntered, especially right after launch. Start a fresh
            // drag once the disarm grace period has closed the old wheel.
            if dropAttempt < 3 {
                print("      drop retry \(dropAttempt)/3 for \(iconName)")
                cancelDrag(at: target)
                pause(1.3)
                return try dragAndChoose(trigger: trigger, expectedMode: expectedMode,
                                         choice: choice, fromIconNamed: iconName,
                                         timeout: timeout, dropAttempt: dropAttempt + 1)
            }
            throw HarnessFailure("the drop never reached the wheel (no Choice line). Recent log:\n"
                + log.recent(12).joined(separator: "\n"))
        }
        guard choiceLine.id == choice else {
            throw HarnessFailure("the wheel committed \(choiceLine.id) instead of \(choice)")
        }
        return wheel
    }

    // MARK: Zest windows and output

    func zestWindows() -> [AXUIElement] { axWindows(zestAX) }

    func windowTitles() -> [String] {
        zestWindows().map { window in
            let title = axText(window, kAXTitleAttribute as String) ?? ""
            let texts = collectStaticText(window).prefix(2).joined(separator: " / ")
            return "[\(title)] \(texts)"
        }
    }

    func collectStaticText(_ root: AXUIElement) -> [String] {
        var values: [String] = []
        var budget = 400
        func walk(_ element: AXUIElement) {
            guard budget > 0 else { return }
            budget -= 1
            if axText(element, kAXRoleAttribute as String) == "AXStaticText",
               let value = axText(element, kAXValueAttribute as String), !value.isEmpty {
                values.append(value)
            }
            for child in axChildren(element) { walk(child) }
        }
        walk(root)
        return values
    }

    func hudText() -> String {
        zestWindows().map { collectStaticText($0).joined(separator: " / ") }
            .filter { !$0.isEmpty }
            .joined(separator: " || ")
    }

    @discardableResult
    func pressZestButton(_ titles: [String], timeout: TimeInterval) throws -> String {
        var pressed: String?
        let found = waitFor(timeout) {
            for window in zestWindows() {
                for title in titles {
                    if let button = axFind(window, depth: 12, { element in
                        axText(element, kAXRoleAttribute as String) == "AXButton"
                            && axText(element, kAXTitleAttribute as String) == title
                    }) {
                        AXUIElementPerformAction(button, kAXPressAction as CFString)
                        pressed = title
                        return true
                    }
                }
            }
            return false
        }
        guard found, let pressed else {
            throw HarnessFailure("Zest never showed \(titles.joined(separator: "/")); windows: \(windowTitles())")
        }
        return pressed
    }

    func waitForZestWindow(title: String, timeout: TimeInterval) throws -> AXUIElement {
        var found: AXUIElement?
        let appeared = waitFor(timeout) {
            found = zestWindows().first {
                axText($0, kAXTitleAttribute as String) == title
            }
            return found != nil
        }
        guard appeared, let found else {
            throw HarnessFailure("Zest never showed the window \"\(title)\"; windows: \(windowTitles())")
        }
        return found
    }

    func pressButton(in window: AXUIElement, title: String, timeout: TimeInterval) throws {
        var button: AXUIElement?
        let found = waitFor(timeout) {
            button = axFind(window, depth: 20, { element in
                axText(element, kAXRoleAttribute as String) == "AXButton"
                    && axText(element, kAXTitleAttribute as String) == title
            })
            return button != nil
        }
        guard found, let button else {
            throw HarnessFailure("the window \"\(axText(window, kAXTitleAttribute as String) ?? "?")"
                + "\" has no \(title) button; texts: \(collectStaticText(window))")
        }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard result == .success else {
            throw HarnessFailure("pressing \(title) failed with AX error \(result.rawValue)")
        }
    }

    func button(in window: AXUIElement, title: String) -> AXUIElement? {
        axFind(window, depth: 20, { element in
            axText(element, kAXRoleAttribute as String) == "AXButton"
                && axText(element, kAXTitleAttribute as String) == title
        })
    }

    func isEnabled(_ element: AXUIElement) -> Bool {
        guard let value = axValue(element, kAXEnabledAttribute as String) else { return true }
        return (value as? NSNumber)?.boolValue ?? true
    }

    /// A click in the title bar activates the window without touching the canvas.
    func activateWindow(_ window: AXUIElement) throws {
        guard let frame = axFrame(window) else {
            throw HarnessFailure("the tool window has no frame")
        }
        click(CGPoint(x: frame.midX, y: frame.minY + 12))
        pause(0.3)
    }

    /// A tool window's canvas, in CG screen coordinates. Content is laid out
    /// from the bottom in AppKit, so the canvas top is the content top.
    func canvasRect(of window: AXUIElement, contentHeight: CGFloat,
                    canvasHeight: CGFloat) throws -> CGRect {
        guard let frame = axFrame(window) else {
            throw HarnessFailure("the tool window has no frame")
        }
        let titleBar = frame.height - contentHeight
        guard titleBar >= 0, titleBar < 100 else {
            throw HarnessFailure("unexpected title bar \(titleBar) for a \(contentHeight)pt content window")
        }
        return CGRect(x: frame.minX, y: frame.minY + titleBar,
                      width: frame.width, height: canvasHeight)
    }

    /// The image rectangle inside a canvas, in CG screen coordinates.
    func imageRect(source: ImageInfo, canvas: CGRect) -> CGRect {
        let scale = min(canvas.width / CGFloat(source.width),
                        canvas.height / CGFloat(source.height))
        let width = CGFloat(source.width) * scale
        let height = CGFloat(source.height) * scale
        return CGRect(x: canvas.minX + (canvas.width - width) / 2,
                      y: canvas.minY + (canvas.height - height) / 2,
                      width: width, height: height)
    }

    /// Screen point at a normalized position measured from the image's top-left.
    func point(in rect: CGRect, x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }

    func textFields(in window: AXUIElement) -> [AXUIElement] {
        var fields: [AXUIElement] = []
        var budget = 600
        func walk(_ element: AXUIElement) {
            guard budget > 0 else { return }
            budget -= 1
            if axText(element, kAXRoleAttribute as String) == "AXTextField" {
                fields.append(element)
            }
            for child in axChildren(element) { walk(child) }
        }
        walk(window)
        return fields.sorted { lhs, rhs in
            (axFrame(lhs)?.minY ?? 0) < (axFrame(rhs)?.minY ?? 0)
        }
    }

    @discardableResult
    func setTextField(_ field: AXUIElement, to value: String) throws -> AXUIElement {
        let result = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString,
                                                  value as CFString)
        guard result == .success else {
            throw HarnessFailure("setting a text field failed with AX error \(result.rawValue)")
        }
        return field
    }

    func dismissZestAlerts() {
        for window in zestWindows() {
            for title in ["Cancel", "OK", "Close"] {
                if let button = axFind(window, depth: 10, { element in
                    axText(element, kAXRoleAttribute as String) == "AXButton"
                        && axText(element, kAXTitleAttribute as String) == title
                }) {
                    AXUIElementPerformAction(button, kAXPressAction as CFString)
                    pause(0.1)
                    break
                }
            }
        }
    }

    func snapshot(_ folder: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(names.map { folder.appendingPathComponent($0).standardizedFileURL.path })
    }

    func waitForNewFiles(in folder: URL, since baseline: Set<String>,
                         minimum: Int, timeout: TimeInterval) throws -> [URL] {
        func current() -> [URL] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return names
                .filter { !$0.hasPrefix(".") }
                .map { folder.appendingPathComponent($0) }
                .filter { !baseline.contains($0.standardizedFileURL.path) }
        }
        func sizes(_ urls: [URL]) -> [String: Int64] {
            var result: [String: Int64] = [:]
            for url in urls {
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                result[url.path] = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            }
            return result
        }

        // A file appears when the writer creates it, not when it finishes. Wait
        // for non-zero sizes that stop changing before handing paths to a parser.
        let deadline = Date().addingTimeInterval(timeout)
        var outputs: [URL] = []
        while Date() < deadline {
            outputs = current()
            let snapshot = sizes(outputs)
            if outputs.count >= minimum, snapshot.values.allSatisfy({ $0 > 0 }) {
                pause(0.3)
                if snapshot == sizes(current()) {
                    return outputs
                }
            }
            pause(0.08)
        }
        throw HarnessFailure("no stable output in \(folder.path) after \(Int(timeout))s. "
            + "HUD: \(hudText()). Log: "
            + log.recent(8).joined(separator: " | "))
    }

    func waitForChange(of url: URL, since date: Date?, timeout: TimeInterval) throws {
        let changed = waitFor(timeout) {
            guard let current = modificationDate(url) else { return false }
            guard let date else { return true }
            return current > date
        }
        guard changed else {
            throw HarnessFailure("\(url.lastPathComponent) was not rewritten after \(Int(timeout))s; "
                + "HUD: \(hudText())")
        }
    }

    func setCollisionPolicy(_ policy: String) throws {
        try shell("/usr/bin/defaults", ["write", kZestBundle, "collision", policy])
        // cfprefsd notifies the running app; give it a beat to pick the value up.
        pause(0.6)
    }

    /// A Zest panel whose static text contains every needle.
    func panel(containing needles: [String]) -> AXUIElement? {
        zestWindows().first { window in
            let texts = collectStaticText(window)
            return needles.allSatisfy { texts.contains($0) }
        }
    }

    func waitForPanel(containing needles: [String], timeout: TimeInterval) throws -> AXUIElement {
        var found: AXUIElement?
        let appeared = waitFor(timeout) {
            found = panel(containing: needles)
            return found != nil
        }
        guard appeared, let found else {
            throw HarnessFailure("Zest never showed a panel containing \(needles); "
                + "windows: \(windowTitles())")
        }
        return found
    }

    // MARK: Cleanup

    func cleanupAfterScenario() {
        for modifier in [Modifier.shift, .command, .control] where held.contains(modifier.flag) {
            release(modifier)
        }
        let point = NSEvent.mouseLocation
        postMouse(.leftMouseUp, CGPoint(x: point.x, y: kMainDisplay.height - point.y))
        pause(0.2)
        dismissZestAlerts()
    }
}

// MARK: - Scenarios

enum Scenario: String, CaseIterable {
    case basic, tools, actions, folder, twopdf, pdfsplit
    case crop, markup, redact, metadata, collisions, float

    var detail: String {
        switch self {
        case .basic: return "PNG → JPG through the Shift wheel"
        case .tools: return "PNG → Grayscale through the Command wheel"
        case .actions: return "PNG → Copy Path through the Control wheel"
        case .folder: return "folder → ZIP through the Shift wheel"
        case .twopdf: return "two PNGs → one 2-page PDF"
        case .pdfsplit: return "3-page PDF → Split form → three one-page PDFs"
        case .crop: return "Crop editor → drag a box → 40% crop"
        case .markup: return "Annotate editor → drag a box → red stroke saved"
        case .redact: return "Redact editor → drag a box → black fill saved"
        case .metadata: return "Metadata editor → Title/Author → PNG tags"
        case .collisions: return "keepBoth then replace through the wheel"
        case .float: return "Float panel → per-row close → panel close"
        }
    }

    func run(_ harness: Harness) throws -> String {
        let root = harness.runRoot.appendingPathComponent(rawValue, isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        harness.dismissZestAlerts()

        switch self {
        case .basic:
            let png = root.appendingPathComponent("probe.png")
            try makePNG(png, size: NSSize(width: 640, height: 400), color: .systemOrange)
            let source = try imageInfo(png)
            let baseline = harness.snapshot(root)
            try harness.select(files: [png])
            try harness.dragAndChoose(trigger: .shift, expectedMode: "convert",
                                      choice: "fmt-jpg", fromIconNamed: png.lastPathComponent)
            let outputs = try harness.waitForNewFiles(in: root, since: baseline,
                                                      minimum: 1, timeout: 30)
            guard let jpg = outputs.first(where: { $0.pathExtension.lowercased() == "jpg" }) else {
                throw HarnessFailure("expected a .jpg, got \(outputs.map(\.lastPathComponent))")
            }
            let info = try imageInfo(jpg)
            try require(info.type.contains("jpeg"), "\(jpg.lastPathComponent) is \(info.type)")
            try require(info.width == source.width && info.height == source.height,
                        "\(jpg.lastPathComponent) is \(info.width)×\(info.height), expected \(source.width)×\(source.height)")
            return "probe.png → \(jpg.lastPathComponent) (\(info.width)×\(info.height), jpeg)"

        case .tools:
            let png = root.appendingPathComponent("tone.png")
            try makePNG(png, size: NSSize(width: 512, height: 384), color: .systemTeal)
            let source = try imageInfo(png)
            let baseline = harness.snapshot(root)
            try harness.select(files: [png])
            try harness.dragAndChoose(trigger: .command, expectedMode: "tools",
                                      choice: "tool-grayscale", fromIconNamed: png.lastPathComponent)
            let outputs = try harness.waitForNewFiles(in: root, since: baseline,
                                                      minimum: 1, timeout: 30)
            guard let bw = outputs.first(where: { $0.lastPathComponent.hasSuffix("-bw.png") }) else {
                throw HarnessFailure("expected tone-bw.png, got \(outputs.map(\.lastPathComponent))")
            }
            let info = try imageInfo(bw)
            try require(info.width == source.width && info.height == source.height,
                        "\(bw.lastPathComponent) is \(info.width)×\(info.height), expected \(source.width)×\(source.height)")
            try verifyGrayscale(bw)
            return "tone.png → \(bw.lastPathComponent) (neutral channels, \(info.width)×\(info.height))"

        case .actions:
            let png = root.appendingPathComponent("clip.png")
            try makePNG(png, size: NSSize(width: 320, height: 240), color: .systemPurple)
            let baseline = harness.snapshot(root)
            NSPasteboard.general.clearContents()
            try harness.select(files: [png])
            try harness.dragAndChoose(trigger: .control, expectedMode: "actions",
                                      choice: "action-copyPath", fromIconNamed: png.lastPathComponent)
            let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
            try require(clipboard == png.path,
                        "clipboard holds '\(clipboard.prefix(120))', expected \(png.path)")
            pause(0.5)
            let extra = harness.snapshot(root).subtracting(baseline)
            try require(extra.isEmpty, "Copy Path wrote files: \(extra)")
            return "clipboard holds \(png.lastPathComponent)'s path; no files written"

        case .folder:
            let box = root.appendingPathComponent("box", isDirectory: true)
            try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
            try "zest".write(to: box.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
            let baseline = harness.snapshot(root)
            try harness.select(files: [box])
            try harness.dragAndChoose(trigger: .shift, expectedMode: "convert",
                                      choice: "fmt-zip", fromIconNamed: box.lastPathComponent)
            let outputs = try harness.waitForNewFiles(in: root, since: baseline,
                                                      minimum: 1, timeout: 30)
            guard let zip = outputs.first(where: { $0.pathExtension.lowercased() == "zip" }) else {
                throw HarnessFailure("expected a .zip, got \(outputs.map(\.lastPathComponent))")
            }
            try verifyZip(zip, contains: ["box/", "box/inner.txt"])
            return "box/ → \(zip.lastPathComponent) with box/inner.txt"

        case .twopdf:
            let alpha = root.appendingPathComponent("alpha.png")
            let beta = root.appendingPathComponent("beta.png")
            try makePNG(alpha, size: NSSize(width: 800, height: 600), color: .systemRed)
            try makePNG(beta, size: NSSize(width: 500, height: 700), color: .systemBlue)
            let baseline = harness.snapshot(root)
            try harness.select(files: [alpha, beta])
            try harness.dragAndChoose(trigger: .shift, expectedMode: "convert",
                                      choice: "fmt-pdf", fromIconNamed: beta.lastPathComponent)
            let outputs = try harness.waitForNewFiles(in: root, since: baseline,
                                                      minimum: 1, timeout: 30)
            guard let pdf = outputs.first(where: { $0.pathExtension.lowercased() == "pdf" }) else {
                throw HarnessFailure("expected a .pdf, got \(outputs.map(\.lastPathComponent))")
            }
            try verifyPDF(pdf, pages: 2)
            return "alpha.png + beta.png → \(pdf.lastPathComponent) (2 pages)"

        case .pdfsplit:
            let pdf = root.appendingPathComponent("doc.pdf")
            try makePDF(pdf, pages: 3)
            let baseline = harness.snapshot(root)
            try harness.select(files: [pdf])
            try harness.dragAndChoose(trigger: .command, expectedMode: "tools",
                                      choice: "tool-split", fromIconNamed: pdf.lastPathComponent)
            let button = try harness.pressZestButton(["Apply"], timeout: 8)
            let outputs = try harness.waitForNewFiles(in: root, since: baseline,
                                                      minimum: 3, timeout: 30)
            let pages = outputs.filter { $0.pathExtension.lowercased() == "pdf" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            try require(pages.count == 3, "expected 3 PDFs, got \(pages.map(\.lastPathComponent))")
            for page in pages { try verifyPDF(page, pages: 1) }
            let names = pages.map(\.lastPathComponent).joined(separator: ", ")
            return "\(button) pressed; doc.pdf → \(names)"

        case .crop:
            let png = root.appendingPathComponent("probe.png")
            try makePNG(png, size: NSSize(width: 640, height: 400), color: .systemOrange)
            let source = try imageInfo(png)
            let baseline = harness.snapshot(root)
            try harness.select(files: [png])
            try harness.dragAndChoose(trigger: .command, expectedMode: "tools",
                                      choice: "tool-crop", fromIconNamed: png.lastPathComponent)
            let window = try harness.waitForZestWindow(title: "Crop \(png.lastPathComponent)",
                                                       timeout: 8)
            let canvas = try harness.canvasRect(of: window, contentHeight: 640, canvasHeight: 582)
            try harness.activateWindow(window)
            let image = harness.imageRect(source: source, canvas: canvas)
            let from = harness.point(in: image, x: 0.3, y: 0.3)
            let to = harness.point(in: image, x: 0.7, y: 0.7)
            harness.dragMouse(from: from, to: to)
            if let button = harness.button(in: window, title: "Crop"), !harness.isEnabled(button) {
                print("      crop: the first drag did not register; activating and retrying")
                try harness.activateWindow(window)
                harness.dragMouse(from: from, to: to)
            }
            guard let cropButton = harness.button(in: window, title: "Crop"),
                  harness.isEnabled(cropButton) else {
                throw HarnessFailure("Crop stayed disabled after dragging \(from) → \(to); "
                    + "window \(axFrame(window)?.debugDescription ?? "nil") canvas \(canvas) "
                    + "image \(image)")
            }
            try harness.pressButton(in: window, title: "Crop", timeout: 5)
            let outputs = try harness.waitForNewFiles(in: root, since: baseline,
                                                      minimum: 1, timeout: 30)
            guard let cropped = outputs.first(where: { $0.lastPathComponent.hasSuffix("-cropped.png") }) else {
                throw HarnessFailure("expected probe-cropped.png, got \(outputs.map(\.lastPathComponent))")
            }
            let info = try imageInfo(cropped)
            let expectedW = Int((Double(source.width) * 0.4).rounded())
            let expectedH = Int((Double(source.height) * 0.4).rounded())
            try require(abs(info.width - expectedW) <= 4 && abs(info.height - expectedH) <= 4,
                        "\(cropped.lastPathComponent) is \(info.width)×\(info.height), "
                        + "expected ~\(expectedW)×\(expectedH) from \(source.width)×\(source.height); "
                        + "window \(axFrame(window)?.debugDescription ?? "nil") "
                        + "canvas \(canvas) image \(image) from \(from) to \(to)")
            return "drag 30–70% → \(cropped.lastPathComponent) "
                + "(\(info.width)×\(info.height), source \(source.width)×\(source.height))"

        case .markup:
            let png = root.appendingPathComponent("paint.png")
            try makePNG(png, size: NSSize(width: 640, height: 400), color: .systemTeal)
            let source = try imageInfo(png)
            let redBefore = try redPixelCount(png)
            let baseline = harness.snapshot(root)
            try harness.select(files: [png])
            try harness.dragAndChoose(trigger: .command, expectedMode: "tools",
                                      choice: "tool-annotate", fromIconNamed: png.lastPathComponent)
            let window = try harness.waitForZestWindow(title: "Annotate \(png.lastPathComponent)",
                                                       timeout: 8)
            let canvas = try harness.canvasRect(of: window, contentHeight: 720, canvasHeight: 668)
            try harness.activateWindow(window)
            let image = harness.imageRect(source: source, canvas: canvas)
            harness.dragMouse(from: harness.point(in: image, x: 0.25, y: 0.25),
                              to: harness.point(in: image, x: 0.75, y: 0.75))
            try harness.pressButton(in: window, title: "Save", timeout: 5)
            let outputs = try harness.waitForNewFiles(in: root, since: baseline,
                                                      minimum: 1, timeout: 30)
            guard let annotated = outputs.first(where: {
                $0.lastPathComponent.hasSuffix("-annotated.png")
            }) else {
                throw HarnessFailure("expected paint-annotated.png, got \(outputs.map(\.lastPathComponent))")
            }
            let info = try imageInfo(annotated)
            try require(info.width == source.width && info.height == source.height,
                        "\(annotated.lastPathComponent) is \(info.width)×\(info.height), "
                        + "expected \(source.width)×\(source.height)")
            let redAfter = try redPixelCount(annotated)
            try require(redBefore < 50 && redAfter > 200,
                        "red pixels \(redBefore) → \(redAfter); the stroke was not saved")
            return "box saved → \(annotated.lastPathComponent) "
                + "(same size, red pixels \(redBefore) → \(redAfter))"

        case .redact:
            let png = root.appendingPathComponent("secret.png")
            try makePNG(png, size: NSSize(width: 640, height: 400), color: .systemTeal)
            let source = try imageInfo(png)
            let blackBefore = try blackPixelCount(png)
            let baseline = harness.snapshot(root)
            try harness.select(files: [png])
            try harness.dragAndChoose(trigger: .command, expectedMode: "tools",
                                      choice: "tool-redact", fromIconNamed: png.lastPathComponent)
            let window = try harness.waitForZestWindow(title: "Redact \(png.lastPathComponent)",
                                                       timeout: 8)
            let canvas = try harness.canvasRect(of: window, contentHeight: 720, canvasHeight: 668)
            try harness.activateWindow(window)
            let image = harness.imageRect(source: source, canvas: canvas)
            harness.dragMouse(from: harness.point(in: image, x: 0.3, y: 0.3),
                              to: harness.point(in: image, x: 0.7, y: 0.7))
            try harness.pressButton(in: window, title: "Redact", timeout: 5)
            let outputs = try harness.waitForNewFiles(in: root, since: baseline,
                                                      minimum: 1, timeout: 30)
            guard let redacted = outputs.first(where: {
                $0.lastPathComponent.hasSuffix("-redacted.png")
            }) else {
                throw HarnessFailure("expected secret-redacted.png, got \(outputs.map(\.lastPathComponent))")
            }
            let info = try imageInfo(redacted)
            try require(info.width == source.width && info.height == source.height,
                        "\(redacted.lastPathComponent) is \(info.width)×\(info.height), "
                        + "expected \(source.width)×\(source.height)")
            let blackAfter = try blackPixelCount(redacted)
            try require(blackBefore < 50 && blackAfter > 50_000,
                        "black pixels \(blackBefore) → \(blackAfter); the redaction was not filled")
            return "box filled → \(redacted.lastPathComponent) "
                + "(same size, black pixels \(blackBefore) → \(blackAfter))"

        case .metadata:
            let png = root.appendingPathComponent("tagged.png")
            try makePNG(png, size: NSSize(width: 480, height: 320), color: .systemGreen)
            let baseline = harness.snapshot(root)
            try harness.select(files: [png])
            try harness.dragAndChoose(trigger: .command, expectedMode: "tools",
                                      choice: "tool-metadata", fromIconNamed: png.lastPathComponent)
            let window = try harness.waitForPanel(containing: ["Metadata", png.lastPathComponent],
                                                  timeout: 8)
            let fields = harness.textFields(in: window)
            try require(fields.count >= 2, "the metadata editor showed \(fields.count) text fields")
            try harness.setTextField(fields[0], to: "Zest Harness")
            try harness.setTextField(fields[1], to: "Bench")
            pause(0.2)
            try harness.pressButton(in: window, title: "Save", timeout: 5)
            let outputs = try harness.waitForNewFiles(in: root, since: baseline,
                                                      minimum: 1, timeout: 30)
            guard let tagged = outputs.first(where: {
                $0.lastPathComponent.hasSuffix("-metadata.png")
            }) else {
                throw HarnessFailure("expected tagged-metadata.png, got \(outputs.map(\.lastPathComponent))")
            }
            let tags = try tiffDescription(tagged)
            try require(tags.description == "Zest Harness",
                        "\(tagged.lastPathComponent) description is \(tags.description ?? "nil")")
            try require(tags.artist == "Bench",
                        "\(tagged.lastPathComponent) artist is \(tags.artist ?? "nil")")
            return "Title/Author → \(tagged.lastPathComponent) "
                + "(description \"Zest Harness\", artist \"Bench\")"

        case .collisions:
            let png = root.appendingPathComponent("dup.png")
            try makePNG(png, size: NSSize(width: 400, height: 300), color: .systemBlue)
            let source = try imageInfo(png)
            defer { try? harness.setCollisionPolicy("keepBoth") }
            try harness.setCollisionPolicy("keepBoth")
            let baseline = harness.snapshot(root)
            try harness.select(files: [png])
            try harness.dragAndChoose(trigger: .shift, expectedMode: "convert",
                                      choice: "fmt-jpg", fromIconNamed: png.lastPathComponent)
            var outputs = try harness.waitForNewFiles(in: root, since: baseline,
                                                      minimum: 1, timeout: 30)
            guard let first = outputs.first(where: { $0.lastPathComponent == "dup.jpg" }) else {
                throw HarnessFailure("expected dup.jpg, got \(outputs.map(\.lastPathComponent))")
            }
            let firstInfo = try imageInfo(first)
            try require(firstInfo.width == source.width && firstInfo.height == source.height,
                        "dup.jpg is \(firstInfo.width)×\(firstInfo.height)")
            try harness.waitForFolderIcon(named: "dup.jpg")

            try harness.dragAndChoose(trigger: .shift, expectedMode: "convert",
                                      choice: "fmt-jpg", fromIconNamed: png.lastPathComponent)
            outputs = try harness.waitForNewFiles(in: root, since: baseline,
                                                  minimum: 2, timeout: 30)
            guard let second = outputs.first(where: { $0.lastPathComponent == "dup 2.jpg" }) else {
                throw HarnessFailure("keepBoth did not make dup 2.jpg, got "
                    + "\(outputs.map(\.lastPathComponent))")
            }
            _ = try imageInfo(second)
            try harness.waitForFolderIcon(named: "dup 2.jpg")
            let firstDate = modificationDate(first)

            try harness.setCollisionPolicy("replace")
            try harness.dragAndChoose(trigger: .shift, expectedMode: "convert",
                                      choice: "fmt-jpg", fromIconNamed: png.lastPathComponent)
            try harness.waitForChange(of: first, since: firstDate, timeout: 20)
            pause(0.5)
            let jpgs = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
                .filter { $0.lowercased().hasSuffix(".jpg") }
            try require(jpgs.count == 2,
                        "replace left \(jpgs.count) JPGs: \(jpgs.sorted())")
            return "keepBoth → dup.jpg + dup 2.jpg; replace rewrote dup.jpg "
                + "(\(source.width)×\(source.height)), no third file"

        case .float:
            let one = root.appendingPathComponent("one.png")
            let two = root.appendingPathComponent("two.png")
            try makePNG(one, size: NSSize(width: 300, height: 200), color: .systemPink)
            try makePNG(two, size: NSSize(width: 300, height: 200), color: .systemBrown)
            try harness.select(files: [one, two])
            try harness.dragAndChoose(trigger: .control, expectedMode: "actions",
                                      choice: "action-float", fromIconNamed: two.lastPathComponent)
            var panel: AXUIElement?
            let appeared = waitFor(8) {
                panel = harness.panel(containing: ["Floating · 2 files",
                                                   "one.png", "two.png"])
                return panel != nil
            }
            guard appeared, let panel else {
                throw HarnessFailure("the Float panel never listed both files; windows: "
                    + "\(harness.windowTitles())")
            }
            guard let frame = axFrame(panel) else {
                throw HarnessFailure("the Float panel has no frame")
            }
            pause(0.3)
            // Rows are 62pt tall under a 42pt header; close buttons sit 21pt in.
            harness.click(CGPoint(x: frame.maxX - 21, y: frame.minY + 72))
            let rowClosed = waitFor(5) {
                harness.panel(containing: ["Floating", "one.png"]) == nil
                    && harness.panel(containing: ["two.png"]) != nil
            }
            try require(rowClosed, "closing the first row did not leave only two.png; texts: "
                + "\(harness.windowTitles())")
            harness.click(CGPoint(x: frame.maxX - 21, y: frame.minY + 21))
            let panelClosed = waitFor(5) {
                harness.panel(containing: ["Floating"]) == nil
            }
            try require(panelClosed, "the panel did not close from its header button; texts: "
                + "\(harness.windowTitles())")
            return "two files floated; row close left two.png; header close removed the panel"
        }
    }
}

// MARK: - Command line

func describe(_ error: Error) -> String {
    if let failure = error as? HarnessFailure { return failure.description }
    return error.localizedDescription
}

func locateApp() throws -> URL {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    var candidates = [cwd.appendingPathComponent("Zest.app")]
    candidates.append(exe.deletingLastPathComponent()   // harness
                       .deletingLastPathComponent()   // .build
                       .deletingLastPathComponent()   // Zest
                       .appendingPathComponent("Zest.app"))
    for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
    }
    throw HarnessFailure("Zest.app was not found; run from the Zest directory or build it first")
}

let arguments = Array(CommandLine.arguments.dropFirst())
let requested = arguments.filter { !$0.hasPrefix("-") }
let relaunch = !arguments.contains("--keep-running")
let runRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Harness/run", isDirectory: true)

let scenarios: [Scenario]
if requested.isEmpty || requested == ["all"] {
    scenarios = Scenario.allCases
} else {
    var picked: [Scenario] = []
    for name in requested {
        guard let scenario = Scenario(rawValue: name) else {
            print("Unknown scenario \(name). Choose from: \(Scenario.allCases.map(\.rawValue).joined(separator: ", ")) or all")
            exit(2)
        }
        picked.append(scenario)
    }
    scenarios = picked
}

do {
    let harness = try Harness(runRoot: runRoot, appURL: try locateApp(), relaunch: relaunch)
    print("Zest harness · app \(harness.appURL.path) · display \(Int(kMainDisplay.width))×\(Int(kMainDisplay.height))")
    var failures = 0
    for scenario in scenarios {
        do {
            let detail = try scenario.run(harness)
            print("PASS  \(scenario.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(detail)")
        } catch {
            failures += 1
            print("FAIL  \(scenario.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(describe(error))")
            print("      artifacts: \(runRoot.appendingPathComponent(scenario.rawValue).path)")
        }
        harness.cleanupAfterScenario()
    }
    print("")
    print("\(scenarios.count - failures) passed · \(failures) failed")
    exit(failures == 0 ? 0 : 1)
} catch {
    print("FAIL  harness — \(describe(error))")
    exit(1)
}
