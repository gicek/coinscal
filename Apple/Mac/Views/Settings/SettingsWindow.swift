import SwiftUI
import AppKit

/// Settings window: native NavigationSplitView sidebar (fixed width, not collapsible or resizable).
/// No custom background; light and dark mode are left to the system sidebar material and window background.
/// The detail title is bridged to the window's unified toolbar (see AppDelegate), so every pane gets the same
/// title bar height, the title follows the selected pane, and scrolled content slides under the bar.
struct SettingsWindow: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var coinListVM: CoinListViewModel
    @State private var selectedTab: SettingsTab = .general
    @State private var showAddCoin = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            // No explicit fill: all panes share the system window background (the grouped Form's background shows through).
            detailContent
                .navigationTitle(selectedTab.title)
                .toolbar {
                    // The "+" stays in the toolbar on every pane, hidden outside Watchlist. When the bridged toolbar
                    // has no items (a pane-local toolbar, or an item with empty content) SwiftUI removes the window
                    // toolbar, the title bar falls back to a short centred one and the sidebar shifts down.
                    if #available(macOS 26.0, *) {
                        ToolbarItem(placement: .primaryAction) {
                            addCoinButton
                        }
                        // The glass platter is drawn by the toolbar, not the button, so hiding the button leaves it.
                        .sharedBackgroundVisibility(selectedTab == .watchlist ? .automatic : .hidden)
                    } else {
                        ToolbarItem(placement: .primaryAction) {
                            addCoinButton
                        }
                    }
                }
        }
        .frame(
            minWidth: Constants.Window.settingsMinSize.width,
            minHeight: Constants.Window.settingsMinSize.height
        )
        .onAppear {
            selectedTab = settingsVM.settingsWindowTab
        }
        .onChange(of: selectedTab) { _, tab in
            guard settingsVM.settingsWindowTab != tab else { return }
            DispatchQueue.main.async {
                settingsVM.settingsWindowTab = tab
            }
        }
        .onChange(of: settingsVM.settingsWindowTab) { _, tab in
            guard selectedTab != tab else { return }
            selectedTab = tab
        }
    }

    private var addCoinButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                showAddCoin.toggle()
            }
        } label: {
            Label(loc("watchlist.addCoin"), systemImage: "plus")
        }
        .help(loc("watchlist.addCoin"))
        .opacity(selectedTab == .watchlist ? 1 : 0)
        .disabled(selectedTab != .watchlist)
        .accessibilityHidden(selectedTab != .watchlist)
    }

    private var sidebar: some View {
        List(selection: $selectedTab) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
        }
        .listStyle(.sidebar)
        // The bridged toolbar would add a collapse button; the sidebar stays fixed.
        .toolbar(removing: .sidebarToggle)
        // Fixed column width: the sidebar cannot be resized.
        .navigationSplitViewColumnWidth(Constants.Window.settingsSidebarIdealWidth)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .general:
            // The grouped Form brings its own padding and background; no extra padding.
            GeneralSettingsView()
                .environmentObject(settingsVM)
                .environmentObject(coinListVM)
        case .watchlist:
            WatchlistView(showAddCoin: $showAddCoin)
                .environmentObject(settingsVM)
                .environmentObject(coinListVM)
                .padding(Constants.Window.settingsContentPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .about:
            // Pads its own content inside the scroll view (outer padding would clip scrolled content 24pt below the bar).
            AboutView()
                .environmentObject(settingsVM)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension SettingsTab: Hashable {
    @MainActor
    var title: String {
        switch self {
        case .general:   return loc("nav.general")
        case .watchlist: return loc("nav.watchlist")
        case .about:     return loc("nav.about")
        }
    }

    var systemImage: String {
        switch self {
        case .general:   return "gear"
        case .watchlist: return "bitcoinsign.circle"
        case .about:     return "info.circle"
        }
    }
}
