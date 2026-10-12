#!/usr/bin/env bash
# Generates ChargeGuard/Core/DevCredentials.generated.swift from .env so DEBUG
# builds seed the Keychain automatically instead of you typing four fields on a
# phone keyboard.
#
# The generated file is gitignored and everything in it is wrapped in #if DEBUG,
# so release/App Store builds contain none of it. Run this before `xcodegen
# generate` — XcodeGen globs sources at generate time, so the file must exist first.
#
#   ./scripts/gen-dev-credentials.sh && xcodegen generate

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
OUT="$ROOT/ChargeGuard/Core/DevCredentials.generated.swift"

get() {
  [ -f "$ENV_FILE" ] || { echo ""; return; }
  sed -n "s/^$1=//p" "$ENV_FILE" | head -1 | tr -d '"'"'"' \r'
}

REGION="$(get TUYA_REGION)"
ACCESS_ID="$(get TUYA_ACCESS_ID)"
ACCESS_SECRET="$(get TUYA_ACCESS_SECRET)"
DEVICE_ID="$(get TUYA_DEVICE_ID)"
SWITCH_CODE="$(get TUYA_SWITCH_CODE)"

# .env uses the API's short code; TuyaRegion spells India out.
[ "$REGION" = "in" ] && REGION="india"
[ -n "$REGION" ] || REGION="eu"
[ -n "$SWITCH_CODE" ] || SWITCH_CODE="switch_1"

TMP="$(mktemp)"
cat > "$TMP" <<SWIFT
// GENERATED FILE — do not edit, do not commit.
// Produced by scripts/gen-dev-credentials.sh from .env.
//
// DEBUG ONLY. Everything here is compiled out of release builds, so no
// credential ever reaches a distributable binary. Real users of a shipped build
// enter their own values in the app's settings form.

import Foundation

#if DEBUG
enum DevCredentials {
    static let region = "$REGION"
    static let accessId = "$ACCESS_ID"
    static let accessSecret = "$ACCESS_SECRET"
    static let deviceId = "$DEVICE_ID"
    static let switchCode = "$SWITCH_CODE"

    /// nil when .env wasn't filled in — the app then behaves exactly as it does
    /// in release: an empty form waiting for input.
    static var config: TuyaConfig? {
        guard !accessId.isEmpty, !accessSecret.isEmpty, !deviceId.isEmpty else { return nil }
        return TuyaConfig(
            region: TuyaRegion(rawValue: region) ?? .eu,
            accessId: accessId,
            accessSecret: accessSecret,
            deviceId: deviceId,
            switchCode: switchCode
        )
    }
}
#endif
SWIFT

# Only replace the file when the contents actually change, so running this from an
# Xcode build phase doesn't touch the mtime and force a needless recompile every build.
if [ -f "$OUT" ] && cmp -s "$TMP" "$OUT"; then
  rm -f "$TMP"
  exit 0
fi
mv "$TMP" "$OUT"

if [ -n "$ACCESS_ID" ] && [ -n "$ACCESS_SECRET" ] && [ -n "$DEVICE_ID" ]; then
  echo "Generated $OUT (credentials found in .env — DEBUG builds will self-configure)"
else
  echo "Generated $OUT (.env incomplete — app will show an empty form as usual)"
fi
