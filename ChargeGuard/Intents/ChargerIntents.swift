import AppIntents

/// Cut power to the charger — this is what the iOS "Battery rises above 79%"
/// automation calls in the background to stop charging at ~80%.
struct StopChargerIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Charging (Cut Plug)"
    static var description = IntentDescription(
        "Turns OFF the smart plug powering your charger, so the battery stops around 80%."
    )
    // Runs silently in the background — no need to open the app.
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ChargerController.setCharger(on: false)
        return .result(dialog: "Charger plug turned off — battery will hold around 80%. 🔋")
    }
}

/// Restore power to the charger (manual use / testing).
struct StartChargerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Charging (Power Plug)"
    static var description = IntentDescription(
        "Turns ON the smart plug powering your charger."
    )
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ChargerController.setCharger(on: true)
        return .result(dialog: "Charger plug turned on. ⚡️")
    }
}

/// Report whether the plug is currently powered.
struct ChargerStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Charger Plug"
    static var description = IntentDescription("Reports whether the charger plug is on or off.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        let on = try await ChargerController.isOn()
        return .result(value: on, dialog: on ? "Charger plug is ON." : "Charger plug is OFF.")
    }
}
