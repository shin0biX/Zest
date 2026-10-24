import AppKit
import PDFKit

// MARK: - Documents

enum DocEngine {
    static func convert(_ input: URL, to fmt: Fmt, params: [String: String] = [:]) throws -> [URL] {
        let ext = input.pathExtension.lowercased()
        let kind = KindDetector.kind(of: input)

        if kind == .slides || ["ppt", "pptx", "key", "odp"].contains(ext) {
            return try convertSlides(input, to: fmt)
        }

        if ext == "pages" {
            let pdf = try pagesToPDF(input)
            if fmt.ext == "pdf" { return [pdf] }
            return try PDFEngine.convert(pdf, to: fmt)
        }

        if ext == "epub" {
            let text = try epubText(input)
            return try writeTextOutputs(text: text, input: input, to: fmt)
        }

        switch fmt.ext.lowercased() {
        case "txt":
            let out = Naming.output(for: input, ext: "txt")
            try TextTools.plainText(from: input).write(to: out, atomically: true, encoding: .utf8)
            return [out]
        case "md":
            let out = Naming.output(for: input, ext: "md")
            let text = try TextTools.plainText(from: input)
            let title = input.deletingPathExtension().lastPathComponent
            try ("# \(title)\n\n" + text).write(to: out, atomically: true, encoding: .utf8)
            return [out]
        case "pdf":
            let out = Naming.output(for: input, ext: "pdf")
            // "Flowing text" drops the source styling; "editable paragraphs"
            // keeps the rich runs that textutil hands back.
            let body: NSAttributedString
            if params["pdfLayout"] == "flowing" {
                body = TextTools.attributed(try TextTools.plainText(from: input))
            } else {
                body = try TextTools.attributedDocument(input)
            }
            try TextTools.pdf(from: body, to: out)
            return [out]
        case "docx":
            let out = Naming.output(for: input, ext: "docx")
            let text = try TextTools.plainText(from: input)
            try DocxWriter.write(paragraphs: text.components(separatedBy: "\n"),
                                 title: input.deletingPathExtension().lastPathComponent,
                                 to: out)
            return [out]
        case "rtf":
            let out = Naming.output(for: input, ext: "rtf")
            let text = try TextTools.plainText(from: input)
            try TextTools.writeRTF(text: text, to: out)
            return [out]
        case "html":
            let out = Naming.output(for: input, ext: "html")
            let text = try TextTools.plainText(from: input)
            let isMarkdown = ext == "md" || ext == "markdown"
            let body = isMarkdown
                ? TextTools.markdownToHTML(try String(contentsOf: input, encoding: .utf8))
                : "<p>" + TextTools.escapeXML(text).replacingOccurrences(of: "\n", with: "</p><p>") + "</p>"
            let html = """
            <!doctype html><html><head><meta charset="utf-8"><title>\(TextTools.escapeXML(input.deletingPathExtension().lastPathComponent))</title>
            <style>body{font:15px -apple-system,Helvetica,sans-serif;line-height:1.55;max-width:760px;margin:48px auto;padding:0 20px;color:#111}</style></head>
            <body>\(body)</body></html>
            """
            try html.write(to: out, atomically: true, encoding: .utf8)
            return [out]
        case "epub":
            let out = Naming.output(for: input, ext: "epub")
            let title = input.deletingPathExtension().lastPathComponent
            if params["epubLayout"] == "fixed" {
                // Paginate first, then keep those pages as images.
                let pdf = Temp.dir(prefix: "zest-epub").appendingPathComponent("doc.pdf")
                try TextTools.pdf(from: try TextTools.attributedDocument(input), to: pdf)
                guard let doc = PDFDocument(url: pdf) else {
                    throw ZestError("Couldn't paginate \(input.lastPathComponent)")
                }
                try PDFEngine.writeFixedEPUB(doc, input: input, to: out)
            } else {
                let text = try TextTools.plainText(from: input)
                try EpubWriter.write(title: title, pages: [text], to: out)
            }
            return [out]
        case "pages":
            return try pagesOutput(input, to: fmt)
        default:
            throw ZestError("No document converter for .\(fmt.ext)")
        }
    }

    private static func writeTextOutputs(text: String, input: URL, to fmt: Fmt) throws -> [URL] {
        switch fmt.ext.lowercased() {
        case "txt", "md":
            let out = Naming.output(for: input, ext: fmt.ext)
            try text.write(to: out, atomically: true, encoding: .utf8)
            return [out]
        case "pdf":
            let out = Naming.output(for: input, ext: "pdf")
            try TextTools.pdf(from: text, to: out)
            return [out]
        case "docx":
            let out = Naming.output(for: input, ext: "docx")
            try DocxWriter.write(paragraphs: text.components(separatedBy: "\n"),
                                 title: input.deletingPathExtension().lastPathComponent, to: out)
            return [out]
        case "epub":
            let out = Naming.output(for: input, ext: "epub")
            try EpubWriter.write(title: input.deletingPathExtension().lastPathComponent,
                                 pages: [text], to: out)
            return [out]
        default:
            throw ZestError("No converter for EPUB → .\(fmt.ext)")
        }
    }

