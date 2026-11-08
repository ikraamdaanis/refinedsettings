import SwiftUI

@MainActor
final class PickerModel: ObservableObject {
    @Published var headline = ""
    @Published var fullURL = ""
    @Published var queuedCount = 0
    @Published var entries: [BrowserEntry] = []
    @Published var selectedIndex = 0
}

struct PickerView: View {
    @ObservedObject var model: PickerModel
    let onOpen: (BrowserEntry) -> Void
    let onCancel: () -> Void

    private var selectedEntry: BrowserEntry? {
        model.entries.indices.contains(model.selectedIndex) ? model.entries[model.selectedIndex] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.headline)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.fullURL)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.fullURL)
            }
            VStack(spacing: 2) {
                if model.entries.isEmpty {
                    Text("No browsers to show. Turn some on in Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                    EntryRow(entry: entry, shortcut: index < 9 ? "\(index + 1)" : nil, isSelected: index == model.selectedIndex)
                        .onTapGesture(count: 2) { onOpen(entry) }
                        .simultaneousGesture(TapGesture().onEnded { model.selectedIndex = index })
                        .accessibilityAction { onOpen(entry) }
                }
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
            HStack(spacing: 8) {
                if model.queuedCount > 0 {
                    Text(model.queuedCount == 1 ? "1 more link waiting" : "\(model.queuedCount) more links waiting")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Open") {
                    if let selectedEntry {
                        onOpen(selectedEntry)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedEntry == nil)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(width: 380)
    }
}

private struct EntryRow: View {
    let entry: BrowserEntry
    let shortcut: String?
    let isSelected: Bool

    private var secondaryColor: Color {
        isSelected ? Color(nsColor: .alternateSelectedControlTextColor).opacity(0.8) : .secondary
    }

    var body: some View {
        HStack(spacing: 10) {
            EntryIcon(entry: entry, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.browserName)
                    .lineLimit(1)
                if let profileName = entry.profileName {
                    Text(profileName)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(secondaryColor)
                }
            }
            Spacer(minLength: 8)
            if let shortcut {
                Text(shortcut)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(secondaryColor)
                    .accessibilityLabel("Shortcut \(shortcut)")
            }
        }
        .foregroundStyle(isSelected ? Color(nsColor: .alternateSelectedControlTextColor) : .primary)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The browser's app icon, with the profile's picture as a small round badge in the corner.
struct EntryIcon: View {
    let entry: BrowserEntry
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: entry.icon)
                .resizable()
                .frame(width: size, height: size)
            if let profilePicture = entry.profilePicture {
                Image(nsImage: profilePicture)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size / 2 + 3, height: size / 2 + 3)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5))
                    .offset(x: size / 10, y: size / 10)
            }
        }
        .accessibilityHidden(true)
    }
}
