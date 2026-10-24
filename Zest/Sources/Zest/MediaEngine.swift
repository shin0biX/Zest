import AppKit

// MARK: - Media engine

enum MediaEngine {
    static func convert(_ input: URL, to fmt: Fmt, params: [String: String] = [:]) throws -> [URL] {
        guard let ffmpeg = ToolFinder.ffmpeg else {
            throw ZestError("ffmpeg is required for video and audio. Install it with: brew install ffmpeg")
        }
        let out = Naming.output(for: input, ext: fmt.ext)
        let crf = Int(params["crf"] ?? "") ?? crfForPreset()
        let audioBitrate = params["audioBitrate"] ?? "192k"
        let maxHeight = Int(params["maxHeight"] ?? "") ?? 0
        var videoFilter: [String] = []
        if maxHeight > 0 {
            // Downscale only: `min(ih,h)` never enlarges a smaller source.
            videoFilter = ["-vf", "scale=-2:min(ih\\,\(maxHeight))"]
        }

        switch fmt.ext.lowercased() {
        case "mp4", "mov":
            try Shell.run(ffmpeg, ["-y", "-i", input.path] + videoFilter + [
                                   "-c:v", "libx264", "-preset", "medium", "-crf", "\(crf)",
                                   "-pix_fmt", "yuv420p",
                                   "-c:a", "aac", "-b:a", audioBitrate,
                                   "-movflags", "+faststart", out.path])
        case "mkv":
            try Shell.run(ffmpeg, ["-y", "-i", input.path] + videoFilter + [
                                   "-c:v", "libx264", "-preset", "medium", "-crf", "\(crf)",
                                   "-c:a", "aac", "-b:a", audioBitrate, out.path])
        case "webm":
            try Shell.run(ffmpeg, ["-y", "-i", input.path] + videoFilter + [
                                   "-c:v", "libvpx-vp9", "-crf", "\(crf + 5)", "-b:v", "0",
                                   "-row-mt", "1",
                                   "-c:a", "libopus", "-b:a", audioBitrate, out.path])
        case "avi":
            try Shell.run(ffmpeg, ["-y", "-i", input.path] + videoFilter + [
                                   "-c:v", "mpeg4", "-q:v", legacyQuality(crf),
                                   "-c:a", "libmp3lame", "-q:a", "4", out.path])
        case "wmv":
            try Shell.run(ffmpeg, ["-y", "-i", input.path] + videoFilter + [
                                   "-c:v", "wmv2", "-q:v", legacyQuality(crf),
                                   "-c:a", "wmav2", "-b:a", audioBitrate, out.path])
        case "gif":
            return [try makeGIF(input, to: out,
                                fps: Int(params["fps"] ?? "") ?? 12,
                                width: Int(params["width"] ?? "") ?? 720)]
        case "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma", "aac", "caf":
            try extractAudio(input, to: out, ext: fmt.ext,
                             bitrate: audioBitrate,
                             bitDepth: params["audioBitDepth"] ?? "16")
        default:
            throw ZestError("No media converter for .\(fmt.ext)")
        }
        return [out]
    }

    /// mpeg4/wmv2 have no CRF; map the requested CRF onto their `-q:v`
    /// scale (2 = near-lossless … 12 = rough) so the video-quality preset
    /// reaches AVI and WMV output too.
    private static func legacyQuality(_ crf: Int) -> String {
        let q = 2 + Int((Double(crf - 18) * 4.0 / 14.0).rounded())
        return String(min(12, max(2, q)))
    }

    static func pcmBE(_ bitDepth: String) -> String {
        switch bitDepth {
        case "24": return "pcm_s24be"
        case "32": return "pcm_s32be"
        default: return "pcm_s16be"
        }
    }

    static func crfForPreset() -> Int {
        switch Prefs.quality {
        case "light": return 20
        case "strong": return 27
        case "maximum": return 31
        default: return 23
        }
    }

    static func audioBitrateForPreset() -> String {
        switch Prefs.quality {
        case "light": return "256k"
        case "strong": return "112k"
        case "maximum": return "80k"
        default: return "160k"
        }
    }

