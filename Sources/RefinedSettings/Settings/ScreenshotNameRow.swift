import SwiftUI

/// Keeps what's being typed apart from what's saved, because the saved name has spaces trimmed from its ends and using
/// it directly would stop anyone typing a space between two words.
struct ScreenshotNameRow: View {
    @ObservedObject private var store = SystemPreferenceStore.shared
    @State private var typedName = SystemPreferenceStore.shared.screenshotName ?? ""

    var body: some View {
        SystemPreferenceRow(
            title: "File name",
            detail: "Used in place of the word Screenshot.",
            isChanged: store.isChanged(.screenshotName),
            reset: { store.reset(.screenshotName) }
        ) {
            TextField("File name", text: $typedName, prompt: Text("Screenshot"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
        }
        .onChange(of: typedName) { name in
            store.setScreenshotName(name)
        }
        .onChange(of: store.screenshotName) { savedName in
            if savedName != store.cleanedScreenshotName(typedName) {
                typedName = savedName ?? ""
            }
        }
    }
}
