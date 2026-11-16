import SwiftUI

@main
struct PanGalacticNinaTVApp: App {
    @State private var model = AppModel()
    @State private var ambient = AmbientController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(ambient)
        }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhaseChanged(isActive: phase == .active)
        }
    }
}
