import AppKit

// MARK: - Tool UI

enum ToolUI {
    struct Field {
        enum Kind {
            case text(String, String?)      // default, placeholder
            case popup([(String, String)], Int)
        }
        let id: String
        let label: String
        let kind: Kind
    }

    private static func form(title: String, message: String,
                             fields: [Field]) -> [String: String]? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        var controls: [String: NSControl] = [:]
        var popupValues: [String: [String]] = [:]
        var rows: [[NSView]] = []

        for field in fields {
            let label = NSTextField(labelWithString: field.label)
            label.alignment = .right
            label.font = .systemFont(ofSize: 12)
            let control: NSControl
            switch field.kind {
            case let .text(value, placeholder):
                let text = NSTextField(string: value)
                text.placeholderString = placeholder
                text.font = .systemFont(ofSize: 12)
                control = text
            case let .popup(options, selected):
                let popup = NSPopUpButton(frame: .zero, pullsDown: false)
                popup.addItems(withTitles: options.map(\.0))
                popup.selectItem(at: min(max(0, selected), max(0, options.count - 1)))
                popupValues[field.id] = options.map(\.1)
                control = popup
            }
            control.translatesAutoresizingMaskIntoConstraints = false
            control.widthAnchor.constraint(equalToConstant: 210).isActive = true
            controls[field.id] = control
            rows.append([label, control])
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.frame = NSRect(origin: .zero,
                            size: NSSize(width: 360, height: grid.fittingSize.height))
        alert.accessoryView = grid

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        var values: [String: String] = [:]
        for (id, control) in controls {
            if let popup = control as? NSPopUpButton {
                let map = popupValues[id] ?? []
                let index = popup.indexOfSelectedItem
                if index >= 0, index < map.count { values[id] = map[index] }
            } else {
                values[id] = control.stringValue
            }
        }
        return values
    }

    // MARK: Entry point

