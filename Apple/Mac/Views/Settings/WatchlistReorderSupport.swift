import SwiftUI

/// Gesture-driven state machine for reordering the watchlist.
///
/// Design notes (do not go back to NSDraggingSession + DropDelegate):
/// - The floating row is a real SwiftUI view (overlay), not an ImageRenderer snapshot, so it matches the list row;
/// - The insertion slot is pure math (floating row center Y ÷ fixed row height), not per-row drop hit-testing,
///   so rows animating out of the way cannot cause a reorder feedback loop (the cause of the old jitter);
/// - While dragging only the preview state changes; the real order is committed once after the settle animation.
@MainActor
final class WatchlistReorderSession: ObservableObject {
    /// Full row height (including the bottom divider); all reorder geometry is based on this fixed value.
    nonisolated static let rowHeight: CGFloat = 44
    /// Coordinate space name shared by the DragGesture and the scroll geometry.
    nonisolated static let coordinateSpaceName = "watchlistReorderViewport"
    /// Distance from the viewport's top/bottom edge that starts auto-scrolling.
    private static let autoScrollEdge: CGFloat = 32

    private enum AutoScrollDirection {
        case up
        case down
    }

    /// Id of the coin being dragged; non-nil means dragging (or settling).
    @Published private(set) var draggedID: String?
    /// Display slot of the gap (0 ..< row count).
    @Published private(set) var insertionIndex = 0
    /// Y of the floating row's top edge in viewport coordinates.
    @Published private(set) var floatingY: CGFloat = 0
    /// The floating row is animating into place after release; gesture input is ignored meanwhile.
    @Published private(set) var isSettling = false

    private var orderIDs: [String] = []
    private var sourceIndex = 0
    private var grabOffsetY: CGFloat = 0
    private var scrollOffset: CGFloat = 0
    private var viewportHeight: CGFloat = 0
    private var reduceMotion = false
    private var scrollProxy: ScrollViewProxy?
    private var commitHandler: (([String]) -> Void)?
    private var autoScrollTask: Task<Void, Never>?
    private var autoScrollDirection: AutoScrollDirection?

    var isActive: Bool { draggedID != nil }

