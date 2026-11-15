import PanGalacticCore
import SwiftUI

/// Flat module surface: rubric header with grey icon and LED, hairline, content.
struct ModulePanel<Content: View>: View {
    let title: LocalizedStringKey
    let icon: Image
    let light: StatusLight?
    let accessory: String?
    let fillHeight: Bool
    let content: Content

    init(_ title: LocalizedStringKey, icon: Image, light: StatusLight?, accessory: String? = nil, fillHeight: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.light = light
        self.accessory = accessory
        self.fillHeight = fillHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                icon.resizable().scaledToFit().frame(width: 26, height: 26).foregroundStyle(Theme.text2)
                Text(title).font(.pgRubric).tracking(2.5).textCase(.uppercase).foregroundStyle(Theme.text2)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                if let accessory {
                    Text(verbatim: accessory).font(.pgLabel).foregroundStyle(Theme.text).lineLimit(1)
                }
                if let light { StatusLED(light) }
            }
            .frame(height: 44)
            Rectangle().fill(Theme.line).frame(height: 1)
            content.padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
    }
}
