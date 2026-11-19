import PanGalacticCore
import PanGalacticServices
import SwiftUI

/// The whole Advanced Sequence as a tree, from the same `/sequence/json` poll as the strip.
struct SequenceView: View {
    let connection: InstanceConnection

    var body: some View {
        Text("Sequence").font(.pgDisplay).foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .ignoresSafeArea()
    }
}