    /// Animation for rows moving out of the gap's way; respects Reduce Motion.
    private var rowAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.18)
    }

    /// How far the row at `index` shifts to make room for the gap. The dragged row keeps its slot (hidden as the gap).
    func offset(forRowAt index: Int) -> CGFloat {
        guard isActive, index != sourceIndex else { return 0 }
        if sourceIndex < index, index <= insertionIndex { return -Self.rowHeight }
        if insertionIndex <= index, index < sourceIndex { return Self.rowHeight }
        return 0
    }

    func begin(
        id: String,
        index: Int,
        orderIDs: [String],
        viewportHeight: CGFloat,
        location: CGPoint,
        reduceMotion: Bool,
        proxy: ScrollViewProxy,
        commit: @escaping ([String]) -> Void
    ) {
        guard !isActive, orderIDs.indices.contains(index) else { return }
        self.orderIDs = orderIDs
        sourceIndex = index
        self.viewportHeight = viewportHeight
        self.reduceMotion = reduceMotion
        scrollProxy = proxy
        commitHandler = commit

        let rowTop = CGFloat(index) * Self.rowHeight - scrollOffset
        grabOffsetY = location.y - rowTop

        // On pick-up the floating row sits exactly on the original row, so no transition is needed.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            floatingY = rowTop
            insertionIndex = index
            draggedID = id
        }
    }

    func update(location: CGPoint) {
        guard isActive, !isSettling else { return }
        floatingY = clampedFloatingY(location.y - grabOffsetY)
        recomputeInsertionIndex()
        updateAutoScroll(cursorY: location.y)
    }

    func end() {
        guard isActive, !isSettling else { return }
        stopAutoScroll()

        if reduceMotion {
            completeDrag()
            return
        }

        isSettling = true
        let slotY = CGFloat(insertionIndex) * Self.rowHeight - scrollOffset
        withAnimation(.snappy(duration: 0.22)) {
            floatingY = slotY
        } completion: { [weak self] in
            self?.completeDrag()
        }
    }

    /// Abandons the drag (view disappeared, coins added or removed elsewhere) without committing an order.
    func cancel() {
        guard isActive else { return }
        commitHandler = nil
        reset()
    }

    /// Continuously fed from the list's scroll geometry; scrolling during a drag recomputes the slot under the cursor.
    func updateScrollOffset(_ offset: CGFloat) {
        scrollOffset = offset
        guard isActive, !isSettling else { return }
        recomputeInsertionIndex()
    }

    // MARK: - Private

    private func completeDrag() {
        let moved = insertionIndex != sourceIndex
        let finalOrder = previewOrder()
        let commit = commitHandler
        reset()
        // Reset before committing: in the same render pass, the new order with no offsets matches the settled frame, so nothing flickers.
        if moved {
            commit?(finalOrder)
        }
    }

    private func previewOrder() -> [String] {
        guard orderIDs.indices.contains(sourceIndex) else { return orderIDs }
        var ids = orderIDs
        let moved = ids.remove(at: sourceIndex)
        ids.insert(moved, at: min(max(insertionIndex, 0), ids.count))
        return ids
    }

    private func reset() {
        stopAutoScroll()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            draggedID = nil
            isSettling = false
            insertionIndex = 0
            floatingY = 0
        }
        orderIDs = []
        commitHandler = nil
        scrollProxy = nil
    }

    private func clampedFloatingY(_ y: CGFloat) -> CGFloat {
        let contentHeight = CGFloat(orderIDs.count) * Self.rowHeight
        let lower = max(0, -scrollOffset)
        let upper = min(viewportHeight, contentHeight - scrollOffset) - Self.rowHeight
        guard upper > lower else { return lower }
        return min(max(y, lower), upper)
    }

    private func recomputeInsertionIndex() {
        guard !orderIDs.isEmpty else { return }
        let centerY = floatingY + Self.rowHeight / 2 + scrollOffset
        let index = min(max(Int(centerY / Self.rowHeight), 0), orderIDs.count - 1)
        guard index != insertionIndex else { return }
        withAnimation(rowAnimation) {
            insertionIndex = index
        }
    }

    private func updateAutoScroll(cursorY: CGFloat) {
        let contentHeight = CGFloat(orderIDs.count) * Self.rowHeight
        let canScrollUp = scrollOffset > 1
        let canScrollDown = scrollOffset + viewportHeight < contentHeight - 1

        if cursorY < Self.autoScrollEdge, canScrollUp {
            startAutoScroll(.up)
        } else if cursorY > viewportHeight - Self.autoScrollEdge, canScrollDown {
            startAutoScroll(.down)
        } else {
            stopAutoScroll()
        }
    }

    private func startAutoScroll(_ direction: AutoScrollDirection) {
        guard autoScrollDirection != direction else { return }
        stopAutoScroll()
        autoScrollDirection = direction
        autoScrollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isActive, !self.isSettling else { return }
                self.autoScrollTick(direction)
                try? await Task.sleep(for: .milliseconds(130))
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        autoScrollDirection = nil
    }

    private func autoScrollTick(_ direction: AutoScrollDirection) {
        guard let scrollProxy, !orderIDs.isEmpty else { return }
        let contentHeight = CGFloat(orderIDs.count) * Self.rowHeight

        switch direction {
        case .up:
            guard scrollOffset > 1 else {
                stopAutoScroll()
                return
            }
            let topIndex = Int((scrollOffset / Self.rowHeight).rounded(.down))
            let next = max(topIndex - 1, 0)
            withAnimation(.linear(duration: 0.12)) {
                scrollProxy.scrollTo(orderIDs[next], anchor: .top)
            }
        case .down:
            guard scrollOffset + viewportHeight < contentHeight - 1 else {
                stopAutoScroll()
                return
            }
            let bottomIndex = Int(((scrollOffset + viewportHeight) / Self.rowHeight).rounded(.up)) - 1
            let next = min(bottomIndex + 1, orderIDs.count - 1)
            withAnimation(.linear(duration: 0.12)) {
                scrollProxy.scrollTo(orderIDs[next], anchor: .bottom)
            }
        }
    }
}