    static func collect(tool: String, inputs: [URL], kind: Kind) -> [String: String]? {
        let input = inputs[0]
        let info = MediaProbe.info(input)

        // PDF ids that collide with media tool names must win over the generic cases.
        if kind == .pdf {
            switch tool {
            case "split":
                return form(title: "Split PDF",
                            message: "Leave the ranges blank to split every page. Example: 1-3,4-6",
                            fields: [Field(id: "ranges", label: "Ranges", kind: .text("", "1-3,4-6"))])
            case "reorder":
                return form(title: "Reorganize pages",
                            message: "Enter the new order, for example 3,1,2,5-7.",
                            fields: [Field(id: "order", label: "Page order", kind: .text("", "3,1,2,5-7"))])
            case "extractImages":
                return form(title: "Extract images",
                            message: "Embedded images keep their native pixels. DPI is used only for pages with no embedded image.",
                            fields: [
                                Field(id: "dpi", label: "Fallback DPI", kind: .popup(
                                    [("150", "150"), ("300", "300"), ("600", "600")], 1)),
                                Field(id: "format", label: "Format", kind: .popup(
                                    [("PNG", "png"), ("JPG", "jpg")], 0))
                            ])
            default:
                break
            }
        }

        switch tool {
        case "compress":
            if kind == .image {
                return form(title: "Compress image",
                            message: "Leave the fields blank to use the \(Prefs.quality) preset.",
                            fields: [
                                Field(id: "percent", label: "Reduce by %", kind: .text("", "e.g. 50")),
                                Field(id: "target", label: "Target size", kind: .text("", "e.g. 2MB")),
                                Field(id: "maxDimension", label: "Max dimension", kind: .text("", "e.g. 2400"))
                            ])
            }
            return form(title: "Compress \(kind.title.lowercased())",
                        message: "Leave the fields blank to use the \(Prefs.quality) preset.",
                        fields: [
                            Field(id: "percent", label: "Reduce by %", kind: .text("", "e.g. 50")),
                            Field(id: "target", label: "Target size", kind: .text("", "e.g. 8MB"))
                        ])
        case "targetSize":
            return form(title: "Hit an exact size", message: "The encoder searches for the best quality under the target.",
                        fields: [Field(id: "target", label: "Target size", kind: .text("", "e.g. 2MB"))])
        case "resize":
            return form(title: "Resize image", message: "Leave one side at zero to keep the aspect ratio.",
                        fields: [
                            Field(id: "width", label: "Width", kind: .text("", "pixels")),
                            Field(id: "height", label: "Height", kind: .text("", "pixels")),
                            Field(id: "fit", label: "Mode", kind: .popup(
                                [("Fit inside", "fit"), ("Fill and crop", "fill"), ("Stretch", "stretch")], 0))
                        ])
        case "frame":
            return form(title: "Add background",
                        message: "Pad the photo on a coloured card. Ratios crop the canvas, never the photo.",
                        fields: [
                            Field(id: "padding", label: "Padding %", kind: .text("10", "0–30")),
                            Field(id: "ratio", label: "Canvas", kind: .popup(
                                [("Original", "original"), ("Square", "square"),
                                 ("4:3", "4:3"), ("16:9", "16:9"),
                                 ("9:16", "9:16"), ("3:2", "3:2")], 0)),
                            Field(id: "background", label: "Background", kind: .text("#FFFFFF", "#RRGGBB")),
                            Field(id: "radius", label: "Corner %", kind: .text("4", "0 = square")),
                            Field(id: "border", label: "Border px", kind: .text("0", nil)),
                            Field(id: "shadow", label: "Shadow", kind: .popup(
                                [("None", "none"), ("Soft", "soft"), ("Strong", "strong")], 0)),
                            Field(id: "format", label: "Output", kind: .popup(
                                [("PNG", "png"), ("JPG", "jpg")], 0))
                        ])
        case "crop":
            if kind == .image {
                guard let rect = cropEditor(input) else { return nil }
                return ["crop": rect]
            }
            return form(title: "Crop video",
                        message: "Source is \(info.width)×\(info.height).",
                        fields: [
                            Field(id: "width", label: "Width", kind: .text("\(info.width)", nil)),
                            Field(id: "height", label: "Height", kind: .text("\(info.height)", nil)),
                            Field(id: "x", label: "X", kind: .text("0", nil)),
                            Field(id: "y", label: "Y", kind: .text("0", nil))
                        ])
        case "rotate":
            return form(title: "Rotate",
                        message: kind == .pdf ? "Pages left blank rotate every page." : "",
                        fields: [
                            Field(id: "degrees", label: "Angle", kind: .popup(
                                [("90° right", "90"), ("180°", "180"), ("90° left", "270")], 0)),
                            Field(id: "pages", label: "PDF pages", kind: .text("", "e.g. 1-3,5"))
                        ])
        case "flip":
            return form(title: "Flip", message: "",
                        fields: [Field(id: "direction", label: "Direction", kind: .popup(
                            [("Horizontal", "horizontal"), ("Vertical", "vertical")], 0))])
        case "adjust":
            return form(title: "Adjust photo", message: "Values are relative. Contrast and saturation default to 1.0.",
                        fields: [
                            Field(id: "brightness", label: "Brightness", kind: .text("-0.05", nil)),
                            Field(id: "contrast", label: "Contrast", kind: .text("1.08", nil)),
                            Field(id: "saturation", label: "Saturation", kind: .text("1.05", nil))
                        ])
        case "grayscale", "strip", "mute", "join", "merge", "qr":
            return [:]
        case "annotate", "redact":
            guard let json = markupEditor(input, redact: tool == "redact") else { return nil }
            return ["markup": json]
        case "metadata":
            return metadataEditor(input: input, kind: kind)
        case "collage":
            return form(title: "Collage", message: "Images are arranged in reading order.",
                        fields: [
                            Field(id: "layout", label: "Layout", kind: .popup(
                                [("Grid", "grid"), ("Horizontal strip", "horizontal"),
                                 ("Vertical strip", "vertical")], 0)),
                            Field(id: "spacing", label: "Spacing", kind: .text("16", nil)),
                            Field(id: "background", label: "Background", kind: .text("#FFFFFF", nil)),
                            Field(id: "format", label: "Output", kind: .popup(
                                [("JPG", "jpg"), ("PNG", "png"), ("PDF", "pdf")], 0))
                        ])
        case "trim":
            return form(title: "Trim",
                        message: "Duration is \(String(format: "%.2f", info.duration)) s.",
                        fields: [
                            Field(id: "start", label: "Start (s)", kind: .text("0", nil)),
                            Field(id: "end", label: "End (s)", kind: .text(String(format: "%.2f", info.duration), nil))
                        ])
        case "split":
            return form(title: "Split",
                        message: "Fill either a part count or a segment length in seconds.",
                        fields: [
                            Field(id: "parts", label: "Parts", kind: .text("2", nil)),
                            Field(id: "every", label: "Every (s)", kind: .text("", nil))
                        ])
        case "speed":
            return form(title: "Change speed", message: "2 = twice as fast, 0.5 = half speed.",
                        fields: [Field(id: "factor", label: "Factor", kind: .text("1.5", nil))])
        case "snapshot":
            return form(title: "Grab a frame", message: "",
                        fields: [
                            Field(id: "time", label: "At (s)", kind: .text("0", nil)),
                            Field(id: "format", label: "Format", kind: .popup(
                                [("PNG", "png"), ("JPG", "jpg")], 0))
                        ])
        case "snapshots":
            return form(title: "Grab several frames",
                        message: "Duration is \(String(format: "%.2f", info.duration)) s. Leave times empty to space the count evenly.",
                        fields: [
                            Field(id: "times", label: "Times (s)", kind: .text("", "0,1,2")),
                            Field(id: "count", label: "Even count", kind: .text("6", nil)),
                            Field(id: "format", label: "Format", kind: .popup(
                                [("PNG", "png"), ("JPG", "jpg")], 0))
                        ])
        case "gif":
            return form(title: "Make GIF", message: "",
                        fields: [
                            Field(id: "fps", label: "Frames / s", kind: .text("12", nil)),
                            Field(id: "width", label: "Pixel width", kind: .text("720", nil))
                        ])
        case "extractAudio":
            return form(title: "Extract audio", message: "",
                        fields: [Field(id: "format", label: "Format", kind: .popup(
                            [("MP3", "mp3"), ("M4A", "m4a"), ("WAV", "wav"), ("FLAC", "flac")], 0))])
        case "normalize":
            return form(title: "Normalize volume", message: "Target loudness for podcasts is about -16 LUFS.",
                        fields: [Field(id: "lufs", label: "Loudness", kind: .text("-16", nil))])
        case "bleep":
            return form(title: "Bleep a range", message: "",
                        fields: [
                            Field(id: "start", label: "Start (s)", kind: .text("0", nil)),
                            Field(id: "end", label: "End (s)", kind: .text("1", nil))
                        ])
        case "channels":
            return form(title: "Audio channels", message: "",
                        fields: [Field(id: "mode", label: "Output", kind: .popup(
                            [("Mono", "mono"), ("Stereo", "stereo")], 0))])
        case "sampleRate":
            return form(title: "Sample rate", message: "",
                        fields: [Field(id: "rate", label: "Rate", kind: .popup(
                            [("44.1 kHz", "44100"), ("48 kHz", "48000"),
                             ("22.05 kHz", "22050"), ("96 kHz", "96000")], 0))])
        case "redactVideo":
            guard let frame = videoFrame(input, info: info),
                  let box = rectEditor(image: frame,
                                       title: "Redact \(input.lastPathComponent)",
                                       actionTitle: "Redact") else { return nil }
            let parts = box.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 4 else { return nil }
            let pixels = CGRect(x: parts[0] * Double(info.width),
                                y: parts[1] * Double(info.height),
                                width: parts[2] * Double(info.width),
                                height: parts[3] * Double(info.height))
            guard let values = form(
                title: "Redact region",
                message: "The box covers \(Int(pixels.width))×\(Int(pixels.height)) px. Pick the time range and the treatment.",
                fields: [
                    Field(id: "start", label: "From (s)", kind: .text("0", nil)),
                    Field(id: "end", label: "To (s)",
                          kind: .text(String(format: "%.2f", info.duration), nil)),
                    Field(id: "mode", label: "Treatment", kind: .popup(
                        [("Blur", "blur"), ("Pixelate", "pixelate"), ("Black box", "box")], 0))
                ]) else { return nil }
            var params = values
            params["x"] = "\(Int(pixels.minX.rounded()))"
            params["y"] = "\(Int(pixels.minY.rounded()))"
            params["w"] = "\(Int(pixels.width.rounded()))"
            params["h"] = "\(Int(pixels.height.rounded()))"
            return params
        case "redactAudio":
            return form(title: "Redact audio",
                        message: "Duration is \(String(format: "%.2f", info.duration)) s. A tone keeps the rhythm; silence removes it.",
                        fields: [
                            Field(id: "start", label: "From (s)", kind: .text("0", nil)),
                            Field(id: "end", label: "To (s)", kind: .text("1", nil)),
                            Field(id: "mode", label: "Replace with", kind: .popup(
                                [("Tone", "tone"), ("Silence", "silence")], 0)),
                            Field(id: "frequency", label: "Tone (Hz)", kind: .text("1000", nil))
                        ])
        case "audioToVideo":
            guard var values = form(
                title: "Audio to video",
                message: "Pairs the track with a still image, or a solid colour when the path is blank.",
                fields: [
                    Field(id: "background", label: "Image path", kind: .text("", "optional, e.g. ~/cover.jpg")),
                    Field(id: "color", label: "Background", kind: .text("#1C1C1E", "#RRGGBB")),
                    Field(id: "size", label: "Frame", kind: .popup(
                        [("1080p", "1920x1080"), ("720p", "1280x720"),
                         ("Square", "1080x1080"), ("Vertical", "1080x1920")], 0))
                ]) else { return nil }
            let size = (values["size"] ?? "1920x1080").split(separator: "x")
            values["width"] = size.first.map(String.init) ?? "1920"
            values["height"] = size.count > 1 ? String(size[1]) : "1080"
            return values
        case "reorder":
            return form(title: "Reorganize pages",
                        message: "Enter the new order, for example 3,1,2,5-7.",
                        fields: [Field(id: "order", label: "Page order", kind: .text("", "3,1,2,5-7"))])
        default:
            break
        }

        if kind == .subtitle {
            switch tool {
            case "shift":
                return form(title: "Shift subtitles",
                            message: "Positive moves later, negative moves earlier.",
                            fields: [Field(id: "seconds", label: "Seconds", kind: .text("0.5", nil))])
            default:
                break
            }
        }

        return [:]
    }

