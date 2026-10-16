import SwiftUI

struct AboutView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var updateController: UpdateController

    private let openSourceComponents: [(name: String, license: String, url: String)] = [
        ("Sparkle", "MIT License", "https://github.com/sparkle-project/Sparkle"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image("app-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Coinscal")
                            .font(.title)
                            .bold()
                        Text(String(format: loc("about.version"), Constants.appVersion))
                            .foregroundStyle(.secondary)
                        Text(loc("about.slogan"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text(loc("about.section.updates"))
                        .font(.headline)

                    Toggle(loc("about.updates.automatic"), isOn: Binding(
                        get: { updateController.automaticallyChecksForUpdates },
                        set: { updateController.setAutomaticallyChecksForUpdates($0) }
                    ))
                    .disabled(!updateController.isAvailable)

                    Button(loc("menu.checkForUpdates")) {
                        updateController.checkForUpdates()
                    }
                    .disabled(!updateController.canCheckForUpdates)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text(loc("about.section.contact"))
                        .font(.headline)

                    AboutContactLinks()
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text(loc("about.section.dataSources"))
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        Label(loc("about.dataSource.price"), systemImage: "chart.line.uptrend.xyaxis")
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("about.dataSource.exchangeRate"))
                                // Required wording, kept in English in every language.
                                Link(destination: Constants.Attribution.exchangeRateAPIURL) {
                                    Text(verbatim: Constants.Attribution.exchangeRateAPIText)
                                }
                                .font(.caption)
                                // The section is secondary-colored; keep the link looking like one.
                                .foregroundStyle(Color.accentColor)
                            }
                        } icon: {
                            Image(systemName: "dollarsign.arrow.circlepath")
                        }
                        // CoinGecko's free data terms require attribution (coin names, logos and ranks come from it).
                        Label(loc("about.dataSource.coinInfo"), systemImage: "list.bullet")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                if !openSourceComponents.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text(loc("about.section.opensource"))
                            .font(.headline)

                        ForEach(openSourceComponents, id: \.name) { component in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(verbatim: component.name).font(.callout)
                                    Text(verbatim: component.license).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let url = URL(string: component.url) {
                                    Link(loc("about.opensource.view"), destination: url)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            // Padding inside the scroll view: it starts right under the title bar and content scrolls under it.
            .padding(Constants.Window.settingsContentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Contact rows on the About page: email and the X account.
struct AboutContactLinks: View {
    /// Same icon column width for every row so the texts line up.
    private static let iconWidth: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
