#!/usr/bin/env bash
# Diagnose the Tuya Cloud side of Charge Guard from a laptop — no Xcode needed.
# Same checks as the app's "Diagnose connection" button: credentials/region,
# device link, online state, switch code. Optionally switches the plug.
#
# Usage:
#   TUYA_REGION=eu TUYA_ACCESS_ID=... TUYA_ACCESS_SECRET=... TUYA_DEVICE_ID=... \
#     ./scripts/tuya-diagnose.sh            # read-only checks
#   ... ./scripts/tuya-diagnose.sh off      # also turn the plug OFF
#   ... ./scripts/tuya-diagnose.sh on       # also turn the plug ON
#
# Any variable not set is prompted for (the secret is read without echo).
set -euo pipefail

ask() { # ask VAR "Prompt" [silent]
  if [ -z "${!1:-}" ]; then
    if [ "${3:-}" = silent ]; then read -rsp "$2: " "$1"; echo; else read -rp "$2: " "$1"; fi
  fi
}
ask TUYA_REGION "Region (eu/us/cn/in) [eu]"
ask TUYA_ACCESS_ID "Access ID"
ask TUYA_ACCESS_SECRET "Access Secret" silent
ask TUYA_DEVICE_ID "Device ID"
SWITCH_CODE="${TUYA_SWITCH_CODE:-switch_1}"
ACTION="${1:-}"

case "${TUYA_REGION:-eu}" in
  eu|"") BASE=https://openapi.tuyaeu.com ;;
  us) BASE=https://openapi.tuyaus.com ;;
  cn) BASE=https://openapi.tuyacn.com ;;
  in|india) BASE=https://openapi.tuyain.com ;;
  *) echo "Unknown region: $TUYA_REGION" >&2; exit 2 ;;
esac

TOKEN=""

# tuya METHOD PATH [BODY] — signed request, prints the JSON response.
tuya() {
  local method=$1 path=$2 body=${3:-}
  local t; t=$(( $(date +%s) * 1000 ))
  local hash; hash=$(printf '%s' "$body" | openssl dgst -sha256 | awk '{print $NF}')
  local str="${TUYA_ACCESS_ID}${TOKEN}${t}${method}"$'\n'"${hash}"$'\n\n'"${path}"
  local sign; sign=$(printf '%s' "$str" | openssl dgst -sha256 -hmac "$TUYA_ACCESS_SECRET" | awk '{print toupper($NF)}')
  local args=(-sS -X "$method" "$BASE$path"
    -H "client_id: $TUYA_ACCESS_ID" -H "sign: $sign" -H "t: $t"
    -H "sign_method: HMAC-SHA256" -H "Content-Type: application/json")
  [ -n "$TOKEN" ] && args+=(-H "access_token: $TOKEN")
  [ -n "$body" ] && args+=(--data "$body")
  curl "${args[@]}"
}

field() { # field JSON KEY — crude extractor, avoids needing jq
  printf '%s' "$1" | grep -o "\"$2\":[^,}]*" | head -1 | cut -d: -f2- | tr -d '"'
}

hint() {
  case "$1" in
    2009) echo "   → Access ID not recognised in this region: check the ID and the Region."  ;;
    1004) echo "   → Wrong Access Secret or wrong Region (data center)." ;;
    1010|1011) echo "   → Token invalid: re-check Access ID / Secret / Region." ;;
    1106) echo "   → Plug not linked to your cloud project. Re-link the app account under Devices on iot.tuya.com and re-check the Device ID." ;;
    2001) echo "   → Plug is OFFLINE: re-pair it to the new WiFi (2.4 GHz) in Smart Life/Deltaco and check signal." ;;
    28841002) echo "   → IoT Core trial expired: iot.tuya.com → Cloud → Cloud Services → IoT Core → extend (free)." ;;
  esac
}

check() { # check STEP JSON — exits on failure with a hint
  if [ "$(field "$2" success)" != "true" ]; then
    local code; code=$(field "$2" code)
    echo "❌ $1 failed: code $code — $(field "$2" msg)"
    hint "$code"
    exit 1
  fi
}

resp=$(tuya GET "/v1.0/token?grant_type=1")
check "Credentials & region" "$resp"
TOKEN=$(field "$resp" access_token)
echo "✅ Credentials & region accepted ($BASE)"

resp=$(tuya GET "/v1.0/devices/$TUYA_DEVICE_ID")
check "Device lookup" "$resp"
echo "✅ Plug \"$(field "$resp" name)\" is linked to your project"

if [ "$(field "$resp" online)" != "true" ]; then
  echo "❌ Plug is OFFLINE in Tuya cloud — it can't be switched off at 80%."
  hint 2001
  exit 1
fi
echo "✅ Plug is online"

resp=$(tuya GET "/v1.0/devices/$TUYA_DEVICE_ID/status")
check "Status" "$resp"
if printf '%s' "$resp" | grep -q "\"code\":\"$SWITCH_CODE\""; then
  echo "✅ Switch code \"$SWITCH_CODE\" found"
else
  echo "❌ Switch code \"$SWITCH_CODE\" not found. Device reports:"
  printf '%s\n' "$resp" | grep -o '"code":"[^"]*"'
  exit 1
fi

if [ "$ACTION" = on ] || [ "$ACTION" = off ]; then
  value=$([ "$ACTION" = on ] && echo true || echo false)
  resp=$(tuya POST "/v1.0/devices/$TUYA_DEVICE_ID/commands" \
    "{\"commands\":[{\"code\":\"$SWITCH_CODE\",\"value\":$value}]}")
  check "Switch $ACTION" "$resp"
  echo "✅ Plug turned $ACTION"
fi

echo
echo "Cloud side is healthy. If the phone still charges to 100%, check the Shortcuts"
echo "battery automation (exists, enabled, Run Immediately, Notify When Run on)."
