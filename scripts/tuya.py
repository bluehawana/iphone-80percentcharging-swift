#!/usr/bin/env python3
"""Mac-side Tuya Cloud diagnostics for Charge Guard.

Verifies credentials, region and IoT Core authorization from the command line so
you can prove the plug is reachable BEFORE typing anything into the iPhone app.

This is a diagnostic tool, not a delivery mechanism — the iOS app never reads
.env. It takes its config from its own settings form and stores it in the
Keychain (Core/SettingsStore.swift).

Signing mirrors Core/TuyaCrypto.swift exactly: lowercase hex SHA-256 of the body,
uppercase hex HMAC-SHA256 for the signature.

Usage:
    python3 scripts/tuya.py token     # auth only — proves ID/secret/region
    python3 scripts/tuya.py list      # devices linked to the project (find Device ID)
    python3 scripts/tuya.py detect    # boolean datapoints — finds the switch code
    python3 scripts/tuya.py status    # is the plug on or off?
    python3 scripts/tuya.py off       # what happens at 80%
    python3 scripts/tuya.py on        # restore
"""

import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_PATH = os.path.join(ROOT, ".env")

BASE_URLS = {
    "eu": "https://openapi.tuyaeu.com",
    "us": "https://openapi.tuyaus.com",
    "cn": "https://openapi.tuyacn.com",
    "in": "https://openapi.tuyain.com",
}

# Tuya error codes worth translating into an actual fix.
HINTS = {
    1004: "Signature invalid — almost always the wrong Access Secret, or the wrong\n"
          "       TUYA_REGION. The data center must match the country your Deltaco /\n"
          "       Smart Life account is registered in.",
    1106: "Permission denied — authorize the IoT Core service under your project's\n"
          "       Service API tab, and confirm the plug appears under Devices.",
    1010: "Token expired or invalid — rerun the command.",
    2009: "Device not found under this project — redo Devices → Link App Account and\n"
          "       check TUYA_DEVICE_ID.",
    28841002: "Your IoT Core free trial has expired — every command is rejected until\n"
              "       you renew it. iot.tuya.com → Cloud → your project → Service API →\n"
              "       IoT Core → Extend Trial Period (free, needs approval).",
    28841101: "This API's service isn't subscribed for your project — add it under\n"
              "       Service API (IoT Core covers on/off/status).",
}


def die(message):
    print("error: " + message, file=sys.stderr)
    sys.exit(1)


def load_env(path):
    if not os.path.exists(path):
        die(".env not found. Copy .env.example to .env and fill it in.")
    values = {}
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values


ENV = load_env(ENV_PATH)
REGION = ENV.get("TUYA_REGION", "eu").lower()
ACCESS_ID = ENV.get("TUYA_ACCESS_ID", "")
ACCESS_SECRET = ENV.get("TUYA_ACCESS_SECRET", "")
DEVICE_ID = ENV.get("TUYA_DEVICE_ID", "")
SWITCH_CODE = ENV.get("TUYA_SWITCH_CODE", "switch_1")

if REGION not in BASE_URLS:
    die("TUYA_REGION must be one of: " + ", ".join(BASE_URLS))
BASE_URL = BASE_URLS[REGION]


def require(**fields):
    missing = [name for name, value in fields.items() if not value]
    if missing:
        die("missing in .env: " + ", ".join(missing))


def sha256_hex(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def hmac_sha256_upper(secret, message):
    digest = hmac.new(secret.encode("utf-8"), message.encode("utf-8"), hashlib.sha256)
    return digest.hexdigest().upper()


def request(method, path, body="", token=""):
    timestamp = str(int(time.time() * 1000))
    string_to_sign = "%s\n%s\n\n%s" % (method, sha256_hex(body), path)
    signature = hmac_sha256_upper(ACCESS_SECRET, ACCESS_ID + token + timestamp + string_to_sign)

    headers = {
        "client_id": ACCESS_ID,
        "sign": signature,
        "t": timestamp,
        "sign_method": "HMAC-SHA256",
        "Content-Type": "application/json",
    }
    if token:
        headers["access_token"] = token

    data = body.encode("utf-8") if body and method != "GET" else None
    req = urllib.request.Request(BASE_URL + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        die("HTTP %s from Tuya: %s" % (exc.code, exc.read().decode("utf-8", "replace")[:300]))
    except urllib.error.URLError as exc:
        die("could not reach %s (%s)" % (BASE_URL, exc.reason))

    if not payload.get("success"):
        code = payload.get("code", -1)
        message = payload.get("msg", "unknown error")
        hint = HINTS.get(code)
        print("Tuya API error %s: %s" % (code, message), file=sys.stderr)
        if hint:
            print("  hint: " + hint, file=sys.stderr)
        sys.exit(1)
    return payload


def get_token():
    require(TUYA_ACCESS_ID=ACCESS_ID, TUYA_ACCESS_SECRET=ACCESS_SECRET)
    return request("GET", "/v1.0/token?grant_type=1")["result"]["access_token"]


def cmd_token():
    get_token()
    print("Auth OK — Access ID, Access Secret and region (%s) are correct." % REGION)


def cmd_list():
    token = get_token()
    result = request("GET", "/v1.0/iot-01/associated-users/devices?size=100", token=token)["result"]
    devices = result.get("devices", [])
    if not devices:
        print("No devices linked. Do Devices → Link App Account → scan the QR with the")
        print("Deltaco Smart Home app (Me → scan icon), then rerun.")
        return
    print("%-24s  %-28s  %s" % ("DEVICE ID", "NAME", "ONLINE"))
    for device in devices:
        print("%-24s  %-28s  %s" % (device.get("id", "?"), device.get("name", "?")[:28],
                                    "yes" if device.get("online") else "no"))
    print("\nCopy the plug's DEVICE ID into TUYA_DEVICE_ID in .env.")


def cmd_detect():
    require(TUYA_DEVICE_ID=DEVICE_ID)
    token = get_token()
    result = request("GET", "/v1.0/devices/%s/status" % DEVICE_ID, token=token)["result"]
    codes = [dp["code"] for dp in result if isinstance(dp.get("value"), bool)]
    if not codes:
        print("No on/off datapoint found — double-check TUYA_DEVICE_ID.")
        return
    print("Boolean datapoints: " + ", ".join(codes))
    print("Set TUYA_SWITCH_CODE=%s in .env (and the same in the iPhone app)." % codes[0])


def cmd_status():
    require(TUYA_DEVICE_ID=DEVICE_ID)
    token = get_token()
    result = request("GET", "/v1.0/devices/%s/status" % DEVICE_ID, token=token)["result"]
    for dp in result:
        if dp.get("code") == SWITCH_CODE:
            print("Plug is currently %s." % ("ON" if dp.get("value") else "OFF"))
            return
    die("no datapoint named %r — run: python3 scripts/tuya.py detect" % SWITCH_CODE)


def set_power(on):
    require(TUYA_DEVICE_ID=DEVICE_ID)
    token = get_token()
    body = json.dumps({"commands": [{"code": SWITCH_CODE, "value": on}]},
                      separators=(",", ":"), sort_keys=True)
    request("POST", "/v1.0/devices/%s/commands" % DEVICE_ID, body=body, token=token)
    print("Plug turned %s." % ("ON" if on else "OFF"))


COMMANDS = {
    "token": cmd_token,
    "list": cmd_list,
    "detect": cmd_detect,
    "status": cmd_status,
    "on": lambda: set_power(True),
    "off": lambda: set_power(False),
}

if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action not in COMMANDS:
        print(__doc__)
        sys.exit(0 if action in ("", "-h", "--help") else 1)
    COMMANDS[action]()
