import SwiftUI

/// Display pane: the menu bar item and the desktop ticker.
struct DisplaySettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var coinListVM: CoinListViewModel

    var body: some View {
        Form {
            menuBarSection
            desktopSection
        }
        .formStyle(.grouped)
    }

    private var menuBarSection: some View {
        Section(loc("general.section.menubar")) {
            HStack {
                Text(loc("general.display.menubarContent"))
                Spacer()
                Picker(loc("general.display.menubarContent"), selection: $settingsVM.settings.menuBarContent) {
                    ForEach(MenuBarContent.allCases) { content in
                        Text(content.displayName).tag(content)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220, alignment: .trailing)
                // Recreate NSSegmentedControl so its labels follow the app language.
                .id(settingsVM.settings.language)
            }

            // Keep dependent controls in place when switching the menu bar mode.
            Group {
                HStack(alignment: .firstTextBaseline) {
                    Text(loc("general.display.menubarCoin"))
                    Spacer()
                    if settingsVM.settings.watchlistCoins.isEmpty {
                        Text(loc("general.display.menubarCoin.hint"))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 220, alignment: .trailing)
                    } else {
                        Picker(loc("general.display.menubarCoin"), selection: $settingsVM.settings.displayedCoinId) {
                            ForEach(settingsVM.settings.watchlistCoins) { added in
                                Text(menuBarCoinLabel(for: added)).tag(added.coinId)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220, alignment: .trailing)
                    }
                }

                Toggle(loc("general.display.coinSymbol"), isOn: $settingsVM.settings.showMenuBarCoinSymbol)
                Toggle(loc("general.display.textColor"), isOn: $settingsVM.settings.priceColorEnabled)

                Group {
                    SettingsPickerRow(loc("general.display.colorScheme")) {
                        Picker(loc("general.display.colorScheme"), selection: $settingsVM.settings.colorScheme) {
                            ForEach(PriceColorScheme.allCases) { scheme in
                                Text(scheme.displayName).tag(scheme)
                            }
                        }
                        .id(settingsVM.settings.language)
                    }

                    if settingsVM.settings.colorScheme == .custom {
                        ColorPickerRow(label: loc("general.priceColor.upColor"), hexColor: $settingsVM.settings.customUpColorHex)
                        ColorPickerRow(label: loc("general.priceColor.downColor"), hexColor: $settingsVM.settings.customDownColorHex)
                    }
                }
                .disabled(!settingsVM.settings.priceColorEnabled)

                // The badge follows the price color, so it comes after the color options.
                Toggle(loc("general.display.textBackground"), isOn: $settingsVM.settings.showMenuBarBackground)
            }
            .disabled(settingsVM.settings.menuBarContent == .icon)
        }
    }

    private var desktopSection: some View {
        Section(loc("general.section.desktop")) {
            Toggle(loc("desktop.show"), isOn: $settingsVM.settings.desktopOverlayEnabled)

            Group {
                HStack {
                    Text(loc("desktop.textSize"))
                    Spacer()
                    Picker(loc("desktop.textSize"), selection: $settingsVM.settings.desktopOverlayTextSize) {
                        ForEach(DesktopOverlayTextSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 160, alignment: .trailing)
                    .id(settingsVM.settings.language)
                }

                HStack {
                    Text(loc("desktop.opacity"))
                    Spacer()
                    Slider(value: $settingsVM.settings.desktopOverlayBackgroundOpacity, in: 0...1)
                        .labelsHidden()
                        .frame(width: 176)
                    Text(verbatim: "\(Int((settingsVM.settings.desktopOverlayBackgroundOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }

                HStack {
                    Text(loc("desktop.position"))
                    Spacer()
                    Button(loc("desktop.adjust")) {
                        NotificationCenter.default.post(name: .coinscalAdjustDesktopOverlay, object: nil)
                    }
                }
            }
            .disabled(!settingsVM.settings.desktopOverlayEnabled)
        }
    }

    private func menuBarCoinLabel(for added: WatchlistCoin) -> String {
        coinListVM.coins.first(where: { $0.id == added.coinId })?.symbol ?? added.coinId
    }
}
