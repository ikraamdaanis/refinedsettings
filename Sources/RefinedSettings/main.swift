import AppKit

// Settings move over from Linkguide before anything reads them.
LinkguideMigration.runIfNeeded()

// The delegate is installed before run() so the links that launched the app reach it.
let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
NSApplication.shared.run()
