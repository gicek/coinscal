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

    /// Keep white text readable by darkening light fills in linear sRGB.
    static func priceBadgeBackground(_ color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .black }
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let red = linear(rgb.redComponent)
        let green = linear(rgb.greenComponent)
        let blue = linear(rgb.blueComponent)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let maximumLuminance: CGFloat = 0.18
        guard luminance > maximumLuminance else { return color }

        let scale = maximumLuminance / luminance
        func encode(_ component: CGFloat) -> CGFloat {
            let value = component * scale
            return value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
        }
        return NSColor(srgbRed: encode(red), green: encode(green), blue: encode(blue), alpha: 1)
    }

    private func updateStatusItem(coins: [Coin], settings: AppSettings, settingsVM: SettingsViewModel) {
        guard let displayedCoin = Self.priceCoin(coins: coins, settings: settings),
              let price = displayedCoin.currentPrice else {
            showLogoOnly()
            return
        }

        let priceText = PriceFormatter.formatShort(price)
        let title = "\(displayedCoin.symbol) \(priceText)"

        guard let button = statusItem?.button else { return }
        statusItem?.length = NSStatusItem.variableLength
        button.layer?.backgroundColor = nil

        let priceColor = settingsVM.priceNSColor(changePercent: displayedCoin.priceChange24hPercent)
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let isDarkMenuBar = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let style: MenuBarTitleImage.Style
        switch (settings.priceColorEnabled, settings.showMenuBarBackground) {
        case (false, false):
            // Default style: a plain title the system draws and tints like other menu bar text.
            button.image = nil
            button.attributedTitle = NSAttributedString()
            button.title = title
            button.setAccessibilityLabel(nil)
            return
        case (true, true):
            style = .init(textColor: .white, background: Self.priceBadgeBackground(priceColor))
        case (true, false):
            // Text = price color, no background.
            style = .init(textColor: priceColor, background: nil)
        case (false, true):
            // Background = menu bar text color (white on a dark bar, black on a light one), text = inverted.
            style = .init(textColor: isDarkMenuBar ? .black : .white, background: isDarkMenuBar ? .white : .black)
        }
        // A colored title or a background is drawn into one image: the menu bar of an inactive display fades its
        // items, and an attributed title over a layer background then renders as blurred, heavier text.
        let height = button.bounds.height > 0 ? button.bounds.height : NSStatusBar.system.thickness
        button.attributedTitle = NSAttributedString()
        button.title = ""
        button.image = MenuBarTitleImage.make(text: title, font: font, style: style, height: height)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.setAccessibilityLabel(title)
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
        button.setAccessibilityLabel("Coinscal")
    }
}

/// The menu bar price as one non-template image: text, and optionally a rounded background behind it.
enum MenuBarTitleImage {
    struct Style {
        var textColor: NSColor
        var background: NSColor?
    }

    /// Space between the text and the edges of the background.
    static let horizontalPadding: CGFloat = 13
    static let cornerRadius: CGFloat = 4

    static func size(text: String, font: NSFont, style: Style, height: CGFloat) -> NSSize {
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return NSSize(width: textWidth + (style.background == nil ? 0 : horizontalPadding * 2), height: height)
    }

    static func make(text: String, font: NSFont, style: Style, height: CGFloat) -> NSImage {
        let size = size(text: text, font: font, style: style, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            if let background = style.background {
                background.setFill()
                NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: style.textColor]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let origin = NSPoint(x: (rect.width - textSize.width) / 2, y: ((rect.height - textSize.height) / 2).rounded())
            (text as NSString).draw(at: origin, withAttributes: attributes)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = text
        return image
    }
}
