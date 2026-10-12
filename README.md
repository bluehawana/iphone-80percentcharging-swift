# Charge Guard 🔋

Stop your older iPhone from charging past ~80% overnight — using a WiFi smart plug
(Deltaco Smart Home / Smart Life / Tuya) instead of the built-in charge limit that only
iPhone 15 and newer have.

Keeping a lithium battery pinned at 100% all night is one of the fastest ways to age it.
Apple ships a user-settable **Charge Limit** (80 / 85 / 90 / 95%) under Settings →
Battery → Charging — but [only on iPhone 15 and later](https://support.apple.com/en-us/108055).
Older iPhones get **Optimized Battery Charging**, which is adaptive: *it* decides when to
top up to 100% based on your routine, and you can't pin it.

Charge Guard gives you the hard cap from the *outside*: when your phone crosses your
threshold, it switches **off** the smart plug powering the charger, so charging stops.

## What you need

| | |
|---|---|
| **iPhone** | Any model, iOS 16+. (If you have an iPhone 15 or newer, just use Settings → Battery → Charging — you don't need this.) |
| **Smart plug** | Any Tuya-compatible WiFi plug (~€10) — Deltaco Smart Home, Smart Life, Tuya branded. **2.4GHz only**; these don't do 5GHz. |
| **Tuya account** | Free developer account at [iot.tuya.com](https://iot.tuya.com) — ~15 minutes, one time. |
| **Mac** | Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) to build and install on your phone. |

## Do you actually need this app?

Be honest with yourself first — there's a no-code route that works for a lot of people:

1. In **Smart Life**, open your plug → **Tap-to-Run** → create a scene that turns it
   **off**, name it something like *Charger Off*, and **Add to Siri**.
2. In **Shortcuts → Automation → Battery Level → Rises Above 75%**, run that scene.
3. Set it to **Run Immediately**.

No Tuya developer account, no API credentials, no Xcode. If that works for you, use it —
this README will still be here if it doesn't.

**Charge Guard is for when it doesn't**, or when you'd rather not depend on it:

- It talks to the Tuya API **directly** — no third-party app sitting in the automation
  path, nothing to stay logged into, no scene silently breaking after an app update.
- The backend is a swappable protocol, so the same Shortcut works if you move to
  LAN/MQTT/Matter hardware later.
- It's open source and auditable — you can see exactly what it does with your credentials.
- It's a single-purpose app, not a smart-home suite that also wants your location.

The trade is honest: **more setup, more control.**

## Quick start

```bash
git clone https://github.com/bluehawana/iphone-80percentcharging-swift.git
cd iphone-80percentcharging-swift
brew install xcodegen
cp .env.example .env          # fill in Tuya credentials + your Apple team ID
./scripts/setup.sh            # generates ChargeGuard.xcodeproj
python3 scripts/tuya.py off   # optional: prove the plug responds before building
open ChargeGuard.xcodeproj
```

Then follow **Setup** below — the Tuya credentials in step 1 are the only fiddly part,
and `scripts/tuya.py` will tell you exactly what's wrong if something doesn't work.

---

## How it works

The one thing an iOS app **cannot** do is watch your battery in the background and act
at a threshold — Apple doesn't allow continuous background execution or real-time battery
reactions. The only component on iOS that reliably reacts to battery level while you're
asleep is the **Shortcuts "Battery Level" automation**, which is an OS feature.

So Charge Guard splits the job cleanly:

```
┌──────────────────────────────────────────────────────────┐
│  iOS Shortcuts automation:  "Battery rises above 75%"      │  ← the trigger (OS-level)
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
scripts/
  setup.sh                      # .env → credentials + generated Xcode project
  gen-dev-credentials.sh        # DEBUG-only Keychain seeding from .env
  tuya.py                       # Mac-side API diagnostics (stdlib only)
  watch-plug.sh                 # polls the plug; reports when an automation fires
project.yml                     # XcodeGen project definition
.env.example                    # template — copy to .env (gitignored)
```

---

## Setup

### 1. Get your Tuya Cloud credentials (~15 min, one-time, free)

Deltaco Smart Home plugs run on Tuya, so we use Tuya's developer cloud.

1. Pair the plug in the **Smart Life** app (by Tuya) and note the country you registered
   the account in.

   > ⚠️ **Use Smart Life, not a rebranded OEM app.** Deltaco Smart Home, and other
   > white-label Tuya skins, keep their accounts in a separate pool that the console's
   > device-linking QR flow rejects — the scan succeeds, you confirm, and it reports
   > "expired" with no device added. If your plug is already in an OEM app, remove it
   > there first (a plug binds to one account at a time), then pair it in Smart Life.
   > Same plug, same Tuya backend, same hardware — only the front end differs.
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

Requires Xcode 16+ (this repo was built with Xcode 26) and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is generated, not
committed, so nobody inherits anyone else's signing settings.

```bash
brew install xcodegen        # once
cp .env.example .env         # then fill it in — see below
./scripts/setup.sh           # seeds credentials + generates ChargeGuard.xcodeproj
open ChargeGuard.xcodeproj
```

Your `.env` holds your Tuya credentials **and** your `DEVELOPMENT_TEAM` (Xcode →
Settings → Accounts → your team). It is gitignored, so nothing personal is ever
committed. Then in Xcode: select the **ChargeGuard** scheme, pick your iPhone, and Run.

> Command-line build check (macOS): `xcodebuild -scheme ChargeGuard -destination 'platform=macOS' build`

**Debug builds configure themselves.** `scripts/setup.sh` generates
`DevCredentials.generated.swift` (gitignored) from your `.env` and seeds the Keychain on
first launch, so you don't type a 32-character secret on a phone keyboard. It's wrapped
in `#if DEBUG` — release and TestFlight builds contain none of it, and their users enter
their own credentials in the app's form.

### 2b. Check your credentials without the phone

Before touching the iPhone, prove the whole cloud path works from your Mac:

```bash
python3 scripts/tuya.py token    # Access ID + Secret + region correct?
python3 scripts/tuya.py list     # devices linked — copy your Device ID from here
python3 scripts/tuya.py detect   # finds the switch code (switch_1 / switch)
python3 scripts/tuya.py off      # the plug should click
python3 scripts/tuya.py on
```

Stdlib Python only, no `pip install`. It translates Tuya's error codes into fixes, which
turns "it doesn't work" into a specific next step. `scripts/watch-plug.sh` polls the plug
and reports the moment an automation fires — useful for confirming an overnight run.

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
2. Choose **Battery Level** → **Rises Above** → set the slider to **75%**.
   *(The trigger is strictly "above", so 75 fires at 76. Newer iOS snaps the slider to
   5% steps; if yours allows 1% steps, 79 gives you a cut at 80.)*
3. **Next → Add Action →** search **Stop Charging** (from Charge Guard) → select it.
4. **Next →** choose **Run Immediately** — on older iOS, turn **Ask Before Running OFF**.
   Optionally enable **Notify When Run** for proof it fired.
5. Done. Plug your phone into the smart-plug-powered charger at night.

> ⚠️ **Step 4 is the one everybody gets wrong.** Left on "Run After Confirmation", iOS
> posts a notification and waits for a tap — so it silently does nothing while you sleep,
> and looks exactly like a broken integration.

### 5. Wire the recharge automation (so the plug comes back on)

The plug stays off until something turns it on. Add a second automation the same way:

**Battery Level → Falls Below → 40% → Start Charging → Run Immediately**

That produces a self-regulating loop that keeps the battery in the healthiest band:

```
plug in at 55% → charges → 76% → plug cut
drains through the day → hits 40% → plug re-armed
plug in again → charges → 76% → cut …
```

You can leave the phone docked permanently and it will cycle between roughly 40% and 76%
on its own.

### 5b. Or: power on at a fixed time every day

If you'd rather charge on a schedule — say, plug live from 20:00, cut at ~80% — replace
the *falls below 40%* automation with a timed one:

1. **Shortcuts → Automation → + → Time of Day → 20:00 → Daily → Run Immediately**.
2. **New Blank Automation**, then add three actions:
   - **Get Battery Level**
   - **If** *Battery Level* **is less than** `75` → **Start Charging**
   - **Otherwise** → **Stop Charging**

The **If** matters. The cut in §4 fires on the *crossing* of 75%, so a phone that is
already at 78% when the plug comes on would never trigger it and would charge to 100%.
Checking the level at 20:00 skips the top-up on those days instead.

> There is no "charger connected" trigger for this: with the plug off there's no power,
> so iOS never sees a charger attached and such an automation would never fire.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| **Link App Account QR "expires" the moment you confirm** | Two causes. Your project's **data center doesn't match** the country your plug app account is registered in (Nordic/EU → *Central Europe*, **not** *Western Europe* — different API host entirely). Or you're scanning with a **white-label app**: Deltaco Smart Home and other OEM skins live in a separate account pool and the console's QR flow rejects them. Remove the plug from the OEM app, pair it in **Smart Life** instead, and scan from there. |
| **Automation posts a notification but the plug doesn't switch** | The automation is on **Run After Confirmation** — iOS is waiting for a tap you'll never give at 3am. Set it to **Run Immediately**. |
| **Nothing happens at exactly your threshold** | "Rises Above 75%" fires when the level *exceeds* 75, i.e. at 76%. Expect the cut a percent or two above what you set, plus a few minutes of iOS batching. |
| **It worked for months, then silently stopped cutting** | Tuya's **IoT Core** service is a free *trial* that expires (typically after 1–6 months), after which every command is rejected. Run `python3 scripts/tuya.py token` to confirm, then renew at iot.tuya.com → Cloud → your project → **Service API → IoT Core → Extend Trial Period**. Put the new expiry date in your calendar. |
| `Tuya API error 1106: permission deny` | Authorize **IoT Core** under Service API, and confirm the plug is linked under Devices. |
| `sign invalid` / `1004` | Wrong Region (data center) or Access Secret. The region must match where the app account is registered. |
| `switch code not found` | Run `python3 scripts/tuya.py detect`, or try `switch` instead of `switch_1`. |
| **Plug off but phone still charged to 100%** | Either the phone was already above your threshold when charging started (it triggers on the *crossing* — start the night below it), or the phone was charging from something else. A USB cable to your Mac will happily charge it no matter what the plug does. |
| **Plug never comes back on** | By design — see §5. Add the *falls below 40% → Start Charging* automation. |

---

## Security notes

- Credentials (including the Access Secret) are stored in the **Keychain**, not in
  UserDefaults or the app binary.
- Nothing is sent anywhere except directly to Tuya's official Cloud API over HTTPS.
- For a public App Store release, each user enters **their own** Tuya credentials — there
  is no shared server or shared secret.
- `.env` and `ChargeGuard/Core/DevCredentials.generated.swift` are **gitignored**. Only
  `.env.example` is committed. Your Apple `DEVELOPMENT_TEAM` also comes from `.env`, so
  no personal identifier lives in a tracked file.
- The `.env` convenience is **DEBUG-only**. `DevCredentials` is wrapped in `#if DEBUG`,
  so release and TestFlight builds contain no credentials at all — their users type their
  own into the app. An iOS app bundle is a readable zip; anything compiled into a shipped
  binary is not a secret, which is exactly why the runtime form exists.

---

## Roadmap

- [ ] `LocalTuyaBackend` — control the plug over the LAN (no cloud) via its local key.
- [ ] `MqttBackend` — for a Home Assistant / zigbee2mqtt setup if you add a home server.
- [ ] Widget + Live Activity showing plug state.
- [ ] Onboarding wizard that walks through the Tuya setup in-app.
- [ ] App Store submission (Utilities category).

---

## Contributing

The backend is a swappable protocol — `ChargerBackend` in `Core/`. If your plug isn't
Tuya, implementing that one interface is the whole job; the App Intents and Shortcuts
wiring stay untouched. PRs for LAN/MQTT/Matter backends especially welcome.

## License

[MIT](LICENSE) — do what you like with it.

---

Built for an iPhone 12 Pro Max with a fresh battery and a Deltaco WiFi plug — because a
battery that never sits at 100% overnight lasts a lot longer.

If this saved you a battery replacement, star the repo so the next person finds it. ⭐️
