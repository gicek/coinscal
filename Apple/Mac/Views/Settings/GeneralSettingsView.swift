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
                    Picker("", selection: Binding(
                        get: { settingsVM.settings.menuBarContent },
                        set: { settingsVM.settings.menuBarContent = $0 }
                    )) {
                        ForEach(MenuBarContent.allCases) { content in
                            Text(content.displayName).tag(content)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220, alignment: .trailing)
                    // Like radioGroup, the underlying NSSegmentedControl may keep stale titles when tags stay the same.
                    .id(settingsVM.settings.language)
                }

                // Price-text options stay visible but disabled in icon mode, so the form does not jump.
                HStack(alignment: .firstTextBaseline) {
                    Text(loc("general.display.menubarCoin"))
                    Spacer()
                    if settingsVM.settings.watchlistCoins.isEmpty {
                        Text(loc("general.display.menubarCoin.hint"))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 220, alignment: .trailing)
                    } else {
                        Picker("", selection: Binding(
                            get: { settingsVM.settings.displayedCoinId },
                            set: { settingsVM.settings.displayedCoinId = $0 }
                        )) {
                            ForEach(settingsVM.settings.watchlistCoins) { added in
                                Text(menuBarCoinLabel(for: added)).tag(added.coinId)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220, alignment: .trailing)
                    }
                }
                .disabled(showsIconOnly)

                Toggle(loc("general.display.textColor"), isOn: Binding(
                    get: { settingsVM.settings.priceColorEnabled },
                    set: { settingsVM.settings.priceColorEnabled = $0 }
                ))
                .disabled(showsIconOnly)

                if settingsVM.settings.priceColorEnabled {
                    Picker(loc("general.display.colorScheme"), selection: Binding(
                        get: { settingsVM.settings.colorScheme },
                        set: { settingsVM.settings.colorScheme = $0 }
                    )) {
                        ForEach(PriceColorScheme.allCases) { scheme in
                            Text(scheme.displayName).tag(scheme)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    // radioGroup's underlying NSMatrix does not refresh titles while tags stay the same; rebuild per language.
                    .id(settingsVM.settings.language)
                    .disabled(showsIconOnly)

                    if settingsVM.settings.colorScheme == .custom {
                        HStack(spacing: 16) {
                            ColorPickerRow(
                                label: loc("general.priceColor.upColor"),
                                hexColor: Binding(
                                    get: { settingsVM.settings.customUpColorHex },
                                    set: { settingsVM.settings.customUpColorHex = $0 }
                                )
                            )
                            ColorPickerRow(
                                label: loc("general.priceColor.downColor"),
                                hexColor: Binding(
                                    get: { settingsVM.settings.customDownColorHex },
                                    set: { settingsVM.settings.customDownColorHex = $0 }
                                )
                            )
                        }
                        .disabled(showsIconOnly)
                    }
                }

                Toggle(loc("general.display.textBackground"), isOn: Binding(
                    get: { settingsVM.settings.showMenuBarBackground },
                    set: { settingsVM.settings.showMenuBarBackground = $0 }
                ))
                .disabled(showsIconOnly)
            }

            Section(loc("general.section.desktop")) {
                Toggle(loc("desktop.show"), isOn: Binding(
                    get: { settingsVM.settings.desktopOverlayEnabled },
                    set: { settingsVM.settings.desktopOverlayEnabled = $0 }
                ))

                Group {
                    HStack {
                        Text(loc("desktop.size"))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settingsVM.settings.desktopOverlaySize },
                            set: { settingsVM.settings.desktopOverlaySize = $0 }
                        )) {
                            ForEach(DesktopOverlaySize.allCases) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220, alignment: .trailing)
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