    static func makeGIF(_ input: URL, to out: URL, fps: Int, width: Int) throws -> URL {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg is required for GIF output") }
        let filter = "fps=\(fps),scale=\(width):-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=256[p];[s1][p]paletteuse=dither=sierra2_4a"
        try Shell.run(ffmpeg, ["-y", "-i", input.path, "-vf", filter,
                               "-loop", "0", out.path])
        return out
    }

    static func extractAudio(_ input: URL, to out: URL, ext: String,
                             bitrate: String? = nil, bitDepth: String = "16") throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        let rate = bitrate ?? audioBitrateForPreset()
        let pcm: String = {
            switch bitDepth {
            case "24": return "pcm_s24le"
            case "32": return "pcm_s32le"
            default: return "pcm_s16le"
            }
        }()
        var args = ["-y", "-i", input.path, "-vn"]
        switch ext.lowercased() {
        case "mp3": args += ["-c:a", "libmp3lame", "-b:a", rate]
        case "m4a", "aac": args += ["-c:a", "aac", "-b:a", rate]
        case "wav": args += ["-c:a", pcm]
        case "flac": args += ["-c:a", "flac", "-compression_level", "5"]
        case "ogg": args += ["-c:a", "libvorbis", "-b:a", rate]
        case "opus": args += ["-c:a", "libopus", "-b:a", rate]
        // AIFF is big-endian and ffmpeg supports all three depths, so a
        // 32-bit request really produces 32-bit instead of silently 24.
        case "aiff": args += ["-c:a", Self.pcmBE(bitDepth)]
        case "wma": args += ["-c:a", "wmav2", "-b:a", rate]
        case "caf": args += ["-c:a", pcm]
        default: args += ["-c:a", "aac", "-b:a", rate]
        }
        args.append(out.path)
        try Shell.run(ffmpeg, args)
    }

    // MARK: - Tools

    static func compress(_ input: URL, targetBytes: Int64?, percent: Double?, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        let info = MediaProbe.info(input)
        let isAudioOnly = info.hasAudio && !info.hasVideo

        if let percent, percent > 0, let targetBytes = Optional(Int64(Double(input.fileSize) * (1 - percent / 100))) {
            try compressToSize(input, info: info, targetBytes: targetBytes, out: out)
            return
        }
        if let targetBytes {
            try compressToSize(input, info: info, targetBytes: targetBytes, out: out)
            return
        }

        if isAudioOnly {
            try Shell.run(ffmpeg, ["-y", "-i", input.path, "-vn",
                                   "-c:a", audioCodecForExt(out.pathExtension),
                                   "-b:a", audioBitrateForPreset(), out.path])
        } else {
            try Shell.run(ffmpeg, ["-y", "-i", input.path,
                                   "-c:v", "libx264", "-preset", "medium",
                                   "-crf", "\(crfForPreset())", "-pix_fmt", "yuv420p",
                                   "-c:a", "aac", "-b:a", "128k",
                                   "-movflags", "+faststart", out.path])
        }
    }

    static func compressToSize(_ input: URL, info: MediaProbe.Info,
                               targetBytes: Int64, out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        let duration = info.duration > 0 ? info.duration : 1
        let audioKbps = info.hasAudio && info.hasVideo ? 128.0 : 0.0
        var totalKbps = Double(targetBytes) * 8 / 1000 / duration
        var videoKbps = max(120, totalKbps - audioKbps)

        for attempt in 0..<3 {
            let ext = out.pathExtension.lowercased()
            var args = ["-y", "-i", input.path, "-vn"]
            if info.hasVideo {
                args = ["-y", "-i", input.path,
                        "-c:v", "libx264", "-preset", "medium",
                        "-b:v", "\(Int(videoKbps))k",
                        "-maxrate", "\(Int(videoKbps * 1.45))k",
                        "-bufsize", "\(Int(videoKbps * 2))k",
                        "-pix_fmt", "yuv420p"]
                if info.hasAudio {
                    args += ["-c:a", "aac", "-b:a", "128k"]
                }
                args += ["-movflags", "+faststart"]
                if ext == "webm" {
                    args = ["-y", "-i", input.path,
                            "-c:v", "libvpx-vp9", "-b:v", "\(Int(videoKbps))k",
                            "-c:a", "libopus", "-b:a", "96k"]
                }
            } else {
                let kbps = max(48, min(320, Int(totalKbps)))
                args = ["-y", "-i", input.path, "-vn",
                        "-c:a", audioCodecForExt(ext), "-b:a", "\(kbps)k"]
            }
            args.append(out.path)
            try Shell.run(ffmpeg, args)
            let size = out.fileSize
            if size <= Int64(Double(targetBytes) * 1.02) || attempt == 2 { return }
            videoKbps = max(90, videoKbps * 0.82)
            totalKbps = max(64, totalKbps * 0.85)
        }
    }

    private static func audioCodecForExt(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "libmp3lame"
        case "opus": return "libopus"
        case "ogg": return "libvorbis"
        case "flac": return "flac"
        case "wav", "aiff", "caf": return "pcm_s16le"
        case "wma": return "wmav2"
        default: return "aac"
        }
    }

    static func trim(_ input: URL, start: Double, end: Double?, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        let info = MediaProbe.info(input)
        let finish = end ?? info.duration
        let duration = max(0.05, finish - start)
        try Shell.run(ffmpeg, ["-y", "-ss", "\(start)", "-i", input.path,
                               "-t", "\(duration)",
                               "-c:v", "libx264", "-preset", "medium", "-crf", "\(crfForPreset())",
                               "-c:a", "aac", "-b:a", "160k",
                               "-movflags", "+faststart", out.path])
    }

    static func split(_ input: URL, parts: Int?, every: Double?, to out: URL) throws -> [URL] {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        let info = MediaProbe.info(input)
        guard info.duration > 0 else { throw ZestError("Can't read duration") }
        let segment: Double
        if let every, every > 0 { segment = every }
        else if let parts, parts > 1 { segment = info.duration / Double(parts) }
        else { throw ZestError("Choose a part count or segment length") }

        let dir = out.deletingLastPathComponent()
        let stem = out.deletingPathExtension().lastPathComponent
        let ext = out.pathExtension
        var outputs: [URL] = []
        var index = 0
        var start = 0.0
        while start < info.duration - 0.02 {
            let length = min(segment, info.duration - start)
            let url = dir.appendingPathComponent("\(stem)-\(index + 1).\(ext)")
            try Shell.run(ffmpeg, ["-y", "-ss", "\(start)", "-i", input.path,
                                   "-t", "\(length)",
                                   "-c:v", "libx264", "-preset", "medium", "-crf", "\(crfForPreset())",
                                   "-c:a", "aac", "-b:a", "160k",
                                   "-movflags", "+faststart", url.path])
            outputs.append(url)
            index += 1
            start += segment
        }
        return outputs
    }

    static func join(_ inputs: [URL], to out: URL) throws -> [URL] {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        let infos = inputs.map { MediaProbe.info($0) }
        let anyVideo = infos.contains { $0.hasVideo }

        var args = ["-y"]
        for url in inputs { args += ["-i", url.path] }

        var filters: [String] = []
        var nextIndex = inputs.count
        let n = inputs.count

        if anyVideo {
            let width = infos.first(where: { $0.width > 0 })?.width ?? 1280
            let height = infos.first(where: { $0.height > 0 })?.height ?? 720
            for i in 0..<n {
                filters.append("[\(i):v]scale=\(width):\(height):force_original_aspect_ratio=decrease,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30[v\(i)]")
                if infos[i].hasAudio {
                    filters.append("[\(i):a]aresample=48000[a\(i)]")
                } else {
                    args += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
                    filters.append("[\(nextIndex):a]aresample=48000[a\(nextIndex)]")
                    nextIndex += 1
                }
            }
            let chain = (0..<n).map { "[v\($0)][a\($0)]" }.joined()
            filters.append("\(chain)concat=n=\(n):v=1:a=1[v][a]")
            args += ["-filter_complex", filters.joined(separator: ";"),
                     "-map", "[v]", "-map", "[a]",
                     "-c:v", "libx264", "-preset", "medium", "-crf", "\(crfForPreset())",
                     "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", out.path]
        } else {
            for i in 0..<n {
                if infos[i].hasAudio {
                    filters.append("[\(i):a]aresample=48000[a\(i)]")
                } else {
                    args += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
                    filters.append("[\(nextIndex):a]aresample=48000[a\(nextIndex)]")
                    nextIndex += 1
                }
            }
            let chain = (0..<n).map { "[a\($0)]" }.joined()
            filters.append("\(chain)concat=n=\(n):v=0:a=1[a]")
            args += ["-filter_complex", filters.joined(separator: ";"),
                     "-map", "[a]", "-c:a", audioCodecForExt(out.pathExtension),
                     "-b:a", "192k", out.path]
        }
        try Shell.run(ffmpeg, args)
        return [out]
    }

    static func speed(_ input: URL, factor: Double, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        let info = MediaProbe.info(input)
        guard factor > 0.05 else { throw ZestError("Speed must be greater than zero") }

        var atempo = factor
        var chain: [String] = []
        while atempo > 2.0 { chain.append("atempo=2.0"); atempo /= 2.0 }
        while atempo < 0.5 { chain.append("atempo=0.5"); atempo /= 0.5 }
        chain.append("atempo=\(atempo)")

        if info.hasVideo {
            let video = "[0:v]setpts=PTS/\(factor)[v]"
            if info.hasAudio {
                let audio = "[0:a]\(chain.joined(separator: ","))[a]"
                try Shell.run(ffmpeg, ["-y", "-i", input.path,
                                       "-filter_complex", "\(video);\(audio)",
                                       "-map", "[v]", "-map", "[a]",
                                       "-c:v", "libx264", "-preset", "medium",
                                       "-crf", "\(crfForPreset())",
                                       "-c:a", "aac", "-b:a", "160k",
                                       "-movflags", "+faststart", out.path])
            } else {
                try Shell.run(ffmpeg, ["-y", "-i", input.path,
                                       "-filter_complex", video, "-map", "[v]",
                                       "-c:v", "libx264", "-preset", "medium",
                                       "-crf", "\(crfForPreset())", out.path])
            }
        } else {
            try Shell.run(ffmpeg, ["-y", "-i", input.path,
                                   "-filter:a", chain.joined(separator: ","),
                                   "-c:a", audioCodecForExt(out.pathExtension),
                                   "-b:a", "192k", out.path])
        }
    }

    static func crop(_ input: URL, width: Int, height: Int, x: Int, y: Int, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        try Shell.run(ffmpeg, ["-y", "-i", input.path,
                               "-vf", "crop=\(width):\(height):\(x):\(y)",
                               "-c:v", "libx264", "-preset", "medium", "-crf", "\(crfForPreset())",
                               "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", out.path])
    }

    static func rotate(_ input: URL, degrees: Int, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        let normalized = ((degrees % 360) + 360) % 360
        let filter: String
        switch normalized {
        case 90: filter = "transpose=1"
        case 180: filter = "hflip,vflip"
        case 270: filter = "transpose=2"
        default: filter = "null"
        }
        try Shell.run(ffmpeg, ["-y", "-i", input.path, "-vf", filter,
                               "-c:v", "libx264", "-preset", "medium", "-crf", "\(crfForPreset())",
                               "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", out.path])
    }

    static func snapshot(_ input: URL, at seconds: Double, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        try Shell.run(ffmpeg, ["-y", "-ss", "\(max(0, seconds))", "-i", input.path,
                               "-frames:v", "1", out.path])
    }

    static func mute(_ input: URL, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        try Shell.run(ffmpeg, ["-y", "-i", input.path, "-c:v", "copy", "-an", out.path])
    }

    static func normalize(_ input: URL, lufs: Double, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        try Shell.run(ffmpeg, ["-y", "-i", input.path, "-vn",
                               "-af", "loudnorm=I=\(lufs):TP=-1.5:LRA=11",
                               "-c:a", audioCodecForExt(out.pathExtension),
                               "-b:a", "192k", out.path])
    }

    static func bleep(_ input: URL, start: Double, end: Double, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        let filter = "volume=enable='between(t,\(start),\(end))':volume=0"
        try Shell.run(ffmpeg, ["-y", "-i", input.path, "-af", filter,
                               "-c:v", "copy", "-c:a", audioCodecForExt(out.pathExtension),
                               out.path])
    }

    /// Blurs, pixelates, or blacks out a rectangle for part of the timeline.
    static func redactVideo(_ input: URL, region: CGRect, start: Double, end: Double,
                            mode: String, crf: Int, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        // libx264 with yuv420p wants even dimensions.
        let width = max(2, Int(region.width.rounded(.down)) & ~1)
        let height = max(2, Int(region.height.rounded(.down)) & ~1)
        let x = max(0, Int(region.minX.rounded()))
        let y = max(0, Int(region.minY.rounded()))
        let range = "between(t,\(start),\(end))"
        let filter: String
        switch mode {
        case "blur":
            filter = "[0:v]split=2[base][r];[r]crop=\(width):\(height):\(x):\(y),gblur=sigma=24[red];"
                + "[base][red]overlay=\(x):\(y):enable='\(range)'[v]"
        case "pixelate":
            let smallW = max(2, (width / 16) & ~1)
            let smallH = max(2, (height / 16) & ~1)
            filter = "[0:v]split=2[base][r];[r]crop=\(width):\(height):\(x):\(y),"
                + "scale=\(smallW):\(smallH):flags=neighbor,scale=\(width):\(height):flags=neighbor[red];"
                + "[base][red]overlay=\(x):\(y):enable='\(range)'[v]"
        default:
            filter = "[0:v]drawbox=x=\(x):y=\(y):w=\(width):h=\(height):color=black:t=fill:enable='\(range)'[v]"
        }
        try Shell.run(ffmpeg, ["-y", "-i", input.path, "-filter_complex", filter,
                               "-map", "[v]", "-map", "0:a?", "-c:a", "aac", "-b:a", "192k",
                               "-c:v", "libx264", "-preset", "medium", "-crf", "\(crf)",
                               "-pix_fmt", "yuv420p", "-movflags", "+faststart", out.path])
    }

    /// Replaces a time range with a tone (or silence) so the sensitive words
    /// are gone but the track keeps its length and rhythm.
    static func redactAudio(_ input: URL, start: Double, end: Double, mode: String,
                            frequency: Double, duration: Double, keepVideo: Bool,
                            to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        let codec = audioCodecForExt(out.pathExtension)
        let range = "between(t,\(start),\(end))"
        var args = ["-y", "-i", input.path]
        if mode == "tone" {
            let length = max(duration, 0.1)
            args += ["-f", "lavfi", "-i",
                     "sine=frequency=\(Int(frequency.rounded())):duration=\(length)"]
            let filter = "[0:a]volume=0:enable='\(range)'[main];"
                + "[1:a]volume=0.32:enable='\(range)',volume=0:enable='not(\(range))'[tone];"
                + "[main][tone]amix=inputs=2:duration=first:normalize=0[a]"
            args += ["-filter_complex", filter, "-map", "[a]"]
        } else {
            args += ["-af", "volume=0:enable='\(range)'"]
        }
        if keepVideo {
            args += ["-map", "0:v", "-c:v", "copy"]
        } else {
            args += ["-vn"]
        }
        args += ["-c:a", codec, "-b:a", "192k", out.path]
        try Shell.run(ffmpeg, args)
    }

    /// Turns an audio track into a video: a still image when one is supplied,
    /// otherwise a solid colour frame at the requested size.
    static func audioToVideo(_ input: URL, background: URL?, color: String,
                             width: Int, height: Int, crf: Int, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        let size = "\(width)x\(height)"
        let hex = color.hasPrefix("#") ? "0x" + color.dropFirst() : color
        var args = ["-y"]
        if let background, FileManager.default.fileExists(atPath: background.path) {
            args += ["-loop", "1", "-framerate", "30", "-i", background.path,
                     "-i", input.path]
        } else {
            args += ["-f", "lavfi", "-i", "color=c=\(hex):s=\(size):r=30",
                     "-i", input.path]
        }
        let filter = "[0:v]scale=\(width):\(height):force_original_aspect_ratio=decrease,"
            + "pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2:color=\(hex),format=yuv420p[v]"
        args += ["-filter_complex", filter, "-map", "[v]", "-map", "1:a",
                 "-c:v", "libx264", "-preset", "medium", "-crf", "\(crf)",
                 "-tune", "stillimage", "-c:a", "aac", "-b:a", "192k",
                 "-shortest", "-movflags", "+faststart", out.path]
        try Shell.run(ffmpeg, args)
    }

    static func channels(_ input: URL, mono: Bool, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        try Shell.run(ffmpeg, ["-y", "-i", input.path, "-vn",
                               "-ac", mono ? "1" : "2",
                               "-c:a", audioCodecForExt(out.pathExtension),
                               "-b:a", "192k", out.path])
    }

    static func sampleRate(_ input: URL, rate: Int, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        try Shell.run(ffmpeg, ["-y", "-i", input.path, "-vn",
                               "-ar", "\(rate)", "-ac", "2",
                               "-c:a", audioCodecForExt(out.pathExtension),
                               "-b:a", "192k", out.path])
    }

    // MARK: Metadata

    static func metadata(_ input: URL) -> [(String, String)] {
        guard let ffprobe = ToolFinder.ffprobe else { return [] }
        guard let result = try? Shell.runAllowFailure(ffprobe, [
            "-v", "quiet", "-print_format", "json",
            "-show_format", "-show_streams", input.path
        ]), result.0 == 0,
              let data = result.1.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        var out: [(String, String)] = []
        if let format = json["format"] as? [String: Any] {
            for key in ["format_name", "duration", "size", "bit_rate"] {
                if let value = format[key] {
                    out.append((key.replacingOccurrences(of: "_", with: " ").capitalized,
                                "\(value)"))
                }
            }
            if let tags = format["tags"] as? [String: Any] {
                for key in tags.keys.sorted() {
                    out.append((key, "\(tags[key] ?? "")"))
                }
            }
        }
        if let streams = json["streams"] as? [[String: Any]] {
            for (i, stream) in streams.enumerated() {
                let type = stream["codec_type"] as? String ?? "stream"
                if let codec = stream["codec_name"] {
                    out.append(("Stream \(i + 1)", "\(type) · \(codec)"))
                } else {
                    out.append(("Stream \(i + 1)", type))
                }
            }
        }
        return out
    }

    /// Maps the editor's human labels onto container tags ffmpeg understands.
    static func mapMetadataKeys(_ values: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in values where !value.isEmpty {
            switch key.lowercased() {
            case "title": out["title"] = value
            case "author", "artist": out["artist"] = value
            case "description", "comment", "subject": out["comment"] = value
            case "copyright": out["copyright"] = value
            case "keywords", "genre", "album", "date":
                out[key.lowercased()] = value
            default: break // Unsupported tags are dropped rather than corrupting the file.
            }
        }
        return out
    }

    static func applyMetadata(_ input: URL, values: [String: String],
                              remove: Bool, to out: URL) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
        var args = ["-y", "-i", input.path, "-map", "0", "-c", "copy"]
        if remove {
            args += ["-map_metadata", "-1"]
        } else {
            for (key, value) in mapMetadataKeys(values) {
                args += ["-metadata", "\(key)=\(value)"]
            }
        }
        args.append(out.path)
        try Shell.run(ffmpeg, args)
    }
}

// MARK: - Dispatch

enum Convert {
    static func perform(_ input: URL, to fmt: Fmt, params: [String: String] = [:]) throws -> [URL] {
        switch KindDetector.kind(of: input) {
        case .image:
            return try ImageEngine.convert(input, to: fmt, params: params)
        case .video, .audio:
            return try MediaEngine.convert(input, to: fmt, params: params)
        case .pdf:
            return try PDFEngine.convert(input, to: fmt, params: params)
        case .document, .slides:
            return try DocEngine.convert(input, to: fmt, params: params)
        case .sheet:
            return try SheetEngine.convert(input, to: fmt, params: params)
        case .subtitle:
            return try SubtitleEngine.convert(input, to: fmt, params: params)
        case .archive, .folder:
            return try ArchiveEngine.convert(input, to: fmt, params: params)
        case .other:
            throw ZestError("No converter for .\(input.pathExtension) files")
        }
    }
}
