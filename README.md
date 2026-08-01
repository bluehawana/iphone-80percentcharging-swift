# Charge Guard 🔋

Stop your older iPhone from charging past ~80% overnight — using a WiFi smart plug
(Deltaco Smart Home / Smart Life / Tuya) instead of the built-in charge limit that
only iPhone 15 and newer have.

Keeping a lithium battery pinned at 100% all night is one of the fastest ways to age
it. iPhones before the 15 can't cap charging at 80%. Charge Guard fixes that from the
*outside*: when your phone crosses ~80%, it switches **off** the smart plug that powers
the charger, so charging simply stops.

---

## How it works

The one thing an iOS app **cannot** do is watch your battery in the background and act
at 80% — Apple doesn't allow continuous background execution or real-time battery
reactions. The only component on iOS that reliably reacts to battery level while you're
asleep is the **Shortcuts "Battery Level" automation**, which is an OS feature.

So Charge Guard splits the job cleanly:

```
┌──────────────────────────────────────────────────────────┐
│  iOS Shortcuts automation:  "Battery rises above 79%"      │  ← the trigger (OS-level)
│  runs in the background, even while locked / asleep        │
└───────────────────────────┬──────────────────────────────┘
                            │ invokes
                            ▼
┌──────────────────────────────────────────────────────────┐
│  App Intent:  "Stop Charging (Cut Plug)"  (this app)       │  ← the brains
└───────────────────────────┬──────────────────────────────┘
                            │ calls
                            ▼
┌──────────────────────────────────────────────────────────┐
│  TuyaCloudBackend → Tuya Cloud API → plug switched OFF     │  ← the muscle
└──────────────────────────────────────────────────────────┘
```

The plug-control layer is a swappable `ChargerBackend` protocol. Today the only
implementation is **Tuya Cloud** (works with your existing WiFi plug, no extra
hardware). If you ever run a home server, an MQTT/zigbee2mqtt or LAN backend can drop
in behind the same interface without changing the app or the Shortcut.

---

## Project layout

```
ChargeGuard/
  App/
    ChargeGuardApp.swift        # @main SwiftUI app (iOS + macOS)
    ContentView.swift           # setup UI + test buttons
  Core/
    ChargerBackend.swift        # protocol every backend implements
    TuyaConfig.swift            # region + credentials model
    TuyaCrypto.swift            # HMAC-SHA256 request signing
    TuyaCloudBackend.swift      # Tuya Cloud API client
    Keychain.swift              # secure credential storage
    SettingsStore.swift         # load/save config + ChargerController
  Intents/
    ChargerIntents.swift        # Stop / Start / Status App Intents
    ChargeGuardShortcuts.swift  # exposes intents to Shortcuts & Siri
  ChargeGuard.entitlements      # network client (macOS sandbox)
project.yml                     # XcodeGen project definition
```

---

## Setup

### 1. Get your Tuya Cloud credentials (~15 min, one-time, free)

Deltaco Smart Home plugs run on Tuya, so we use Tuya's developer cloud.

1. Make sure the plug already works in the **Deltaco Smart Home** (or **Smart Life** /
   **Tuya Smart**) app on your phone. Note the country you registered that account in.
2. Go to <https://iot.tuya.com> → sign up → **Cloud → Development → Create Cloud Project**.
   - Industry: *Smart Home*; Development Method: *Custom* (Smart Home works too).
   - Data Center: pick the one for your region (Nordic/EU → **Central Europe**).
3. Open the project → **Authorization** tab → copy the **Access ID / Client ID** and
   **Access Secret / Client Secret**.
4. **Devices** tab → **Link App Account** → **Add App Account** → scan the QR code with
   the Deltaco/Smart Life app (Me → top-right scan icon). This links your plug to the project.
5. **Devices → All Devices** → find your plug → copy its **Device ID**.
6. **Service API** tab → **Authorize** the *IoT Core* service (required for the
   device-control endpoints).

You now have: **Region**, **Access ID**, **Access Secret**, **Device ID**.

### 2. Build & run the app

Requires Xcode 16+ (this repo was built with Xcode 26). The Xcode project is generated
from `project.yml` with [XcodeGen](https://github.com/yonatang/XcodeGen):

```bash
brew install xcodegen        # once
xcodegen generate            # creates ChargeGuard.xcodeproj
open ChargeGuard.xcodeproj
```

In Xcode: select the **ChargeGuard** scheme, pick your iPhone (or a simulator/your Mac),
set your Team under **Signing & Capabilities**, and Run.

> Command-line build check (macOS): `xcodebuild -scheme ChargeGuard -destination 'platform=macOS' build`

### 3. Enter credentials & test

In the app, fill in Region, Access ID, Access Secret, and Device ID, then:

- Tap **Detect** next to *Switch code* — it auto-finds the plug's on/off DP code
  (usually `switch_1`, sometimes `switch`).
- Tap **Test: turn plug OFF** — the plug (and your charger) should click off.
- Tap **Test: turn plug ON** to restore it.

If those work, the hard part is done.

### 4. Wire the battery automation (the trigger)

On the iPhone whose battery you want to protect:

1. Open **Shortcuts → Automation → + → Create Personal Automation**.
2. Choose **Battery Level** → **Rises Above** → set the slider to **79%**.
   *(79%, not 80%, so it fires the instant it reaches 80.)*
3. **Next → Add Action →** search **Stop Charging** (from Charge Guard) → select it.
4. **Next →** turn **Ask Before Running OFF** (and "Notify When Run" on if you want a
   confirmation). This is what lets it run silently while you sleep.
5. Done. Plug your phone into the smart-plug-powered charger at night.

That's it — charging now stops at ~80% automatically.

> **Optional:** add a second automation *Battery falls below 40% → Start Charging* if you
> later want it to top back up. (You chose off-only for now; this is a one-line addition.)

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Tuya API error 1106: permission deny` | Authorize **IoT Core** under Service API, and confirm the plug is linked under Devices. |
| `sign invalid` / `1004` | Wrong Region (data center) or Access Secret. The region must match where the app account is registered. |
| `switch code not found` | Tap **Detect**, or try `switch` instead of `switch_1`. |
| Automation didn't fire overnight | Ensure **Ask Before Running** is OFF; battery automations only fire on a *rising* crossing, so it must go from ≤79 to ≥80 while plugged in. |
| Plug off but phone still charged to 100% | The phone was already above 80% when charging started — it triggers on the *crossing*, so start the night below 80%. |

---

## Security notes

- Credentials (including the Access Secret) are stored in the **Keychain**, not in
  UserDefaults or the app binary.
- Nothing is sent anywhere except directly to Tuya's official Cloud API over HTTPS.
- For a public App Store release, each user enters **their own** Tuya credentials — there
  is no shared server or shared secret.

---

## Roadmap

- [ ] `LocalTuyaBackend` — control the plug over the LAN (no cloud) via its local key.
- [ ] `MqttBackend` — for a Home Assistant / zigbee2mqtt setup if you add a home server.
- [ ] Widget + Live Activity showing plug state.
- [ ] Onboarding wizard that walks through the Tuya setup in-app.
- [ ] App Store submission (Utilities category).

---

Built for an iPhone 12 Pro Max with a fresh battery and a Deltaco WiFi plug — because a
battery that never sits at 100% overnight lasts a lot longer.
