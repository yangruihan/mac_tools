#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
MAC_TOOLS_ICE_INTEGRATED=1 sh scripts/build-ice-interface-product-candidate.sh
# Keep the established build-app output path; preserve any previous generated app.
APP="$PWD/build/MacTools.app"
[ ! -e "$APP" ] || mv "$APP" "$APP.before-ice-$$"
ditto "$PWD/build/ice-interface-integrated/MacTools.app" "$APP"
codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"
