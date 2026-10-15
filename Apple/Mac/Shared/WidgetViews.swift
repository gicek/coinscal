import SwiftUI
import WidgetKit

/// Widget layouts (docs/WIDGET.md, "Visual Rules"). Shared with the app so tests and previews can render them.
/// Change is always shown with an arrow and a sign: desktop widgets lose color in the vibrant (unfocused) mode.
enum WidgetStyle {
    static let popoverURL = URL(string: "coinscal://popover")!
}

/// Small widget: one coin.
struct WidgetPriceView: View {
    let content: WidgetEntryContent
    let now: Date

    var body: some View {
        Group {
            if let row = content.rows.first, content.hasPrices || !row.hasMarket {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        WidgetCoinLogo(row: row, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: row.symbol)
                                .font(.system(size: 14, weight: .semibold))
                            Text(verbatim: row.name)
                                .font(.system(size: 11))
                                .secondaryText()
                        }
                        .lineLimit(1)
                        .textHalo()
                    }
                    Spacer(minLength: 6)
                    Text(verbatim: row.price.map { PriceFormatter.format($0, currency: content.currency) } ?? "—")
                        .font(.system(size: 26, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .textHalo()
                    WidgetChangeText(row: row, content: content)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.top, 2)
                    WidgetUpdatedText(content: content, now: now)
                        .font(.system(size: 10.5))
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                WidgetEmptyView(content: content)
            }
        }
        .widgetURL(WidgetStyle.popoverURL)
        .containerBackground(.background, for: .widget)
    }
}

/// Medium / large widget: watchlist rows.
struct WidgetListView: View {
    let content: WidgetEntryContent
    let now: Date
    let large: Bool

    var body: some View {
        Group {
            if content.hasPrices {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image("app-logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                        Text(verbatim: WidgetText.string("widget.list.title", content.language))
                            .font(.system(size: 12, weight: .semibold))
                            .textHalo()
                        Spacer()
                        WidgetUpdatedText(content: content, now: now)
                            .font(.system(size: 11))
                    }
                    .padding(.bottom, 6)
                    ForEach(Array(content.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().opacity(0.5) }
                        WidgetListRow(row: row, content: content)
                            .frame(height: large ? 38 : 30)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                WidgetEmptyView(content: content)
            }
        }
        .widgetURL(WidgetStyle.popoverURL)
        .containerBackground(.background, for: .widget)
    }
}

private struct WidgetListRow: View {
    let row: WidgetRow
    let content: WidgetEntryContent

    var body: some View {
        HStack(spacing: 9) {
            WidgetCoinLogo(row: row, size: 22)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: row.symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(verbatim: row.name)
                    .font(.system(size: 11))
                    .secondaryText()
            }
            .lineLimit(1)
            .textHalo()
            Spacer(minLength: 6)
            if let price = row.price {
                Text(verbatim: PriceFormatter.format(price, currency: content.currency))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .textHalo()
            }
            WidgetChangeText(row: row, content: content)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 74, alignment: .trailing)
        }
    }
}

private struct WidgetChangeText: View {
    let row: WidgetRow
    let content: WidgetEntryContent

    var body: some View {
        if !row.hasMarket {
            Text(verbatim: WidgetText.string("coin.status.delisted", content.language))
                .secondaryText()
                .lineLimit(1)
                .textHalo()
        } else if let change = row.change24hPercent {
            Text(verbatim: "\(change >= 0 ? "▲" : "▼") \(PriceFormatter.formatPercent(change))")
                .monospacedDigit()
                .foregroundStyle(color(for: change))
                .lineLimit(1)
                .textHalo()
        }
    }

    private func color(for change: Double) -> Color {
        guard content.colorByChange else { return .primary }
        let hex = change >= 0 ? content.upColorHex : content.downColorHex
        return Color(hex: hex) ?? .primary
    }
}

/// Update time; outdated prices get a warning sign.
private struct WidgetUpdatedText: View {
    let content: WidgetEntryContent
    let now: Date

    var body: some View {
        if let updatedAt = content.updatedAt {
            let time = updatedAt.formatted(
                Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: content.language.resourceCode))
            )
            if content.isStale(at: now) {
                Text(verbatim: "⚠︎ \(time)").foregroundStyle(.orange).textHalo()
            } else {
                Text(verbatim: time).secondaryText().textHalo()
            }
        }
    }
}

/// No prices yet: the app has never run and the widget could not fetch.
private struct WidgetEmptyView: View {
    let content: WidgetEntryContent

    var body: some View {
        VStack(spacing: 8) {
            Image("app-logo")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
            Text(verbatim: WidgetText.string("widget.empty", content.language))
                .font(.system(size: 12))
                .secondaryText()
                .multilineTextAlignment(.center)
                .textHalo()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bundled logo only: widgets cannot load remote images while rendering.
private struct WidgetCoinLogo: View {
    let row: WidgetRow
    let size: CGFloat

    var body: some View {
        Group {
            if let asset = row.logoAssetName {
                desaturated(Image(asset).resizable())
                    .scaledToFit()
            } else {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15))
                    Text(verbatim: String(row.symbol.prefix(3)))
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    /// In the accented / vibrant mode colored logos are desaturated rather than tinted.
    private func desaturated(_ image: Image) -> some View {
        if #available(macOS 15.0, *) {
            return AnyView(image.widgetAccentedRenderingMode(.desaturated))
        }
        return AnyView(image)
    }
}

// MARK: - Text halo

/// Set by the desktop overlay when its background is nearly transparent (widgets never set it): every text gets a
/// light dark shadow, like Finder's desktop icon labels. Logos, dividers and backgrounds stay untouched.
private struct WidgetTextHaloKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var widgetTextHalo: Bool {
        get { self[WidgetTextHaloKey.self] }
        set { self[WidgetTextHaloKey.self] = newValue }
    }
}

private struct TextHalo: ViewModifier {
    @Environment(\.widgetTextHalo) private var enabled

    func body(content: Content) -> some View {
        if enabled {
            // As light as Finder's file name labels: a tight shadow hugging the glyphs, barely visible as blur.
            content
                .shadow(color: .black.opacity(0.45), radius: 1.5, y: 0.5)
                .shadow(color: .black.opacity(0.15), radius: 3)
        } else {
            content
        }
    }
}

/// Secondary texts (names, time): the system secondary color, or a fixed 85% white over the wallpaper, where the
/// hierarchical secondary of white is too faint on light wallpapers.
private struct SecondaryText: ViewModifier {
    @Environment(\.widgetTextHalo) private var halo

    func body(content: Content) -> some View {
        if halo {
            content.foregroundStyle(Color.white.opacity(0.85))
        } else {
            content.foregroundStyle(.secondary)
        }
    }
}

extension View {
    fileprivate func textHalo() -> some View { modifier(TextHalo()) }
    fileprivate func secondaryText() -> some View { modifier(SecondaryText()) }
}

enum WidgetText {
    static func string(_ key: String, _ language: AppLanguage) -> String {
        LocalizationManager.string(for: key, language: language)
    }
}
