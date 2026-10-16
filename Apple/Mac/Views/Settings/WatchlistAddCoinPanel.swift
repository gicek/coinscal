import SwiftUI
import AppKit

/// Add-coin panel dropped below the "+" in the Watchlist title bar: a search field over the listed coins.
/// With no query it lists every listed coin in catalog order. Clicking a row adds the coin, or removes it when it is
/// already in the watchlist; the panel stays open so several coins can be added or removed in a row.
/// An in-window card rather than a popover: NSPopover centres on its arrow and only shifts at screen edges,
/// so under a "+" at the window's trailing edge half of it would hang outside the window.
struct WatchlistAddCoinPanel: View {
    private enum Layout {
        static let width: CGFloat = 300
        static let maxListHeight: CGFloat = 320
        static let iconSize: CGFloat = 24
        static let rowCornerRadius: CGFloat = 6
        static let cornerRadius: CGFloat = 12
    }

    let isAdded: (CoinMetadata) -> Bool
    /// Adds the coin, or removes it when it is already in the watchlist.
    let toggle: (CoinMetadata) -> Void
    let close: () -> Void

    @EnvironmentObject private var vm: WatchlistViewModel
    @FocusState private var searchFocused: Bool
    @State private var hoveredID: String?
    @State private var escapeMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(10)
            Divider()
            resultsList
                // Shrinks with a short window instead of running past its bottom edge.
                .frame(maxHeight: Layout.maxListHeight)
        }
        .frame(width: Layout.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .onAppear {
            searchFocused = true
            installEscapeMonitor()
        }
        .onDisappear(perform: removeEscapeMonitor)
    }

    /// Esc closes the panel. The focused search field's editor swallows Esc, so `onExitCommand` never fires;
    /// a local key monitor catches it first, except while an input method is composing (Esc cancels that).
    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            close()
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(loc("watchlist.search.placeholder"), text: $vm.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                // Return adds the first match that is not in the watchlist yet.
                .onSubmit {
                    if let first = vm.addCoinResults.first(where: { !isAdded($0) }) { toggle(first) }
                }
            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(loc("watchlist.search.clear"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    @ViewBuilder
    private var resultsList: some View {
        let coins = vm.addCoinResults
        if coins.isEmpty {
            Text(loc("watchlist.search.noResults"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(coins, id: \.id) { meta in
                        row(meta)
                    }
                }
                .padding(6)
            }
        }
    }

    private func row(_ meta: CoinMetadata) -> some View {
        let added = isAdded(meta)
        let hovered = hoveredID == meta.id
        // Hovering an added row turns its checkmark into a red minus: clicking it removes the coin.
        return Button(action: { toggle(meta) }) {
            HStack(spacing: 10) {
                CoinLogoView(coinID: meta.id, assetName: meta.logoAssetName, urlString: meta.logoURL, symbol: meta.symbol)
                    .frame(width: Layout.iconSize, height: Layout.iconSize)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: meta.symbol).font(.system(size: 13, weight: .medium))
                    Text(verbatim: meta.name).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: added ? (hovered ? "minus.circle.fill" : "checkmark.circle.fill") : "plus.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(added ? (hovered ? Color.red : Color.green) : Color.accentColor)
                    .opacity(added || hovered ? 1 : 0.55)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Layout.rowCornerRadius, style: .continuous)
                    .fill(hovered ? (added ? Color.red : Color.accentColor).opacity(0.12) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Layout.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hoveredID = meta.id
            } else if hoveredID == meta.id {
                hoveredID = nil
            }
        }
        .accessibilityLabel(Text(verbatim: "\(meta.symbol), \(meta.name)"))
        .accessibilityAddTraits(added ? .isSelected : [])
    }
}
