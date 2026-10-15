import SwiftUI

/// One coin row in the popover; fixed height (Constants.Popover.rowHeight) so the popover height follows the row count.
struct CoinRowView: View {
    let coin: Coin
    @EnvironmentObject var settingsVM: SettingsViewModel

    var body: some View {
        HStack(spacing: 10) {
            CoinLogoView(
                assetName: coin.logoAssetName,
                urlString: coin.logoURL,
                symbol: coin.symbol
            )
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(coin.name)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    priceView
                }
                HStack {
                    Text(coin.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    changeView
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Constants.Popover.rowHeight)
    }

    private var priceView: some View {
        Group {
            if let price = coin.currentPrice {
                Text(PriceFormatter.format(price, currency: settingsVM.settings.baseCurrency, includeCurrencySymbol: false))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(settingsVM.priceColor(changePercent: coin.priceChange24hPercent))
            } else {
                Text(verbatim: "--")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var changeView: some View {
        Group {
            if coin.status != .active {
                Text(loc("coin.status.delisted"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let change = coin.priceChange24hPercent {
                Text(PriceFormatter.formatPercent(change))
                    .font(.caption)
                    .foregroundStyle(settingsVM.priceColor(changePercent: change))
            }
        }
    }
}
