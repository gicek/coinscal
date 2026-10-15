import Foundation
import Combine
import AppKit
import SwiftUI

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var statusTitle: String = "BTC --"
    @Published var statusColor: NSColor = .labelColor

    private weak var statusItem: NSStatusItem?
    /// Loaded once. Whether the logo is showing is decided by identity, not by `button.image == nil`:
    /// after `image = nil`, NSStatusBarButton sometimes reports a 1×1 placeholder image instead (macOS 26).
    private lazy var menuBarLogo: NSImage? = {
        guard let image = NSImage(named: "menubar-logo") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
    private var cancellables = Set<AnyCancellable>()

    func bind(
        to coinListVM: CoinListViewModel,
        settingsVM: SettingsViewModel,
        statusItem: NSStatusItem
    ) {
        self.statusItem = statusItem

        Publishers.CombineLatest(
            coinListVM.$coins,
            settingsVM.$settings
        )
        .sink { [weak self] coins, settings in
            self?.updateStatusItem(coins: coins, settings: settings, settingsVM: settingsVM)
        }
        .store(in: &cancellables)
    }

    /// The coin whose price goes in the menu bar; nil means show the logo only
    /// (icon mode chosen, empty watchlist, or no price yet).
    static func priceCoin(coins: [Coin], settings: AppSettings) -> Coin? {
        guard settings.menuBarContent == .price else { return nil }
        guard let coin = coins.first(where: { $0.id == settings.displayedCoinId }) ?? coins.first,
              coin.currentPrice != nil else { return nil }
        return coin
    }

    private func updateStatusItem(coins: [Coin], settings: AppSettings, settingsVM: SettingsViewModel) {
        guard let displayedCoin = Self.priceCoin(coins: coins, settings: settings),
              let price = displayedCoin.currentPrice else {
            showLogoOnly()
            return
        }

        let priceText = PriceFormatter.formatShort(price)
        let title = "\(displayedCoin.symbol) \(priceText)"
        // With a background, pad the text with spaces for visual insets.
        let displayTitle = settings.showMenuBarBackground ? " \(title) " : title

        guard let button = statusItem?.button else { return }
        statusItem?.length = NSStatusItem.variableLength
        button.image = nil

        let priceColor = settingsVM.priceNSColor(changePercent: displayedCoin.priceChange24hPercent)
        let showBg = settings.showMenuBarBackground
        let showColor = settings.priceColorEnabled

        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        switch (showColor, showBg) {
        case (true, true):
            // Background = price color, text = white.
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white, .font: font]
            button.attributedTitle = NSAttributedString(string: displayTitle, attributes: attrs)
            button.layer?.backgroundColor = priceColor.cgColor
        case (true, false):
            // Text = price color, no background.
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: priceColor, .font: font]
            button.attributedTitle = NSAttributedString(string: displayTitle, attributes: attrs)
            button.layer?.backgroundColor = nil
        case (false, true):
            // Background = menu bar text color (white on a dark bar, black on a light one), text = inverted.
            let menuBarTextColor = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white : NSColor.black
            let textOnBg = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.black : NSColor.white
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: textOnBg, .font: font]
            button.attributedTitle = NSAttributedString(string: displayTitle, attributes: attrs)
            button.layer?.backgroundColor = menuBarTextColor.cgColor
        case (false, false):
            // Default style.
            button.attributedTitle = NSAttributedString()
            button.title = displayTitle
            button.layer?.backgroundColor = nil
        }

        button.wantsLayer = true
        if showBg {
            button.layer?.cornerRadius = 4
            button.layer?.masksToBounds = true
        } else {
            button.layer?.cornerRadius = 0
            button.layer?.masksToBounds = false
        }
    }

    /// Puts the logo on the button unless that exact image is already there (a placeholder does not count).
    static func applyLogo(_ logo: NSImage?, to button: NSButton) {
        guard let logo else { return }
        if button.image !== logo { button.image = logo }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
    }

    private func showLogoOnly() {
        guard let button = statusItem?.button else { return }

        Self.applyLogo(menuBarLogo, to: button)
        statusItem?.length = 28
        button.attributedTitle = NSAttributedString()
        button.title = ""
        button.layer?.backgroundColor = nil
        button.layer?.cornerRadius = 0
        button.layer?.masksToBounds = false
    }
}
