import AppKit
import SwiftUI

/// Rows you can drag into order, as in Language & Region > Preferred Languages: the dragged row lifts off the list and
/// the rows it passes slide aside to open a gap for it. Right-clicking a row moves it as well, and shows whatever
/// `menu` adds after that.
struct ReorderableList<Item: Identifiable, Row: View, MenuItems: View>: View {
    @Binding var items: [Item]
    let rowHeight: CGFloat
    /// Where each row's divider starts, to line up with the text after the icon.
    let dividerInset: CGFloat
    /// Builds a row, given the order the rows show in at the moment, which follows a drag under way.
    @ViewBuilder let row: (Item, [Item]) -> Row
    @ViewBuilder let menu: (Item) -> MenuItems
    @State private var draggedID: Item.ID?
    @State private var dragTranslation: CGFloat = 0

    private var draggedIndex: Int? {
        guard let draggedID else { return nil }

        return items.firstIndex { item in item.id == draggedID }
    }

    /// The slot the dragged row would land in if it were dropped now.
    private var dropIndex: Int? {
        guard let draggedIndex else { return nil }

        let rowsMoved = Int((dragTranslation / rowHeight).rounded())

        return min(max(draggedIndex + rowsMoved, 0), items.count - 1)
    }

    /// The order the rows would have if the dragged row were dropped now.
    private var displayedOrder: [Item] {
        guard let draggedIndex, let dropIndex else { return items }

        var reordered = items
        reordered.move(fromOffsets: IndexSet(integer: draggedIndex), toOffset: dropIndex > draggedIndex ? dropIndex + 1 : dropIndex)

        return reordered
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                reorderableRow(for: item, at: index)
            }
        }
        // Cancels the form row's own vertical padding, so these rows are spaced like every other row of their height.
        .padding(.vertical, -10)
    }

    private func reorderableRow(for item: Item, at index: Int) -> some View {
        let isDragged = item.id == draggedID
        let slot = displayedSlot(of: index)
        let offset = isDragged
            ? min(max(dragTranslation, -CGFloat(index) * rowHeight), CGFloat(items.count - 1 - index) * rowHeight)
            : CGFloat(slot - index) * rowHeight

        return row(item, displayedOrder)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Move to Top") { move(item, to: 0) }
                    .disabled(items.first?.id == item.id)
                Button("Move Up") { move(item, by: -1) }
                    .disabled(items.first?.id == item.id)
                Button("Move Down") { move(item, by: 1) }
                    .disabled(items.last?.id == item.id)
                Button("Move to Bottom") { move(item, to: items.count - 1) }
                    .disabled(items.last?.id == item.id)
                menu(item)
            }
            .overlay(alignment: .bottom) {
                if !isDragged && slot < items.count - 1 {
                    Divider()
                        .padding(.leading, dividerInset)
                }
            }
            .background {
                if isDragged {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                        .padding(.horizontal, -6)
                }
            }
            .offset(y: offset)
            .zIndex(isDragged ? 1 : 0)
            .animation(isDragged ? nil : .easeOut(duration: 0.18), value: dropIndex)
            .gesture(reorderGesture(for: item))
            .accessibilityAction(named: "Move Up") { move(item, by: -1) }
            .accessibilityAction(named: "Move Down") { move(item, by: 1) }
    }

    /// Where a row shows while a drag is under way: rows between the dragged row and its drop slot step aside.
    private func displayedSlot(of index: Int) -> Int {
        guard let draggedIndex, let dropIndex else { return index }

        if index == draggedIndex { return dropIndex }
        if draggedIndex < index && index <= dropIndex { return index - 1 }
        if dropIndex <= index && index < draggedIndex { return index + 1 }

        return index
    }

    private func reorderGesture(for item: Item) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggedID == nil {
                    draggedID = item.id
                    NSCursor.closedHand.push()
                }

                dragTranslation = value.translation.height
            }
            .onEnded { _ in
                NSCursor.pop()

                withAnimation(.easeOut(duration: 0.18)) {
                    items = displayedOrder
                    draggedID = nil
                    dragTranslation = 0
                }
            }
    }

    private func move(_ item: Item, by step: Int) {
        guard let index = items.firstIndex(where: { candidate in candidate.id == item.id }) else { return }

        move(item, to: index + step)
    }

    private func move(_ item: Item, to targetIndex: Int) {
        guard let index = items.firstIndex(where: { candidate in candidate.id == item.id }) else { return }

        var reordered = items
        let movedItem = reordered.remove(at: index)
        reordered.insert(movedItem, at: min(max(targetIndex, 0), reordered.count))
        items = reordered
    }
}

extension ReorderableList where MenuItems == EmptyView {
    init(items: Binding<[Item]>, rowHeight: CGFloat, dividerInset: CGFloat, @ViewBuilder row: @escaping (Item, [Item]) -> Row) {
        self.init(items: items, rowHeight: rowHeight, dividerInset: dividerInset, row: row, menu: { _ in EmptyView() })
    }
}
