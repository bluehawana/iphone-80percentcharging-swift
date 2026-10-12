# Privacy Policy — Charge Guard

_Last updated: 2 August 2026_

Charge Guard does not collect, transmit, or store any personal data.

## What the app stores

Charge Guard stores the Tuya Cloud credentials **you** enter — access ID, access secret,
device ID, region, and switch code — in the **iOS Keychain** on your own device. They are
encrypted by iOS, never leave your device except as described below, and are deleted when
you delete the app.

## What the app sends, and to whom

The only network requests Charge Guard makes are to **Tuya's official Cloud API**
(`openapi.tuyaeu.com` or the equivalent host for your region), over HTTPS, to:

- authenticate with the credentials you provided,
- read whether your smart plug is on or off,
- turn your smart plug on or off.

Your use of Tuya's service is governed by [Tuya's own privacy
policy](https://www.tuya.com/privacyPolicy).

## What the app does not do

- No analytics, telemetry, crash reporting, or advertising SDKs.
- No user accounts, and no servers operated by the developer — there is no backend.
- No access to your contacts, location, photos, microphone, or camera.
- No reading or transmission of your battery level. The battery threshold is evaluated
  entirely by iOS Shortcuts on your device; the app is only told "switch the plug".

## Data collected by the developer

**None.** The developer of Charge Guard receives no data from this app whatsoever.

## Children

Charge Guard is a utility app and is not directed at children. It collects no data from
anyone, including children.

## Changes

Any change to this policy will be published in this file in the project repository.

## Contact

Questions: open an issue on the project's GitHub repository.
