import AppKit
import UniformTypeIdentifiers

enum TriggerKey: String, CaseIterable {
    case shift, command, control, option

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .command: return .command
        case .control: return .control
        case .option: return .option
        }
    }

    var title: String {
        switch self {
        case .shift: return "Shift ⇧"
        case .command: return "Command ⌘"
        case .control: return "Control ⌃"
        case .option: return "Option ⌥"
        }
    }
}

enum Prefs {
    static let defaults = UserDefaults(suiteName: "com.zest.app") ?? .standard

    static func register() {
        defaults.register(defaults: [
            "key.convert": TriggerKey.shift.rawValue,
            "key.tools": TriggerKey.command.rawValue,
            "key.actions": TriggerKey.control.rawValue,
            "collision": "keepBoth",
            "sound": true,
            "quality": "balanced",
            "keyboardControl": false
        ])
    }

    static var convertKey: TriggerKey {
        get { TriggerKey(rawValue: defaults.string(forKey: "key.convert") ?? "") ?? .shift }
        set { defaults.set(newValue.rawValue, forKey: "key.convert") }
    }

    static var toolsKey: TriggerKey {
        get { TriggerKey(rawValue: defaults.string(forKey: "key.tools") ?? "") ?? .command }
        set { defaults.set(newValue.rawValue, forKey: "key.tools") }
    }

    static var actionsKey: TriggerKey {
        get { TriggerKey(rawValue: defaults.string(forKey: "key.actions") ?? "") ?? .control }
        set { defaults.set(newValue.rawValue, forKey: "key.actions") }
    }

    static var collisionPolicy: String {
        get { defaults.string(forKey: "collision") ?? "keepBoth" }
        set { defaults.set(newValue, forKey: "collision") }
    }

    static var playSound: Bool {
        get { defaults.object(forKey: "sound") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "sound") }
    }

    static var quality: String {
        get { defaults.string(forKey: "quality") ?? "balanced" }
        set { defaults.set(newValue, forKey: "quality") }
    }

    static var keyboardControl: Bool {
        get { defaults.object(forKey: "keyboardControl") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "keyboardControl") }
    }

    static func toolOverride(_ name: String) -> String? {
        let value = defaults.string(forKey: "tool.\(name)") ?? ""
        return value.isEmpty ? nil : value
    }

    static func setToolOverride(_ name: String, _ path: String) {
        defaults.set(path, forKey: "tool.\(name)")
    }
}

enum Capability {
    static var ffmpeg: Bool { ToolFinder.ffmpeg != nil }
    static var webpEncode: Bool { ToolFinder.cwebp != nil || ffmpeg }
    static var avifEncode: Bool { ffmpeg || ImageSupport.canEncode("avif") }
    static var officeExport: Bool { ToolFinder.soffice != nil }
    static var pagesOutput: Bool { FileManager.default.fileExists(atPath: "/Applications/Pages.app") }
    static var rarInput: Bool { ToolFinder.find("unar") != nil || ToolFinder.find("unrar") != nil }
}

enum ImageSupport {
    static let destinationTypes: Set<String> = {
        (CGImageDestinationCopyTypeIdentifiers() as? [String]).map(Set.init) ?? []
    }()

    static func canEncode(_ ext: String) -> Bool {
        guard let ut = UTType(filenameExtension: ext) else { return false }
        return destinationTypes.contains(ut.identifier)
    }
}
