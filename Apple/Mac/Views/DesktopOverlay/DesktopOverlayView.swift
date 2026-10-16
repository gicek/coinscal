import SwiftUI
import AppKit

@MainActor
final class DesktopOverlayModel: ObservableObject {
    @Published var content: WidgetEntryContent
    @Published var isAdjusting = false
    @Published var backgroundOpacity: Double = 1
    @Published var textSize: DesktopOverlayTextSize = .normal
    var onDoneAdjusting: () -> Void = {}

    init() {
        let defaults = AppSettings()
        content = WidgetEntryContent(
            rows: [], currency: defaults.baseCurrency, updatedAt: nil, language: defaults.language,
            colorByChange: true, upColorHex: defaults.resolvedUpColorHex, downColorHex: defaults.resolvedDownColorHex
        )
    }
}

/// The overlay reuses the large widget layout on a frosted background that blurs the wallpaper behind it.
struct DesktopOverlayView: View {
    @ObservedObject var model: DesktopOverlayModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DesktopOverlayLayout.cornerRadius, style: .continuous)
        ZStack {
            WidgetListView(content: model.content, now: Date(), large: true)
                .environment(\.widgetTextBoost, DesktopOverlayLayout.textBoost(model.textSize))
                .padding(DesktopOverlayLayout.contentPadding)
                .modifier(WallpaperLegibility(active: DesktopOverlayLayout.textNeedsHalo(
                    backgroundOpacity: model.backgroundOpacity, isAdjusting: model.isAdjusting
                )))

            if model.isAdjusting {
                adjustingOverlay
            }
        }
        .frame(
            width: DesktopOverlayLayout.windowSize(for: model.content, textSize: model.textSize).width,
            height: DesktopOverlayLayout.windowSize(for: model.content, textSize: model.textSize).height
        )
        // While adjusting, keep enough background to see the panel's bounds and drag it anywhere:
        // fully transparent pixels of a borderless window do not receive clicks.
        .background(DesktopOverlayBackdrop().opacity(model.isAdjusting ? max(model.backgroundOpacity, 0.6) : model.backgroundOpacity))
        .clipShape(shape)
        .overlay {
            if model.isAdjusting {
                shape.strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
    }

    private var adjustingOverlay: some View {
        VStack(spacing: 8) {
            Text(loc("desktop.adjust.hint"))
                .font(.system(size: 12, weight: .medium))
            Button(loc("desktop.adjust.done")) { model.onDoneAdjusting() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Nearly transparent background: light text with a soft dark shadow under each text (`widgetTextHalo`), as macOS
/// does for desktop icon labels. Only the texts: logos and the background are left as they are.
private struct WallpaperLegibility: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            // Pure white like Finder's labels; secondary texts switch to 85% white themselves (`widgetTextHalo`).
            content
                .environment(\.colorScheme, .dark)
                .foregroundStyle(.white)
                .environment(\.widgetTextHalo, true)
        } else {
            content
        }
    }
}

/// Behind-window blur: the wallpaper shows through, so the overlay blends into the desktop.
private struct DesktopOverlayBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        // Always active: the overlay window is never key, which would otherwise gray the material.
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
