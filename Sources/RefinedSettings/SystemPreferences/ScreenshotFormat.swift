/// The raw values are what macOS stores in the screenshot preferences.
enum ScreenshotFormat: String, CaseIterable, Identifiable {
    case png
    case jpg
    case heic
    case pdf
    case tiff

    /// What macOS uses when nothing has been chosen.
    static let macOSDefault = ScreenshotFormat.png

    var id: Self { self }

    var title: String {
        rawValue.uppercased()
    }
}