    static func epubText(_ input: URL) throws -> String {
        let dir = Temp.dir()
        try ZipUtil.unzip(input, to: dir)
        var files: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: dir,
                                                           includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                if ["xhtml", "html", "htm"].contains(url.pathExtension.lowercased()) {
                    files.append(url)
                }
            }
        }
        let text = files.sorted { $0.path < $1.path }.compactMap { url -> String? in
            guard let html = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return TextTools.stripHTML(html)
        }.joined(separator: "\n\n")
        guard !text.trimmed().isEmpty else { throw ZestError("No text found in EPUB") }
        return text
    }

    // MARK: Slides

    private static func convertSlides(_ input: URL, to fmt: Fmt) throws -> [URL] {
        guard let soffice = ToolFinder.soffice else {
            throw ZestError("Slides need LibreOffice. Install it with: brew install --cask libreoffice")
        }
        let dir = Temp.dir()
        try Shell.run(soffice, ["--headless", "--convert-to", "pdf",
                                "--outdir", dir.path, input.path])
        let pdf = dir.appendingPathComponent(
            input.deletingPathExtension().lastPathComponent + ".pdf")
        guard FileManager.default.fileExists(atPath: pdf.path) else {
            throw ZestError("LibreOffice couldn't open \(input.lastPathComponent)")
        }
        if fmt.ext == "pdf" {
            let out = Naming.output(for: input, ext: "pdf")
            try? FileManager.default.removeItem(at: out)
            try FileManager.default.moveItem(at: pdf, to: out)
            return [out]
        }
        return try PDFEngine.convert(pdf, to: fmt)
    }

    // MARK: Pages

    private static func pagesToPDF(_ input: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: "/Applications/Pages.app") else {
            throw ZestError("Pages isn't installed")
        }
        let out = Temp.dir().appendingPathComponent("export.pdf")
        let script = """
        tell application "Pages"
            set d to open POSIX file "\(appleEscape(input.path))"
            export d to POSIX file "\(appleEscape(out.path))" as PDF
            close d saving no
        end tell
        """
        try Shell.run("/usr/bin/osascript", ["-e", script])
        return out
    }

    private static func pagesOutput(_ input: URL, to fmt: Fmt) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: "/Applications/Pages.app") else {
            throw ZestError("Pages output needs Pages installed")
        }
        let out = Naming.output(for: input, ext: "pages")
        var source = input
        if input.pathExtension.lowercased() != "docx" && input.pathExtension.lowercased() != "rtf" {
            let docx = try Shell.run("/usr/bin/textutil",
                                     ["-convert", "docx", "-output",
                                      Temp.dir().appendingPathComponent("in.docx").path,
                                      input.path])
            source = URL(fileURLWithPath: docx.trimmed())
        }
        let script = """
        tell application "Pages"
            set d to open POSIX file "\(appleEscape(source.path))"
            save d in POSIX file "\(appleEscape(out.path))"
            close d saving no
        end tell
        """
        try Shell.run("/usr/bin/osascript", ["-e", script])
        return [out]
    }

    private static func appleEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - Spreadsheets

enum SheetEngine {
    static func convert(_ input: URL, to fmt: Fmt, params: [String: String] = [:]) throws -> [URL] {
        let rows = try SheetReader.rows(input)
        guard !rows.isEmpty else { throw ZestError("The sheet is empty") }

        switch fmt.ext.lowercased() {
        case "csv":
            let out = Naming.output(for: input, ext: "csv")
            try SheetReader.encode(rows, separator: ",").write(to: out, atomically: true, encoding: .utf8)
            return [out]
        case "tsv":
            let out = Naming.output(for: input, ext: "tsv")
            try SheetReader.encode(rows, separator: "\t").write(to: out, atomically: true, encoding: .utf8)
            return [out]
        case "xlsx":
            let out = Naming.output(for: input, ext: "xlsx")
            try XlsxWriter.write(rows: rows,
                                 sheetName: input.deletingPathExtension().lastPathComponent,
                                 to: out)
            return [out]
        case "ods":
            let out = Naming.output(for: input, ext: "ods")
            try OdsWriter.write(rows: rows, to: out)
            return [out]
        case "pdf":
            let out = Naming.output(for: input, ext: "pdf")
            try TextTools.pdf(from: tableText(rows), to: out,
                              pageSize: CGSize(width: 792, height: 612), margin: 36)
            return [out]
        default:
            throw ZestError("No spreadsheet converter for .\(fmt.ext)")
        }
    }

    static func tableText(_ rows: [[String]]) -> NSAttributedString {
        let columns = rows.map(\.count).max() ?? 0
        var widths = Array(repeating: 0, count: columns)
        for row in rows {
            for (i, cell) in row.enumerated() {
                widths[i] = max(widths[i], min(48, cell.count))
            }
        }
        let font = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 1.5
        let output = NSMutableAttributedString()
        for (index, row) in rows.enumerated() {
            var line = ""
            for i in 0..<columns {
                let cell = i < row.count ? row[i] : ""
                let truncated = cell.count > widths[i] ? String(cell.prefix(widths[i] - 1)) + "…" : cell
                line += truncated.padding(toLength: max(widths[i], truncated.count) + 2,
                                          withPad: " ", startingAt: 0)
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: index == 0 ? NSFont.monospacedSystemFont(ofSize: 9, weight: .bold) : font,
                .paragraphStyle: para,
                .foregroundColor: NSColor.black
            ]
            output.append(NSAttributedString(string: line + "\n", attributes: attrs))
        }
        return output
    }
}
