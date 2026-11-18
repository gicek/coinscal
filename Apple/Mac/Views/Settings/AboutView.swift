import SwiftUI

struct AboutView: View {
    private let openSourceComponents: [(name: String, license: String, url: String)] = [
        ("Sparkle", "MIT License", "https://github.com/sparkle-project/Sparkle"),
    ]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image("app-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Coinscal")
                            .font(.title2)
                            .bold()
                        Text(String(format: loc("about.version"), Constants.appVersion))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(loc("about.slogan"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(loc("about.section.contact")) {
                AboutContactLinks()
            }

            Section(loc("about.section.dataSources")) {
                Label(loc("about.dataSource.price"), systemImage: "chart.line.uptrend.xyaxis")
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("about.dataSource.exchangeRate"))
                        // Required wording, kept in English in every language.
                        Link(destination: Constants.Attribution.exchangeRateAPIURL) {
                            Text(verbatim: Constants.Attribution.exchangeRateAPIText)
                        }
                        .font(.caption)
                    }
                } icon: {
                    Image(systemName: "dollarsign.arrow.circlepath")
                }
                // CoinGecko's free data terms require attribution (coin names, logos and ranks come from it).
                Label(loc("about.dataSource.coinInfo"), systemImage: "list.bullet")
            }

            if !openSourceComponents.isEmpty {
                Section(loc("about.section.opensource")) {
                    ForEach(openSourceComponents, id: \.name) { component in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: component.name)
                                Text(verbatim: component.license)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let url = URL(string: component.url) {
                                Link(loc("about.opensource.view"), destination: url)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Contact rows on the About page: email and the X account.
struct AboutContactLinks: View {
    /// Same icon column width for every row so the texts line up.
    private static let iconWidth: CGFloat = 18

    var body: some View {
        // One form row per link.
        Group {
            Link(destination: Constants.Contact.emailURL) {
                Label {
                    Text(verbatim: Constants.Contact.email)
                } icon: {
                    Image(systemName: "envelope")
                        .frame(width: Self.iconWidth)
                }
            }
            .accessibilityLabel("\(loc("about.contact.email")) \(Constants.Contact.email)")

            Link(destination: Constants.Contact.xURL) {
                Label {
                    Text(verbatim: "@\(Constants.Contact.xHandle)")
                } icon: {
                    // SF Symbols has no X logo; the asset is a template image that follows the text color.
                    Image("brand-x")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .frame(width: Self.iconWidth)
                }
            }
            .accessibilityLabel("X @\(Constants.Contact.xHandle)")
        }
    }
}
