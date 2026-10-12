#!/usr/bin/env bash
# One command to go from a fresh clone to a buildable Xcode project.
#
#   cp .env.example .env    # fill in your Tuya credentials + Apple team ID
#   ./scripts/setup.sh
#   open ChargeGuard.xcodeproj
#
# Reads .env (gitignored), seeds DEBUG credentials, and generates the Xcode
# project with your own signing team — so nothing personal lives in tracked files.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ ! -f .env ]; then
  echo "No .env found. Start with:  cp .env.example .env" >&2
  exit 1
fi

# Export everything in .env so XcodeGen can expand ${DEVELOPMENT_TEAM}.
set -a
# shellcheck disable=SC1091
source .env
set +a

if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  echo "warning: DEVELOPMENT_TEAM is empty in .env — signing for a real device will fail." >&2
  echo "         Xcode → Settings → Accounts → your team, then set it in .env." >&2
fi

./scripts/gen-dev-credentials.sh

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not installed. Run:  brew install xcodegen" >&2
  exit 1
fi

xcodegen generate

echo
echo "Ready. Open ChargeGuard.xcodeproj, pick your iPhone, and Run."
