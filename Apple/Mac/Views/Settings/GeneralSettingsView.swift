import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var coinListVM: CoinListViewModel

    var body: some View {
        Form {
            Section(loc("general.section.launch")) {
                Toggle(loc("general.launch.atLogin"), isOn: Binding(
                    get: { settingsVM.settings.launchAtLogin },
                    set: { newVal in
                        settingsVM.settings.launchAtLogin = newVal
                        LaunchAtLoginService.shared.setEnabled(newVal)
                    }
                ))
            }

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
                    Toggle(loc("general.display.textBackground"), isOn: $settingsVM.settings.showMenuBarBackground)
                    Toggle(loc("general.display.textColor"), isOn: $settingsVM.settings.priceColorEnabled)

                    Group {
                        HStack {
                            Text(loc("general.display.colorScheme"))
                            Spacer()
                            Picker(loc("general.display.colorScheme"), selection: $settingsVM.settings.colorScheme) {
                                ForEach(PriceColorScheme.allCases) { scheme in
                                    Text(scheme.displayName).tag(scheme)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 220, alignment: .trailing)
                            .id(settingsVM.settings.language)
                        }

                        if settingsVM.settings.colorScheme == .custom {
                            HStack(spacing: 16) {
                                ColorPickerRow(label: loc("general.priceColor.upColor"), hexColor: $settingsVM.settings.customUpColorHex)
                                ColorPickerRow(label: loc("general.priceColor.downColor"), hexColor: $settingsVM.settings.customDownColorHex)
                            }
                        }
                    }
                    .disabled(!settingsVM.settings.priceColorEnabled)
                }
                .disabled(showsIconOnly)
            }

            Section(loc("general.section.desktop")) {
                Toggle(loc("desktop.show"), isOn: Binding(
                    get: { settingsVM.settings.desktopOverlayEnabled },
                    set: { settingsVM.settings.desktopOverlayEnabled = $0 }
                ))

                Group {
                    HStack {
                        Text(loc("desktop.textSize"))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settingsVM.settings.desktopOverlayTextSize },
                            set: { settingsVM.settings.desktopOverlayTextSize = $0 }
                        )) {
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
                        Slider(value: Binding(
                            get: { settingsVM.settings.desktopOverlayBackgroundOpacity },
                            set: { settingsVM.settings.desktopOverlayBackgroundOpacity = $0 }
                        ), in: 0...1)
                        .labelsHidden()
                        .frame(width: 176)
                        Text(verbatim: "\(Int((settingsVM.settings.desktopOverlayBackgroundOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }

                    HStack {
                        Spacer()
                        Button(loc("desktop.adjust")) {
                            NotificationCenter.default.post(name: .coinscalAdjustDesktopOverlay, object: nil)
                        }
                    }
                }
                .disabled(!settingsVM.settings.desktopOverlayEnabled)
            }

            // Applies to the popover and price alerts too, so it lives outside the Menu Bar section.
            Section(loc("general.section.prices")) {
                HStack {
                    Text(loc("general.display.currency"))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settingsVM.settings.baseCurrency },
                        set: { settingsVM.settings.baseCurrency = $0 }
                    )) {
                        ForEach(BaseCurrency.allCases) { currency in
                            Text(currency.displayName).tag(currency)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 220, alignment: .trailing)
                }

                HStack {
                    Text(loc("general.display.priceChangeBasis"))
                    Spacer()
                    Picker(loc("general.display.priceChangeBasis"), selection: $settingsVM.settings.priceChangeBasis) {
                        ForEach(PriceChangeBasis.allCases, id: \.self) { basis in
                            Text(loc(basis.titleKey)).tag(basis)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 220, alignment: .trailing)
                    .id(settingsVM.settings.language)
                }
            }

            Section(loc("general.section.notification")) {
                Toggle(loc("general.notification.priceAlert"), isOn: Binding(
                    get: { settingsVM.settings.priceChangeNotificationEnabled },
                    set: { settingsVM.settings.priceChangeNotificationEnabled = $0 }
                ))
            }

            Section(loc("general.section.language")) {
                HStack {
                    Text(loc("general.language.label"))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settingsVM.settings.language },
                        set: { settingsVM.settings.language = $0 }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 220, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var showsIconOnly: Bool { settingsVM.settings.menuBarContent == .icon }

    private func menuBarCoinLabel(for added: WatchlistCoin) -> String {
        coinListVM.coins.first(where: { $0.id == added.coinId })?.symbol ?? added.coinId
    }
}
