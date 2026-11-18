import SwiftUI

/// General pane: app behavior, prices, and updates. Menu bar and desktop options live in `DisplaySettingsView`.
struct GeneralSettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var updateController: UpdateController

    var body: some View {
        Form {
            Section {
                Toggle(loc("general.launch.atLogin"), isOn: Binding(
                    get: { settingsVM.settings.launchAtLogin },
                    set: { newVal in
                        settingsVM.settings.launchAtLogin = newVal
                        LaunchAtLoginService.shared.setEnabled(newVal)
                    }
                ))

                SettingsPickerRow(loc("general.language.label")) {
                    Picker(loc("general.language.label"), selection: $settingsVM.settings.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                }
            }

            // Applies to the menu bar, panel, desktop ticker, widgets, and alerts.
            Section(loc("general.section.prices")) {
                SettingsPickerRow(loc("general.display.currency")) {
                    Picker(loc("general.display.currency"), selection: $settingsVM.settings.baseCurrency) {
                        ForEach(BaseCurrency.allCases) { currency in
                            Text(currency.displayName).tag(currency)
                        }
                    }
                }

                SettingsPickerRow(loc("general.display.priceChangeBasis")) {
                    Picker(loc("general.display.priceChangeBasis"), selection: $settingsVM.settings.priceChangeBasis) {
                        ForEach(PriceChangeBasis.allCases, id: \.self) { basis in
                            Text(loc(basis.titleKey)).tag(basis)
                        }
                    }
                    .id(settingsVM.settings.language)
                }
            }

            Section(loc("general.section.updates")) {
                Toggle(loc("general.updates.automatic"), isOn: Binding(
                    get: { updateController.automaticallyChecksForUpdates },
                    set: { updateController.setAutomaticallyChecksForUpdates($0) }
                ))
                .disabled(!updateController.isAvailable)

                Toggle(loc("general.updates.autoInstall"), isOn: Binding(
                    get: { updateController.automaticallyInstallsUpdates },
                    set: { updateController.setAutomaticallyInstallsUpdates($0) }
                ))
                .disabled(!updateController.canAutomaticallyInstallUpdates)

                HStack {
                    Text(String(format: loc("about.version"), Constants.appVersion))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Button(loc("menu.checkForUpdates")) {
                        updateController.checkForUpdates()
                    }
                    .disabled(!updateController.canCheckForUpdates)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A form row with a label on the left and a menu picker of fixed width on the right.
struct SettingsPickerRow<Content: View>: View {
    private let label: String
    private let width: CGFloat
    private let content: Content

    init(_ label: String, width: CGFloat = 220, @ViewBuilder content: () -> Content) {
        self.label = label
        self.width = width
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            content
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: width, alignment: .trailing)
        }
    }
}
