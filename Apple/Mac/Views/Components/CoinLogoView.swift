import SwiftUI

/// Coin logo: bundled asset → logo cached by `CoinLogoStore` (watchlist coins) → remote URL (e.g. browsing the
/// add-coin panel) → symbol placeholder.
struct CoinLogoView: View {
    let coinID: String
    let assetName: String?
    let urlString: String?
    let symbol: String

    @Environment(\.coinLogoStore) private var logoStore

    var body: some View {
        Group {
            if let assetName, !assetName.isEmpty {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else if let logoStore {
                CachedCoinLogo(store: logoStore, coinID: coinID, urlString: urlString, symbol: symbol)
            } else {
                RemoteCoinLogo(urlString: urlString, symbol: symbol)
            }
        }
        .clipShape(Circle())
    }
}

extension EnvironmentValues {
    /// Injected at the popover and Settings window roots; nil (previews, tests) skips the local cache.
    var coinLogoStore: CoinLogoStore? {
        get { self[CoinLogoStoreKey.self] }
        set { self[CoinLogoStoreKey.self] = newValue }
    }
}

private struct CoinLogoStoreKey: EnvironmentKey {
    static let defaultValue: CoinLogoStore? = nil
}

/// Observes the store so a logo downloaded after the coin was added replaces the remote image or placeholder.
private struct CachedCoinLogo: View {
    @ObservedObject var store: CoinLogoStore
    let coinID: String
    let urlString: String?
    let symbol: String

    var body: some View {
        if let image = store.image(for: coinID) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            RemoteCoinLogo(urlString: urlString, symbol: symbol)
        }
    }
}

private struct RemoteCoinLogo: View {
    let urlString: String?
    let symbol: String

    var body: some View {
        if let url = CoinLogoStore.allowedURL(urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    CoinLogoPlaceholder(symbol: symbol)
                }
            }
        } else {
            CoinLogoPlaceholder(symbol: symbol)
        }
    }
}

private struct CoinLogoPlaceholder: View {
    let symbol: String

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.15))
            Text(verbatim: String(symbol.prefix(3)))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
    }
}
