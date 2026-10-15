import SwiftUI

struct CoinLogoView: View {
    let assetName: String?
    let urlString: String?
    let symbol: String

    var body: some View {
        Group {
            if let assetName, !assetName.isEmpty {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
        }
        .clipShape(Circle())
    }

    private var fallbackView: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.15))
            Text(String(symbol.prefix(3)))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
    }
}