    // MARK: Crop editor

    static func cropEditor(_ input: URL) -> String? {
        guard let image = try? ImageEngine.load(input) else {
            Alert.show("Can't open image", detail: input.lastPathComponent)
            return nil
        }
        return rectEditor(image: image,
                          title: "Crop \(input.lastPathComponent)",
                          actionTitle: "Crop")
    }

    /// Shared rectangle picker: returns a normalized `x,y,w,h` string with a
    /// top-left origin. Used by Crop and by the video redaction tool.
    static func rectEditor(image: CGImage, title: String, actionTitle: String) -> String? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.center()

        let canvas = CropCanvas(image: image)
        canvas.frame = NSRect(x: 0, y: 58, width: 860, height: 582)
        window.contentView?.addSubview(canvas)

        var result: String?
        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        let apply = NSButton(title: actionTitle, target: nil, action: nil)
        apply.keyEquivalent = "\r"
        cancel.keyEquivalent = "\u{1b}"
        apply.isEnabled = false
        let bar = NSStackView(views: [NSTextField(labelWithString: "Drag a rectangle on the image."),
                                      NSView(), cancel, apply])
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        bar.frame = NSRect(x: 0, y: 0, width: 860, height: 58)
        bar.autoresizingMask = [.width, .maxYMargin]
        window.contentView?.addSubview(bar)

