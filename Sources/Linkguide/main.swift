import AppKit

// The delegate is installed before run() so the links that launched the app reach it.
let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
NSApplication.shared.run()
