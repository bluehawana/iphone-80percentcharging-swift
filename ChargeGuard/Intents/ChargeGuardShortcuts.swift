import AppIntents

/// Surfaces the intents in the Shortcuts app and to Siri, so the battery automation
/// can find "Stop Charging" without any manual scripting.
struct ChargeGuardShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StopChargerIntent(),
            phrases: [
                "Stop charging with \(.applicationName)",
                "\(.applicationName) stop charging",
            ],
            shortTitle: "Stop Charging",
            systemImageName: "bolt.slash.fill"
        )
        AppShortcut(
            intent: StartChargerIntent(),
            phrases: [
                "Start charging with \(.applicationName)",
                "\(.applicationName) start charging",
            ],
            shortTitle: "Start Charging",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: ChargerStatusIntent(),
            phrases: [
                "Check charger with \(.applicationName)",
            ],
            shortTitle: "Check Charger",
            systemImageName: "powerplug.fill"
        )
    }
}