        let closer = ModalCloser()
        window.delegate = closer
        // Use a plain modal loop for simplicity.
        final class Actions: NSObject {
            var apply: (() -> Void)?
            var cancel: (() -> Void)?
            @objc func doApply() { apply?() }
            @objc func doCancel() { cancel?() }
        }
        let actions = Actions()
        actions.apply = {
            let sel = canvas.selection.intersection(canvas.imageRect)
            guard sel.width > 2, sel.height > 2 else { return }
            let x = (sel.minX - canvas.imageRect.minX) / canvas.imageRect.width
            let y = (canvas.imageRect.maxY - sel.maxY) / canvas.imageRect.height
            let w = sel.width / canvas.imageRect.width
            let h = sel.height / canvas.imageRect.height
            result = String(format: "%.5f,%.5f,%.5f,%.5f", x, y, w, h)
            NSApp.stopModal(withCode: .OK)
        }
        actions.cancel = {
            NSApp.stopModal(withCode: .cancel)
        }
        apply.target = actions
        apply.action = #selector(Actions.doApply)
        cancel.target = actions
        cancel.action = #selector(Actions.doCancel)
        canvas.onChange = { apply.isEnabled = canvas.selection.width > 2 }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: window)
        window.orderOut(nil)
        return response == .OK ? result : nil
    }

    // MARK: Video frame

    /// Grabs a representative frame so the redaction box can be dragged on
    /// real pixels instead of typed coordinates.
    private static func videoFrame(_ input: URL, info: MediaProbe.Info) -> CGImage? {
        let frameURL = Temp.dir(prefix: "zest-redact")
            .appendingPathComponent("frame.png")
        let time = info.duration > 0 ? min(1.0, info.duration / 2) : 0
        do {
            try MediaEngine.snapshot(input, at: time, to: frameURL)
            return try ImageEngine.load(frameURL)
        } catch {
            Alert.show("Can't read a frame", detail: error.localizedDescription)
            return nil
        }
    }

    // MARK: Markup editor

    static func markupEditor(_ input: URL, redact: Bool) -> String? {
        guard let image = try? ImageEngine.load(input) else {
            Alert.show("Can't open image", detail: input.lastPathComponent)
            return nil
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = (redact ? "Redact " : "Annotate ") + input.lastPathComponent
        window.center()

        let canvas = MarkupCanvas(image: image, redact: redact)
        canvas.frame = NSRect(x: 0, y: 52, width: 920, height: 668)
        window.contentView?.addSubview(canvas)
        let closer = ModalCloser()
        window.delegate = closer

        let toolPicker = NSSegmentedControl(labels: redact ? ["Box"] : ["Box", "Pen", "Arrow", "Text"],
                                            trackingMode: .selectOne,
                                            target: canvas, action: #selector(MarkupCanvas.toolChanged(_:)))
        toolPicker.selectedSegment = 0
        if redact { toolPicker.isEnabled = false }

        let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 24))
        colorWell.color = redact ? .black : .systemRed
        colorWell.target = canvas
        colorWell.action = #selector(MarkupCanvas.colorChanged(_:))
        colorWell.isEnabled = !redact

        let textField = NSTextField(string: "Text")
        textField.widthAnchor.constraint(equalToConstant: 110).isActive = true
        textField.target = canvas
        textField.action = #selector(MarkupCanvas.textChanged(_:))

        let undo = NSButton(title: "Undo", target: canvas, action: #selector(MarkupCanvas.undo))
        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        cancel.keyEquivalent = "\u{1b}"
        let done = NSButton(title: redact ? "Redact" : "Save", target: nil, action: nil)
        done.keyEquivalent = "\r"

        let bar = NSStackView(views: [toolPicker, colorWell, textField, undo, NSView(), cancel, done])
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        bar.frame = NSRect(x: 0, y: 0, width: 920, height: 52)
        bar.autoresizingMask = [.width, .maxYMargin]
        window.contentView?.addSubview(bar)

        final class Actions: NSObject {
            var save: (() -> Void)?
            var cancel: (() -> Void)?
            @objc func doSave() { save?() }
            @objc func doCancel() { cancel?() }
        }
        let actions = Actions()
        var result: String?
        actions.save = {
            result = canvas.json()
            NSApp.stopModal(withCode: .OK)
        }
        actions.cancel = { NSApp.stopModal(withCode: .cancel) }
        done.target = actions
        done.action = #selector(Actions.doSave)
        cancel.target = actions
        cancel.action = #selector(Actions.doCancel)
        canvas.textValue = textField.stringValue

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: window)
        window.orderOut(nil)
        return response == .OK ? result : nil
    }

    // MARK: Metadata

    static func metadataEditor(input: URL, kind: Kind) -> [String: String]? {
        let editable = [.image, .pdf, .video, .audio].contains(kind)
        var pairs: [(String, String)] = []
        switch kind {
        case .image: pairs = ToolRunner.imageMetadata(input)
        case .pdf: pairs = PDFEngine.metadata(input)
        case .video, .audio: pairs = MediaEngine.metadata(input)
        case .document, .slides, .sheet: pairs = ToolRunner.officeMetadata(input)
        default: pairs = [("File size", Bytes.format(input.fileSize))]
        }

        let alert = NSAlert()
        alert.messageText = "Metadata"
        alert.informativeText = editable
            ? input.lastPathComponent
            : "\(input.lastPathComponent) — read-only; the only available change is removal."
        alert.addButton(withTitle: editable ? "Save" : "Remove Metadata")
        if editable { alert.addButton(withTitle: "Remove Metadata") }
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 290))
        var controls: [String: NSTextField] = [:]
        if editable {
            let keys = ["Title", "Author", "Subject", "Keywords", "Description", "Copyright"]
            var rows: [[NSView]] = []
            for key in keys {
                let label = NSTextField(labelWithString: key)
                label.alignment = .right
                label.font = .systemFont(ofSize: 12)
                let field = NSTextField(string: "")
                field.placeholderString = "leave blank to keep"
                field.font = .systemFont(ofSize: 12)
                field.widthAnchor.constraint(equalToConstant: 260).isActive = true
                controls[key] = field
                rows.append([label, field])
            }
            let grid = NSGridView(views: rows)
            grid.rowSpacing = 7
            grid.columnSpacing = 10
            grid.column(at: 0).xPlacement = .trailing
            grid.frame = NSRect(origin: .zero, size: NSSize(width: 380, height: grid.fittingSize.height))
            container.addSubview(grid)

            let info = NSTextView(frame: NSRect(x: 0, y: grid.fittingSize.height + 10,
                                                 width: 440, height: 110))
            info.isEditable = false
            info.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            info.string = pairs.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
            container.addSubview(info)
        } else {
            let scroll = NSScrollView(frame: container.bounds)
            scroll.hasVerticalScroller = true
            let text = NSTextView(frame: scroll.bounds)
            text.isEditable = false
            text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.string = pairs.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
            scroll.documentView = text
            container.addSubview(scroll)
        }
        alert.accessoryView = container

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if !editable { return ["remove": "1"] }
            var values: [String: String] = [:]
            for (key, field) in controls where !field.stringValue.isEmpty {
                values[key] = field.stringValue
            }
            guard !values.isEmpty else { return nil }
            return ["values": ToolRunner.encodeValues(values)]
        }
        if editable, response == .alertSecondButtonReturn {
            return ["remove": "1"]
        }
        return nil
    }

    // MARK: QR

    static func showQR(_ codes: [String], title: String) {
        let alert = NSAlert()
        alert.messageText = codes.isEmpty ? "No codes found" : "\(codes.count) code\(codes.count == 1 ? "" : "s") found"
        alert.informativeText = title
        if codes.isEmpty {
            alert.addButton(withTitle: "OK")
        } else {
            alert.addButton(withTitle: "Copy All")
            alert.addButton(withTitle: "Close")
            let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 140))
            text.isEditable = false
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.string = codes.joined(separator: "\n\n")
            alert.accessoryView = text
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if !codes.isEmpty, response == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(codes.joined(separator: "\n"), forType: .string)
        }
    }
}

