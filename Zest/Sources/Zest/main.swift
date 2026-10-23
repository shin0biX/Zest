import AppKit

Prefs.register()

let arguments = Array(CommandLine.arguments.dropFirst())
// Finder may still append a process-serial argument to GUI launches; never
// treat that as a CLI invocation.
if let first = arguments.first, !first.hasPrefix("-psn_") {
    let status = CLI.run(arguments)
    exit(status)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
