import SwiftUI

struct ColorPickerRow: View {
    let label: String
    @Binding var hexColor: String

    var selectedColor: Binding<Color> {
        Binding(
            get: { Color(hex: hexColor) ?? .green },
            set: { newColor in hexColor = newColor.toHex() }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.callout)
            ColorPicker("", selection: selectedColor)
                .labelsHidden()
                .frame(width: 44)
        }
    }
}