// MARK: - Crop canvas

final class CropCanvas: NSView {
    let image: CGImage
    var imageRect: CGRect = .zero
    var selection: CGRect = .zero
    var onChange: (() -> Void)?
    private var dragStart: CGPoint?

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()

        let scale = min(bounds.width / CGFloat(image.width),
                        bounds.height / CGFloat(image.height))
        let w = CGFloat(image.width) * scale
        let h = CGFloat(image.height) * scale
        imageRect = CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2,
                           width: w, height: h)
        NSImage(cgImage: image, size: imageRect.size).draw(in: imageRect)

        if selection.width > 0 {
            let dim = NSBezierPath(rect: bounds)
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
            NSColor(calibratedWhite: 0, alpha: 0.55).setFill()
            dim.fill()

            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1.5
            border.stroke()
            NSColor.controlAccentColor.setStroke()
            let corners = NSBezierPath(rect: selection.insetBy(dx: 1, dy: 1))
            corners.lineWidth = 1
            corners.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }
        dragStart = point
        selection = .zero
        onChange?()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let w = abs(current.x - start.x)
        let h = abs(current.y - start.y)
        selection = CGRect(x: x, y: y, width: w, height: h).intersection(imageRect)
        onChange?()
        needsDisplay = true
    }
}

// MARK: - Markup canvas

