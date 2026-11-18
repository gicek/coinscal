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
        HStack {
            Text(label)
            Spacer()
            ColorPicker(label, selection: selectedColor)
                .labelsHidden()
                .frame(width: 44)
        }
    }
}
