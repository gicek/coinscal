import SwiftUI
import WidgetKit

@main
struct CoinscalWidgets: WidgetBundle {
    var body: some Widget {
        CoinPriceWidget()
        WatchlistWidget()
    }
}

/// Small: one coin (docs/WIDGET.md).
struct CoinPriceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CoinPriceWidget", intent: CoinPriceConfigurationIntent.self, provider: CoinPriceProvider()) { entry in
            WidgetPriceView(content: entry.content, now: entry.date)
        }
        .configurationDisplayName(Text("widget.price.name"))
        .description(Text("widget.price.description"))
        .supportedFamilies([.systemSmall])
    }
}

/// Medium (4 rows) and large (8 rows): watchlist prices.
struct WatchlistWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WatchlistWidget", intent: WatchlistConfigurationIntent.self, provider: WatchlistProvider()) { entry in
            WatchlistWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("widget.list.name"))
        .description(Text("widget.list.description"))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct WatchlistWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CoinscalWidgetEntry

    var body: some View {
        WidgetListView(content: entry.content, now: entry.date, large: family == .systemLarge)
    }
}