final class MarkupCanvas: NSView {
    private let image: CGImage
    private let redact: Bool
    private var ops: [[String: Any]] = []
    private var draft: [String: Any]?
    private var startPoint: CGPoint?
    private var previewRect: CGRect = .zero
    private var tool = 0
    private var color: NSColor
    var textValue = "Text"

    init(image: CGImage, redact: Bool) {
        self.image = image
        self.redact = redact
        self.color = redact ? .black : .systemRed
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    private var imageRect: CGRect {
        let scale = min(bounds.width / CGFloat(image.width),
                        bounds.height / CGFloat(image.height))
        let w = CGFloat(image.width) * scale
        let h = CGFloat(image.height) * scale
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2,
                      width: w, height: h)
    }

    private func normalized(_ point: CGPoint) -> [Double] {
        let rect = imageRect
        let x = (point.x - rect.minX) / rect.width
        let y = (rect.maxY - point.y) / rect.height
        return [Double(min(1, max(0, x))), Double(min(1, max(0, y)))]
    }

    private func viewPoint(_ normalized: [Double]) -> CGPoint {
        let rect = imageRect
        return CGPoint(x: rect.minX + CGFloat(normalized[0]) * rect.width,
                       y: rect.maxY - CGFloat(normalized[1]) * rect.height)
    }

