import AppKit

// MARK: - Subtitles

struct SubtitleCue {
    var start: Double
    var end: Double
    var text: String
}

enum SubtitleEngine {
    static func convert(_ input: URL, to fmt: Fmt, params: [String: String] = [:]) throws -> [URL] {
        let cues = try parse(input)
        switch fmt.ext.lowercased() {
        case "srt":
            let out = Naming.output(for: input, ext: "srt")
            try writeSRT(cues, to: out)
            return [out]
        case "vtt":
            let out = Naming.output(for: input, ext: "vtt")
            try writeVTT(cues, to: out)
            return [out]
        case "txt":
            let out = Naming.output(for: input, ext: "txt")
            let text = cues.map(\.text).joined(separator: "\n")
            try text.write(to: out, atomically: true, encoding: .utf8)
            return [out]
        default:
            throw ZestError("No subtitle converter for .\(fmt.ext)")
        }
    }

    static func parse(_ url: URL) throws -> [SubtitleCue] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let isVTT = url.pathExtension.lowercased() == "vtt"
            || normalized.hasPrefix("WEBVTT")

        var cues: [SubtitleCue] = []
        let blocks = normalized.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
                .map { $0.trimmed() }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }
            if lines[0].hasPrefix("WEBVTT") || lines[0].hasPrefix("NOTE") { continue }

            var timeIndex = 0
            if !lines[0].contains("-->"), lines.count > 1 {
                timeIndex = 1
            }
            guard timeIndex < lines.count, lines[timeIndex].contains("-->") else { continue }
            let parts = lines[timeIndex].components(separatedBy: "-->")
            guard parts.count == 2 else { continue }

            guard let start = parseTime(parts[0]), let end = parseTime(parts[1]) else { continue }
            let text = lines.dropFirst(timeIndex + 1).joined(separator: "\n")
            cues.append(SubtitleCue(start: start, end: end, text: text))
        }
        if cues.isEmpty {
            // Loose parsing fallback: scan for timestamp lines.
            let lines = normalized.components(separatedBy: "\n")
            var index = 0
            while index < lines.count {
                if lines[index].contains("-->") {
                    let parts = lines[index].components(separatedBy: "-->")
                    if parts.count == 2, let start = parseTime(parts[0]), let end = parseTime(parts[1]) {
                        var textLines: [String] = []
                        var j = index + 1
                        while j < lines.count, !lines[j].trimmed().isEmpty {
                            if lines[j].contains("-->") { break }
                            textLines.append(lines[j])
                            j += 1
                        }
                        cues.append(SubtitleCue(start: start, end: end,
                                                text: textLines.joined(separator: "\n")))
                        index = j
                        continue
                    }
                }
                index += 1
            }
        }
        guard !cues.isEmpty else { throw ZestError("No subtitle cues found") }
        _ = isVTT
        return cues
    }

    static func parseTime(_ text: String) -> Double? {
        let cleaned = text.trimmed()
            .replacingOccurrences(of: ",", with: ".")
            .components(separatedBy: " ").first ?? ""
        let parts = cleaned.components(separatedBy: ":")
        var seconds = 0.0
        for (index, part) in parts.enumerated() {
            guard let value = Double(part) else { return nil }
            seconds = seconds * 60 + value
            if index == parts.count - 2 { break }
        }
        return seconds
    }

    static func formatTime(_ seconds: Double, vtt: Bool) -> String {
        let clamped = max(0, seconds)
        let h = Int(clamped) / 3600
        let m = (Int(clamped) % 3600) / 60
        let s = Int(clamped) % 60
        let ms = Int((clamped - floor(clamped)) * 1000)
        let separator = vtt ? "." : ","
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, separator, ms)
    }

    static func writeSRT(_ cues: [SubtitleCue], to url: URL) throws {
        var text = ""
        for (index, cue) in cues.enumerated() {
            text += "\(index + 1)\n\(formatTime(cue.start, vtt: false)) --> \(formatTime(cue.end, vtt: false))\n\(cue.text)\n\n"
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeVTT(_ cues: [SubtitleCue], to url: URL) throws {
        var text = "WEBVTT\n\n"
        for cue in cues {
            text += "\(formatTime(cue.start, vtt: true)) --> \(formatTime(cue.end, vtt: true))\n\(cue.text)\n\n"
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Tools

    static func shift(_ input: URL, seconds: Double) throws -> [URL] {
        var cues = try parse(input)
        for index in cues.indices {
            cues[index].start = max(0, cues[index].start + seconds)
            cues[index].end = max(0, cues[index].end + seconds)
        }
        let ext = input.pathExtension.lowercased() == "vtt" ? "vtt" : "srt"
        let out = Naming.output(for: input, ext: ext, suffix: "shifted")
        if ext == "vtt" { try writeVTT(cues, to: out) } else { try writeSRT(cues, to: out) }
        return [out]
    }

    static func merge(_ inputs: [URL], to out: URL) throws {
        var all: [SubtitleCue] = []
        for url in inputs { all.append(contentsOf: try parse(url)) }
        all.sort { $0.start < $1.start }
        try writeSRT(all, to: out)
        return
    }
}

// MARK: - Archives

enum ArchiveEngine {
    static func convert(_ input: URL, to fmt: Fmt, params: [String: String] = [:]) throws -> [URL] {
        if input.isDirectory {
            return [try create(urls: [input], ext: fmt.ext)]
        }
        let extracted = try extract(input)
        var out = Naming.output(for: input, ext: fmt.ext)
        if out.standardizedFileURL == input.standardizedFileURL {
            out = Naming.output(for: input, ext: fmt.ext, suffix: "converted")
        }
        return [try create(urls: [extracted], ext: fmt.ext, to: out)]
    }

    static func create(urls: [URL], ext: String, baseName: String? = nil,
                       to explicit: URL? = nil) throws -> URL {
        guard !urls.isEmpty else { throw ZestError("Nothing to archive") }
        let out: URL
        if let explicit {
            out = explicit
        } else if let baseName {
            out = urls[0].deletingLastPathComponent()
                .appendingPathComponent(baseName + "." + ext)
        } else {
            out = Naming.batchOutput(for: urls, ext: ext)
        }
        try? FileManager.default.removeItem(at: out)

        switch ext.lowercased() {
        case "zip":
            try makeZip(urls, out: out)
        case "tar":
            let parent = urls[0].deletingLastPathComponent()
            let names = urls.map(\.lastPathComponent)
            try Shell.run("/usr/bin/tar", ["-cf", out.path] + names, cwd: parent)
        case "gz":
            if urls.count == 1 && !urls[0].isDirectory {
                try Shell.run("/bin/sh", ["-c",
                    "gzip -c \(shellQuote(urls[0].path)) > \(shellQuote(out.path))"])
            } else {
                let tar = out.deletingPathExtension().appendingPathExtension("tar")
                let parent = urls[0].deletingLastPathComponent()
                try Shell.run("/usr/bin/tar", ["-cf", tar.path] + urls.map(\.lastPathComponent),
                              cwd: parent)
                try Shell.run("/usr/bin/gzip", ["-f", tar.path])
                let gz = tar.appendingPathExtension("gz")
                let final = out.deletingPathExtension().appendingPathExtension("tar.gz")
                if gz.standardizedFileURL != final.standardizedFileURL {
                    try? FileManager.default.removeItem(at: final)
                    try FileManager.default.moveItem(at: gz, to: final)
                }
                return final
            }
        default:
            throw ZestError("Unsupported archive format .\(ext)")
        }
        return out
    }

    private static func makeZip(_ urls: [URL], out: URL) throws {
        if urls.count == 1 {
            try Shell.run("/usr/bin/ditto",
                          ["-c", "-k", "--norsrc", "--noextattr", "--keepParent",
                           urls[0].path, out.path])
            return
        }
        let staging = Temp.dir()
        for url in urls {
            let target = staging.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: target)
        }
        try Shell.run("/usr/bin/ditto",
                      ["-c", "-k", "--norsrc", "--noextattr", staging.path, out.path])
    }

    static func extract(_ input: URL) throws -> URL {
        let ext = input.pathExtension.lowercased()
        let base = input.deletingPathExtension().lastPathComponent
        let dir = uniqueDirectory(near: input, name: base)

        switch ext {
        case "zip":
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Shell.run("/usr/bin/ditto", ["-x", "-k", input.path, dir.path])
        case "tar":
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Shell.run("/usr/bin/tar", ["-xf", input.path, "-C", dir.path])
        case "gz", "tgz":
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if ext == "tgz" {
                try Shell.run("/usr/bin/tar", ["-xzf", input.path, "-C", dir.path])
            } else {
                let decompressed = dir.appendingPathComponent(base)
                try Shell.run("/bin/sh", ["-c",
                    "gzip -dc \(shellQuote(input.path)) > \(shellQuote(decompressed.path))"])
                if base.lowercased().hasSuffix(".tar") {
                    try Shell.run("/usr/bin/tar", ["-xf", decompressed.path, "-C", dir.path])
                    try? FileManager.default.removeItem(at: decompressed)
                }
            }
        case "bz2", "tbz2":
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Shell.run("/usr/bin/tar", ["-xjf", input.path, "-C", dir.path])
        case "xz", "txz":
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Shell.run("/usr/bin/tar", ["-xJf", input.path, "-C", dir.path])
        case "rar":
            guard let unar = ToolFinder.find("unar") ?? ToolFinder.find("unrar") else {
                throw ZestError("RAR extraction needs unar or unrar (brew install unar)")
            }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if unar.hasSuffix("unar") {
                try Shell.run(unar, ["-q", "-o", dir.path, input.path])
            } else {
                try Shell.run(unar, ["x", "-y", input.path, dir.path + "/"])
            }
        case "7z":
            guard let seven = ToolFinder.find("7zz") ?? ToolFinder.find("7z") else {
                throw ZestError("7z extraction needs 7-zip (brew install sevenzip)")
            }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Shell.run(seven, ["x", "-y", "-o" + dir.path, input.path])
        default:
            throw ZestError("Unsupported archive .\(ext)")
        }
        return dir
    }

    private static func uniqueDirectory(near input: URL, name: String) -> URL {
        let parent = input.deletingLastPathComponent()
        var candidate = parent.appendingPathComponent(name, isDirectory: true)
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(name) \(i)", isDirectory: true)
            i += 1
        }
        return candidate
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
