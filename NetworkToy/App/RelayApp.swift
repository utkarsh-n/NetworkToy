import SwiftUI
import LabKitCore
import LabKitFeedback
import LabKitUI

@main
struct RelayApp: App {
    @State private var haptics = HapticEngine(persistenceKey: "relay")
    var body: some Scene {
        WindowGroup {
            PlaygroundView(haptics: haptics)
                .labChrome(NetTheme.palette)
                .labHaptics(haptics)
        }
    }
}