    private func colorArray() -> [Double] {
        let c = color.usingColorSpace(.sRGB) ?? .red
        return [Double(c.redComponent), Double(c.greenComponent),
                Double(c.blueComponent), Double(c.alphaComponent)]
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()
        let rect = imageRect
        NSImage(cgImage: image, size: rect.size).draw(in: rect)

        var all = ops
        if let draft { all.append(draft) }
        for op in all { draw(op: op, in: rect) }
    }

    private func draw(op: [String: Any], in rect: CGRect) {
        let kind = op["t"] as? String ?? ""
        let c = op["color"] as? [Double] ?? [1, 0, 0, 1]
        let nsColor = NSColor(srgbRed: CGFloat(c[0]), green: CGFloat(c[1]),
                              blue: CGFloat(c[2]), alpha: CGFloat(c[3]))
        let lineWidth = max(1, CGFloat(op["width"] as? Double ?? 0.004) * rect.width)

        switch kind {
        case "rect":
            guard let values = op["rect"] as? [Double], values.count == 4 else { return }
            let p0 = viewPoint([values[0], values[1]])
            let p1 = viewPoint([values[0] + values[2], values[1] + values[3]])
            let r = CGRect(x: min(p0.x, p1.x), y: min(p0.y, p1.y),
                           width: abs(p1.x - p0.x), height: abs(p1.y - p0.y))
            let path = NSBezierPath(rect: r)
            if op["fill"] as? Bool == true {
                nsColor.setFill()
                path.fill()
            }
            nsColor.setStroke()
            path.lineWidth = lineWidth
            path.stroke()
        case "pen":
            guard let points = op["points"] as? [[Double]], points.count > 1 else { return }
            let path = NSBezierPath()
            path.move(to: viewPoint(points[0]))
            for p in points.dropFirst() { path.line(to: viewPoint(p)) }
            nsColor.setStroke()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.stroke()
        case "arrow":
            guard let a = op["from"] as? [Double], let b = op["to"] as? [Double] else { return }
            let p0 = viewPoint(a), p1 = viewPoint(b)
            let path = NSBezierPath()
            path.move(to: p0)
            path.line(to: p1)
            nsColor.setStroke()
            path.lineWidth = lineWidth
            path.stroke()
            let angle = atan2(p1.y - p0.y, p1.x - p0.x)
            let head = max(10, lineWidth * 4)
            let left = CGPoint(x: p1.x - cos(angle - .pi / 7) * head,
                               y: p1.y - sin(angle - .pi / 7) * head)
            let right = CGPoint(x: p1.x - cos(angle + .pi / 7) * head,
                                y: p1.y - sin(angle + .pi / 7) * head)
            let headPath = NSBezierPath()
            headPath.move(to: p1)
            headPath.line(to: left)
            headPath.line(to: right)
            headPath.close()
            nsColor.setFill()
            headPath.fill()
        case "text":
            guard let text = op["text"] as? String, let at = op["at"] as? [Double] else { return }
            let size = max(10, CGFloat(op["size"] as? Double ?? 0.035) * rect.width)
            let p = viewPoint(at)
            (text as NSString).draw(at: CGPoint(x: p.x, y: p.y - size * 0.85),
                                    withAttributes: [
                                        .font: NSFont.boldSystemFont(ofSize: size),
                                        .foregroundColor: nsColor
                                    ])
        default: break
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }
        startPoint = point
        let n = normalized(point)

        if tool == 3 { // text
            ops.append(["t": "text", "text": textValue, "at": n,
                        "size": 0.035, "color": colorArray()])
            needsDisplay = true
            return
        }

        if tool == 1 { // pen
            draft = ["t": "pen", "points": [n], "color": colorArray(), "width": 0.004]
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        let a = normalized(start)
        let b = normalized(point)

        switch tool {
        case 0:
            let x = min(a[0], b[0])
            let y = min(a[1], b[1])
            draft = ["t": "rect", "rect": [x, y, abs(b[0] - a[0]), abs(b[1] - a[1])],
                     "color": redact ? [0, 0, 0, 1] : colorArray(),
                     "width": 0.004, "fill": redact]
        case 1:
            if var points = draft?["points"] as? [[Double]] {
                points.append(b)
                draft?["points"] = points
            }
        case 2:
            draft = ["t": "arrow", "from": a, "to": b,
                     "color": colorArray(), "width": 0.005]
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let draft {
            if let points = draft["points"] as? [[Double]], points.count < 2 {
                self.draft = nil
            } else {
                ops.append(draft)
                self.draft = nil
            }
        }
        startPoint = nil
        needsDisplay = true
    }

    @objc func toolChanged(_ sender: NSSegmentedControl) {
        tool = sender.selectedSegment
    }

    @objc func colorChanged(_ sender: NSColorWell) {
        color = sender.color
    }

    @objc func textChanged(_ sender: NSTextField) {
        textValue = sender.stringValue.isEmpty ? "Text" : sender.stringValue
    }

    @objc func undo() {
        if !ops.isEmpty { ops.removeLast(); needsDisplay = true }
    }

    func json() -> String {
        let doc: [String: Any] = ["ops": ops]
        guard let data = try? JSONSerialization.data(withJSONObject: doc),
              let text = String(data: data, encoding: .utf8) else { return "{\"ops\":[]}" }
        return text
    }
}

// MARK: - Modal window closer

/// Stops the modal loop if the user closes a tool window with the title-bar button.
private final class ModalCloser: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal(withCode: .cancel)
    }
}
