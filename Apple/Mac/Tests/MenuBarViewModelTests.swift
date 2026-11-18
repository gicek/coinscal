import AppKit
import Testing
@testable import Coinscal

@MainActor
@Suite struct MenuBarViewModelTests {
    private func coin(_ id: String, price: Double?) -> Coin {
        Coin(id: id, symbol: id.uppercased(), name: id, rank: nil, logoAssetName: nil, logoURL: nil, currentPrice: price)
    }

    private func settings(_ content: MenuBarContent, displayed: String = "bitcoin") -> AppSettings {
        var settings = AppSettings()
        settings.menuBarContent = content
        settings.displayedCoinId = displayed
        return settings
    }

    @Test func priceModeShowsDisplayedCoin() {
        let coins = [coin("bitcoin", price: 65_000), coin("ethereum", price: 3_000)]
        #expect(MenuBarViewModel.priceCoin(coins: coins, settings: settings(.price, displayed: "ethereum"))?.id == "ethereum")
    }

    @Test func iconModeShowsLogoEvenWithPrice() {
        let coins = [coin("bitcoin", price: 65_000)]
        #expect(MenuBarViewModel.priceCoin(coins: coins, settings: settings(.icon)) == nil)
    }

    @Test func priceModeFallsBackToLogoWithoutPrice() {
        #expect(MenuBarViewModel.priceCoin(coins: [coin("bitcoin", price: nil)], settings: settings(.price)) == nil)
        #expect(MenuBarViewModel.priceCoin(coins: [], settings: settings(.price)) == nil, "empty watchlist")
    }

    @Test func missingDisplayedCoinFallsBackToFirst() {
        let coins = [coin("solana", price: 150)]
        #expect(MenuBarViewModel.priceCoin(coins: coins, settings: settings(.price, displayed: "bitcoin"))?.id == "solana")
    }

    /// Regression: after `image = nil` NSStatusBarButton can report a 1×1 placeholder image; the logo must still
    /// replace it, otherwise switching to icon mode leaves an empty item (price cleared, no logo).
    @Test func logoReplacesPlaceholderImage() {
        let logo = NSImage(size: NSSize(width: 18, height: 18))
        let button = NSButton()
        button.image = NSImage(size: NSSize(width: 1, height: 1))
        MenuBarViewModel.applyLogo(logo, to: button)
        #expect(button.image === logo)
        #expect(button.imagePosition == .imageOnly)
    }

    @Test func logoAppliesWhenButtonHasNoImage() {
        let logo = NSImage(size: NSSize(width: 18, height: 18))
        let button = NSButton()
        MenuBarViewModel.applyLogo(logo, to: button)
        #expect(button.image === logo)
    }

    @Test func filledAndPlainPricesShareTheSelectedColor() {
        let defaultGreen = NSColor(srgbRed: 28.0 / 255, green: 134.0 / 255, blue: 92.0 / 255, alpha: 1)
        for color in [defaultGreen, NSColor.systemYellow] {
            let plain = MenuBarTitleImage.Style.coloredPrice(color, showBackground: false)
            let badge = MenuBarTitleImage.Style.coloredPrice(color, showBackground: true)
            #expect(plain.textColor == color)
            #expect(plain.background == nil)
            #expect(badge.background == plain.textColor)
            #expect(badge.textColor == .white)
        }
    }
}
