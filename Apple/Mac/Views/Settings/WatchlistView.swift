import SwiftUI

struct WatchlistView: View {
    /// Recommended coins row: icon size, spacing and padding.
    private enum RecommendedCoinsLayout {
        static let iconSize: CGFloat = 28
        static let rowItemSpacing: CGFloat = 10
        static let cardPadding: CGFloat = 6
        /// Vertical gap between the caption and the icon row.
        static let captionToRowSpacing: CGFloat = 4
        /// Vertical padding of the icon row (keeps the height tight to the content).
        static let rowVerticalPadding: CGFloat = 0
    }

    /// Add-coin panel: how far it reaches into the content padding (leaving an 8pt margin to the title bar and window edge).
    private enum AddCoinPanelLayout {
        static let contentInset: CGFloat = Constants.Window.settingsContentPadding - 8
    }

    /// Added-coins list column widths (drag handle, alert picker + value, delete), aligned with the header.
    private enum WatchlistListLayout {
        static let dragHandleColumnWidth: CGFloat = 20
        static let deleteColumnWidth: CGFloat = 28
        static let alertColumnWidth: CGFloat = 220
    }

    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var coinListVM: CoinListViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var vm: WatchlistViewModel
    @StateObject private var reorderSession = WatchlistReorderSession()
    @FocusState private var focusedReorderID: String?
    /// Owned by `SettingsWindow`, which hosts the "+" toolbar button (see the note there).
    @Binding var showAddCoin: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            recommendedCoins
            watchlistSection
        }
        .overlay {
            // Click-away layer: any click outside the panel closes it (covers the content padding too).
            if showAddCoin {
                Color.clear
                    .contentShape(Rectangle())
                    .padding(-Constants.Window.settingsContentPadding)
                    .onTapGesture { setAddCoinShown(false) }
            }
        }
        .overlay(alignment: .topTrailing) {
            if showAddCoin {
                WatchlistAddCoinPanel(
                    isAdded: isAdded,
                    toggle: toggleCoin,
                    close: { setAddCoinShown(false) }
                )
                // Pull the card out of the content padding: just below the title bar, right edge inside the window.
                .padding(.top, -AddCoinPanelLayout.contentInset)
                .padding(.trailing, -AddCoinPanelLayout.contentInset)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing))
                )
            }
        }
        .onChange(of: showAddCoin) { _, shown in
            if !shown { vm.searchText = "" }
        }
        .onDisappear {
            showAddCoin = false
            reorderSession.cancel()
        }
    }

    private func setAddCoinShown(_ shown: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            showAddCoin = shown
        }
    }

    /// Recommended coins: one row of icons, scrolling horizontally when it overflows. Tapping toggles add/remove.
    private var recommendedCoins: some View {
        VStack(alignment: .leading, spacing: RecommendedCoinsLayout.captionToRowSpacing) {
            Text(loc("watchlist.recommended"))
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .center, spacing: RecommendedCoinsLayout.rowItemSpacing) {
                    ForEach(vm.recommendedCoins, id: \.id) { meta in
                        recommendedCoinTile(meta)
                    }
                }
                .padding(.vertical, RecommendedCoinsLayout.rowVerticalPadding)
            }
            // A horizontal ScrollView on macOS tends to take all vertical space; size it to its content.
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Recommended coin tile: light fill when not added; accent border plus a check badge when added (same size).
    private func recommendedCoinTile(_ meta: CoinMetadata) -> some View {
        let added = isAdded(meta)
        return Button(action: { toggleCoin(meta) }) {
            CoinLogoView(coinID: meta.id, assetName: meta.logoAssetName, urlString: meta.logoURL, symbol: meta.symbol)
                .frame(width: RecommendedCoinsLayout.iconSize, height: RecommendedCoinsLayout.iconSize)
                .padding(RecommendedCoinsLayout.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(added ? Color.accentColor.opacity(0.16) : Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            added ? Color.accentColor : Color.primary.opacity(0.08),
                            lineWidth: added ? 1.5 : 1
                        )
                )
                .overlay(alignment: .topTrailing) {
                    if added {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.accentColor)
                            .padding(2)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.15), value: added)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(meta.symbol)
        .accessibilityAddTraits(added ? .isSelected : [])
    }

    private func toggleCoin(_ meta: CoinMetadata) {
        reorderSession.cancel()
        if isAdded(meta) {
            vm.removeCoin(meta.id, from: &settingsVM.settings)
        } else {
            vm.addCoin(meta, to: &settingsVM.settings)
        }
        reloadCoinData()
    }

    private var watchlistSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                    .frame(width: WatchlistListLayout.dragHandleColumnWidth)
                Text(loc("watchlist.added"))
                    .font(.headline)
                Spacer()
                Text(loc("watchlist.alert"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: WatchlistListLayout.alertColumnWidth, alignment: .center)
                Spacer(minLength: 0)
                    .frame(width: WatchlistListLayout.deleteColumnWidth)
            }
            .padding(.vertical, 10)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            if settingsVM.settings.watchlistCoins.isEmpty {
                Text(loc("watchlist.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(40)
            } else {
                reorderableList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Display rows = watchlist coins with resolved metadata; the index is the geometric slot used by reordering.
    private var watchlistRows: [(coin: WatchlistCoin, meta: CoinMetadata)] {
        settingsVM.settings.watchlistCoins.compactMap { coin in
            vm.metadata(for: coin.coinId).map { (coin, $0) }
        }
    }

    private var reorderableList: some View {
        let rows = watchlistRows
        let displayedIDs = rows.map(\.coin.coinId)

        return ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.coin.coinId) { index, row in
                            listRow(
                                row.coin,
                                meta: row.meta,
                                context: WatchlistRowReorderContext(
                                    index: index,
                                    displayedIDs: displayedIDs,
                                    viewportHeight: viewport.size.height,
                                    proxy: proxy
                                )
                            )
                        }
                    }
                    // Keep writing back the scroll offset; during a drag it maps viewport coordinates to content slots.
                    .onGeometryChange(for: CGFloat.self) { content in
                        -content.frame(in: .named(WatchlistReorderSession.coordinateSpaceName)).minY
                    } action: { offset in
                        reorderSession.updateScrollOffset(offset)
                    }
                }
                // No scroll bar even with "Show scroll bars: Always"; scrolling and drag auto-scroll still work.
                .scrollIndicators(.never)
                .coordinateSpace(name: WatchlistReorderSession.coordinateSpaceName)
                .overlay(alignment: .topLeading) {
                    floatingRow(width: viewport.size.width)
                }
            }
        }
    }

    private func listRow(
        _ watchlistCoin: WatchlistCoin,
        meta: CoinMetadata,
        context: WatchlistRowReorderContext
    ) -> some View {
        watchlistCoinRow(watchlistCoin, meta: meta, reorderContext: context)
            .frame(height: WatchlistReorderSession.rowHeight)
            // Normally the same system window background as the detail pane.
            .watchlistRowBackground()
            .overlay(alignment: .bottom) { Divider() }
            // Make room for the gap: rows shift with the insertion slot, animated inside the session.
            .offset(y: reorderSession.offset(forRowAt: context.index))
            // The source row stays in place as an empty gap while dragging (the floating row is an overlay).
            .opacity(reorderSession.draggedID == watchlistCoin.coinId ? 0 : 1)
            .id(watchlistCoin.coinId)
    }

    /// Floating row while dragging: the real row view with a fixed height and a lifted look.
    @ViewBuilder
    private func floatingRow(width: CGFloat) -> some View {
        if let draggedID = reorderSession.draggedID,
           let row = watchlistRows.first(where: { $0.coin.coinId == draggedID }) {
            watchlistCoinRow(row.coin, meta: row.meta, reorderContext: nil)
                .frame(width: width, height: WatchlistReorderSession.rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.windowBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 9, y: 4)
                .offset(y: reorderSession.floatingY)
                .allowsHitTesting(false)
                .transition(.identity)
        }
    }

    private func watchlistCoinRow(
        _ watchlistCoin: WatchlistCoin,
        meta: CoinMetadata,
        reorderContext: WatchlistRowReorderContext?
    ) -> some View {
        let currency = settingsVM.settings.baseCurrency
        let currentCoin = coinListVM.coins.first { $0.id == watchlistCoin.coinId }
        let displayedPrice = coinListVM.priceDataCurrency == currency ? currentCoin?.currentPrice : nil
        let rate = coinListVM.usdExchangeRate(for: currency)

        return HStack {
            dragHandle(for: watchlistCoin, reorderContext: reorderContext)
            CoinLogoView(coinID: meta.id, assetName: meta.logoAssetName, urlString: meta.logoURL, symbol: meta.symbol)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.symbol).font(.system(size: 13, weight: .medium))
                if meta.status != .active {
                    coinStatusLine
                } else if let price = displayedPrice {
                    Text(PriceFormatter.format(price, currency: settingsVM.settings.baseCurrency))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            WatchlistAlertControls(
                kind: alertKindBinding(
                    for: watchlistCoin.coinId,
                    currentPrice: displayedPrice,
                    usdToTargetRate: rate
                ),
                value: thresholdBinding(for: watchlistCoin.coinId, currency: currency),
                usdToTargetRate: rate
            )
            .id(currency)
            .frame(width: WatchlistListLayout.alertColumnWidth, alignment: .center)

            // Remove this coin (same logic as the view model, which also fixes the menu bar coin).
            Button(action: {
                reorderSession.cancel()
                vm.removeCoin(watchlistCoin.coinId, from: &settingsVM.settings)
                reloadCoinData()
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: WatchlistListLayout.deleteColumnWidth, alignment: .center)
            .accessibilityLabel(loc("watchlist.delete"))
        }
    }

    /// Shown under a coin that has no market.
    private var coinStatusLine: some View {
        Text(loc("coin.status.delisted"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func dragHandle(
        for watchlistCoin: WatchlistCoin,
        reorderContext: WatchlistRowReorderContext?
    ) -> some View {
        let focused = reorderContext != nil && focusedReorderID == watchlistCoin.coinId
        let handle = Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(
                focused || reorderSession.draggedID == watchlistCoin.coinId
                    ? Color.accentColor
                    : Color.primary.opacity(0.28)
            )
            .frame(width: 16, height: 18)
            .background {
                if focused {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor, lineWidth: 1)
                }
            }
            .frame(width: WatchlistListLayout.dragHandleColumnWidth)
            .frame(maxHeight: .infinity)
            .accessibilityLabel(loc("watchlist.reorder"))

        if let reorderContext {
            handle
                .contentShape(Rectangle())
                .gesture(reorderGesture(for: watchlistCoin, context: reorderContext))
                .focusable()
                .focused($focusedReorderID, equals: watchlistCoin.coinId)
                .focusEffectDisabled()
                .onMoveCommand { direction in
                    switch direction {
                    case .up: moveCoin(in: reorderContext, by: -1)
                    case .down: moveCoin(in: reorderContext, by: 1)
                    default: break
                    }
                }
                .accessibilityActions {
                    if reorderContext.index > 0 {
                        Button(loc("watchlist.moveUp")) { moveCoin(in: reorderContext, by: -1) }
                    }
                    if reorderContext.index + 1 < reorderContext.displayedIDs.count {
                        Button(loc("watchlist.moveDown")) { moveCoin(in: reorderContext, by: 1) }
                    }
                }
                .onHover { hovering in
                    if hovering {
                        NSCursor.openHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        } else {
            // The handle in the floating row is display-only.
            handle
        }
    }

    private func moveCoin(in context: WatchlistRowReorderContext, by offset: Int) {
        var ids = context.displayedIDs
        let destination = context.index + offset
        guard ids.indices.contains(destination) else { return }
        reorderSession.cancel()
        ids.swapAt(context.index, destination)
        applyWatchlistOrder(ids)
    }

    private func reorderGesture(
        for watchlistCoin: WatchlistCoin,
        context: WatchlistRowReorderContext
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 2,
            coordinateSpace: .named(WatchlistReorderSession.coordinateSpaceName)
        )
        .onChanged { value in
            if !reorderSession.isActive {
                // If a threshold is being edited, end editing and commit before picking up the row.
                NSApp.keyWindow?.makeFirstResponder(nil)
                reorderSession.begin(
                    id: watchlistCoin.coinId,
                    index: context.index,
                    orderIDs: context.displayedIDs,
                    viewportHeight: context.viewportHeight,
                    location: value.location,
                    reduceMotion: reduceMotion,
                    proxy: context.proxy,
                    commit: applyWatchlistOrder
                )
            }
            reorderSession.update(location: value.location)
        }
        .onEnded { _ in
            reorderSession.end()
        }
    }

    private func applyWatchlistOrder(_ orderedIDs: [String]) {
        let current = settingsVM.settings.watchlistCoins
        let coinByID = Dictionary(uniqueKeysWithValues: current.map { ($0.coinId, $0) })
        var reordered = orderedIDs.compactMap { coinByID[$0] }
        // Coins without metadata (not displayed) keep their relative order at the end so none are lost.
        let seen = Set(reordered.map(\.coinId))
        reordered.append(contentsOf: current.filter { !seen.contains($0.coinId) })
        guard reordered.count == current.count,
              reordered.map(\.coinId) != current.map(\.coinId) else { return }

        // One array assignment means one UserDefaults save; hovering during a drag never touches the settings.
        settingsVM.settings.watchlistCoins = reordered
        reloadCoinData()
    }

    private func alertKindBinding(for coinId: String, currentPrice: Double?, usdToTargetRate: Double?) -> Binding<CoinAlertKind> {
        Binding(
            get: { settingsVM.settings.watchlistCoins.first(where: { $0.coinId == coinId })?.alertKind ?? .notSet },
            set: { newKind in
                guard let i = settingsVM.settings.watchlistCoins.firstIndex(where: { $0.coinId == coinId }) else { return }
                var rule = settingsVM.settings.watchlistCoins[i]
                guard rule.alertKind != newKind else { return }
                rule.alertKind = newKind
                switch newKind {
                case .notSet:
                    rule.notificationThreshold = 0
                case .change:
                    rule.notificationThreshold = Constants.Defaults.defaultNotificationThreshold
                case .above, .below:
                    if let price = currentPrice, let rate = usdToTargetRate {
                        let multiplier = newKind == .above ? 1.02 : 0.98
                        let amountUSD = PriceFormatter.alertUsdAmount(fromDisplay: price * multiplier, usdToTargetRate: rate)
                        rule.notificationThreshold = AlertEvaluator.clampAlertThreshold(amountUSD, kind: newKind)
                    } else {
                        rule.notificationThreshold = AlertEvaluator.clampAlertThreshold(rule.notificationThreshold, kind: newKind)
                    }
                }
                settingsVM.settings.watchlistCoins[i] = rule
            }
        )
    }

    private func thresholdBinding(for coinId: String, currency: BaseCurrency) -> Binding<Double> {
        Binding(
            get: {
                settingsVM.settings.watchlistCoins.first(where: { $0.coinId == coinId })?.notificationThreshold
                    ?? Constants.Defaults.defaultNotificationThreshold
            },
            set: { value in
                guard settingsVM.settings.baseCurrency == currency,
                      let i = settingsVM.settings.watchlistCoins.firstIndex(where: { $0.coinId == coinId }) else { return }
                let kind = settingsVM.settings.watchlistCoins[i].alertKind
                let threshold = AlertEvaluator.clampAlertThreshold(value, kind: kind)
                if settingsVM.settings.watchlistCoins[i].notificationThreshold != threshold {
                    settingsVM.settings.watchlistCoins[i].notificationThreshold = threshold
                }
            }
        )
    }

    private func isAdded(_ meta: CoinMetadata) -> Bool {
        settingsVM.settings.watchlistCoins.contains(where: { $0.coinId == meta.id })
    }

    private func reloadCoinData() {
        // Reload only after adding or removing coins, so editing a threshold does not restart price polling.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            coinListVM.reloadAfterSettingsChange()
        }
    }
}

/// Geometry and commit context a row needs for drag reordering; nil for the floating copy.
struct WatchlistRowReorderContext {
    let index: Int
    let displayedIDs: [String]
    let viewportHeight: CGFloat
    let proxy: ScrollViewProxy
}

private extension View {
    /// Row background: `.windowBackground` always matches the system window background (including the
    /// macOS 26 material), blends in normally and is opaque while dragging; macOS 13 uses the flat window color.
    @ViewBuilder
    func watchlistRowBackground() -> some View {
        if #available(macOS 14.0, *) {
            background(.windowBackground)
        } else {
            background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

// MARK: - Alert (kind + value)

private struct WatchlistAlertControls: View {
    @Binding var kind: CoinAlertKind
    @Binding var value: Double
    var usdToTargetRate: Double?

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $kind) {
                ForEach(CoinAlertKind.allCases) { k in
                    Text(k.menuTitle).tag(k)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 88, alignment: .leading)

            WatchlistAlertNumberField(
                kind: kind,
                value: $value,
                usdToTargetRate: usdToTargetRate
            )
            .frame(minWidth: 72, maxWidth: .infinity)
        }
    }
}

/// Change shows % inside the box. Absolute thresholds need a rate for the selected currency.
private struct WatchlistAlertNumberField: View {
    let kind: CoinAlertKind
    @Binding var value: Double
    var usdToTargetRate: Double?

    @State private var text: String = ""
    @State private var isEditing = false
    @State private var fieldProxy = AlertFieldProxy()

    @State private var originalText: String?
    @State private var editingRate: Double?
    @State private var editingKind: CoinAlertKind?

    private var inputRate: Double? {
        switch kind {
        case .notSet: nil
        case .change: 1
        case .above, .below: usdToTargetRate
        }
    }

    var body: some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            // A click anywhere in the box bypasses SwiftUI focus and makes the AppKit field first responder directly.
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onTapGesture {
                guard inputRate != nil else { return }
                fieldProxy.beginEditing()
            }
            .onAppear { syncFromValue() }
            .onChange(of: value) {
                if !isEditing { syncFromValue() }
            }
            .onChange(of: kind) { syncFromValue() }
            .onChange(of: usdToTargetRate) {
                if !isEditing { syncFromValue() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .notSet:
            Text(verbatim: "—")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .change:
            HStack(spacing: 4) {
                alertValueTextField
                Text(verbatim: "%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        case .above, .below:
            if inputRate != nil {
                alertValueTextField
            } else {
                Text(verbatim: "—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help(loc("watchlist.thresholdRateUnavailable"))
                    .accessibilityLabel(loc("watchlist.thresholdRateUnavailable"))
            }
        }
    }

    /// AppKit NSTextField wrapper: an unfocused SwiftUI plain TextField only hit-tests near its text,
    /// while NSTextField focuses on a click anywhere in its frame.
    private var alertValueTextField: some View {
        AlertValueNSTextField(
            text: $text,
            isEditing: $isEditing,
            proxy: fieldProxy,
            onBegin: {
                originalText = text
                editingRate = inputRate
                editingKind = kind
            },
            onCommit: commit
        )
        .frame(maxWidth: .infinity)
    }

    private func syncFromValue() {
        text = inputRate.map { PriceFormatter.formatAlertAmount(value * $0) } ?? ""
    }

    private func commit() {
        defer {
            originalText = nil
            editingRate = nil
            editingKind = nil
            syncFromValue()
        }
        guard let originalText, text != originalText, editingKind == kind, let editingRate,
              let amount = PriceFormatter.parseAlertAmount(text) else { return }
        if kind == .change || amount > 0 {
            value = PriceFormatter.alertUsdAmount(fromDisplay: amount, usdToTargetRate: editingRate)
        }
    }
}

/// Weak reference to the AppKit field so a SwiftUI tap gesture can call makeFirstResponder directly
/// (SwiftUI FocusState often fails silently inside List/NSTableView rows).
@MainActor
private final class AlertFieldProxy {
    weak var field: NSTextField?

    func beginEditing() {
        guard let field, let window = field.window else { return }
        if field.currentEditor() == nil {
            window.makeFirstResponder(field)
        }
    }
}

/// While not editing, the outer full-size tap gesture receives the first click; while editing, normal
/// hit-testing returns, so the whole box focuses and caret placement and selection still work.
private final class FullHitTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        currentEditor() != nil ? super.hitTest(point) : nil
    }
}

/// Borderless NSTextField wrapper: hit-tests its full frame, calls onCommit when editing ends (Return or focus loss).
private struct AlertValueNSTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let proxy: AlertFieldProxy
    var onBegin: () -> Void
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = FullHitTextField(string: text)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.alignment = .right
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        // Lowest priorities so it stretches to the available width inside the HStack.
        field.setContentHuggingPriority(.init(1), for: .horizontal)
        field.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        proxy.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        proxy.field = field
        // While editing the coordinator owns the text; sync from outside only when not editing so typing is not interrupted.
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
        }
    }

    /// NSViewRepresentable sizes to its intrinsic content (as wide as the text) by default;
    /// it must take the proposed width, otherwise only the text itself is clickable.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        return CGSize(
            width: proposal.width ?? intrinsic.width,
            height: intrinsic.height
        )
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AlertValueNSTextField

        init(_ parent: AlertValueNSTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onBegin()
            parent.isEditing = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isEditing = false
            parent.onCommit()
        }
    }
}
