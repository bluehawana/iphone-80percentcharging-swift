import SwiftUI

@main
struct ChargeGuardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 460, height: 640)
        #endif
    }
}
