import AppKit
import SwiftUI

/// Menu bar popover with the coin list: frosted rounded panel with quick actions in the footer.
/// Height follows the watchlist size: at least 4 rows, at most 8, then it scrolls.
struct CoinPopoverView: View {
    @EnvironmentObject var coinListVM: CoinListViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var updateController: UpdateController

    private enum Layout {
        static let cornerRadius: CGFloat = 12
        static let horizontalPadding: CGFloat = 16
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            coinList
            footer
        }
        .frame(
            width: Constants.Popover.width,
            height: Constants.Popover.height(forCoinCount: coinListVM.coins.count)
        )
        .background {
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(verbatim: "Coinscal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if coinListVM.isLoading {
                ProgressView()
                    .scaleEffect(0.72)
                    .controlSize(.small)
            }
            if updateController.updateAvailable {
                updateButton
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .frame(height: Constants.Popover.headerHeight)
    }

    /// A scheduled check found an update without opening a window; this opens Sparkle's update window.
    private var updateButton: some View {
        Button(action: { updateController.checkForUpdates() }) {
            Label(loc("popover.updateAvailable"), systemImage: "arrow.down.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .help(loc("popover.updateAvailable.help"))
    }

    @ViewBuilder
    private var coinList: some View {
        if coinListVM.coins.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(coinListVM.coins) { coin in
                        CoinRowView(coin: coin)
                            .environmentObject(settingsVM)
                    }
                }
            }
            // No scroll bar even with "Show scroll bars: Always"; the list still scrolls.
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bitcoinsign.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(loc("popover.empty"))
                .foregroundStyle(.secondary)
            Button(loc("popover.addCoins")) { navigate(to: .watchlist) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Footer: settings, manage watchlist, quit.
    private var footer: some View {
        HStack(spacing: 0) {
            Button(action: { navigate(to: .general) }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 32, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(loc("popover.settings.help"))

            Spacer(minLength: 12)

            Button(action: { navigate(to: .watchlist) }) {
                Text(loc("popover.watchlist"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    }
            }
            .buttonStyle(.plain)
            .help(loc("popover.watchlist.help"))

            Spacer(minLength: 12)

            Button(action: { quitApp() }) {
                Image(systemName: "power")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 32, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .help(loc("popover.quit"))
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .frame(height: Constants.Popover.footerHeight)
    }

    private func navigate(to tab: SettingsTab) {
        NotificationCenter.default.post(
            name: .coinscalNavigate,
            object: nil,
            userInfo: ["tab": tab.rawValue]
        )
    }

    private func quitApp() {
        NSApp.terminate(nil)
    }
}
