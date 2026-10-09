#!/bin/sh
set -eu
if [ "${1:-}" = "--page-click-installed-app" ]; then
 [ "$#" -eq 2 ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 exec "$DIR/page-click-20261010/ROLLBACK_INSTALLED_APP.sh" "$2"
fi
if [ "${1:-}" = "--page-click-source" ]; then
 [ "$#" -eq 2 ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 exec "$DIR/page-click-20261010/ROLLBACK.sh" "$2"
fi
if [ "${1:-}" = "--panel-drag-installed-app" ]; then
 [ "$#" -eq 2 ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 exec "$DIR/panel-drag-20261010/ROLLBACK_INSTALLED_APP.sh" "$2"
fi
if [ "${1:-}" = "--panel-drag-source" ] || [ "${1:-}" = "--panel-drag-worker" ]; then
 [ "$#" -eq 2 ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 MODE=source; [ "$1" != "--panel-drag-worker" ] || MODE=worker
 exec "$DIR/panel-drag-20261010/ROLLBACK.sh" "$MODE" "$2"
fi
if [ "${1:-}" = "--background-window-installed-app" ]; then
 [ "$#" -eq 2 ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 exec "$DIR/production-entry/continuation-20261010/ROLLBACK_INSTALLED_APP.sh" "$2"
fi
if [ "${1:-}" = "--background-window-source" ] || [ "${1:-}" = "--background-window-worker" ]; then
 [ "$#" -eq 2 ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 MODE=source; [ "$1" != "--background-window-worker" ] || MODE=worker
 exec "$DIR/production-entry/continuation-20261010/ROLLBACK.sh" "$MODE" "$2"
fi
if [ "${1:-}" = "--production-entry-installed-app" ]; then
 [ "$#" -eq 2 ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 exec "$DIR/production-entry/ROLLBACK_INSTALLED_APP.sh" "$2"
fi
if [ "${1:-}" = "--production-entry-source" ] || [ "${1:-}" = "--production-entry-app" ]; then
 [ "$#" -eq 2 ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 MODE=source; [ "$1" != "--production-entry-app" ] || MODE=app
 exec "$DIR/production-entry/ROLLBACK.sh" "$MODE" "$2"
fi
if [ "${1:-}" = "--production-home-source" ]; then
 [ "$#" -eq 2 ] && [ -d "$2" ] && [ ! -L "$2" ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 for REL in Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift scripts/build-ice-interface-product-candidate.sh; do
  [ ! -L "$2/$REL" ] && cmp -s "$DIR/formalization/modified-sources/$REL" "$2/$REL" || { echo 'changed production source: nothing restored' >&2; exit 1; }
 done
 for REL in Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift scripts/build-ice-interface-product-candidate.sh; do
  cp "$DIR/formalization/baseline/Source/$REL" "$2/$REL"
 done
 exit 0
fi
if [ "${1:-}" = "--production-home-app" ]; then
 [ "$#" -eq 2 ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 exec "$DIR/formalization/rollback/ROLLBACK_APP.sh" "$2"
fi
if [ "${1:-}" = "--stage4-source" ]; then
 [ "$#" -eq 2 ] && [ -d "$2" ] && [ ! -L "$2" ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 TAB=$(printf '\t')
 while IFS="$TAB" read -r action rel; do
  [ ! -L "$2/$rel" ] && cmp -s "$DIR/stage4/modified-sources/$rel" "$2/$rel" || { echo "changed stage4 source: $rel; nothing restored" >&2; exit 1; }
 done < "$DIR/stage4/paths.tsv"
 while IFS="$TAB" read -r action rel; do
  if [ "$action" = restore ]; then cp "$DIR/stage4/baseline/Source/$rel" "$2/$rel"; else rm -f "$2/$rel"; fi
 done < "$DIR/stage4/paths.tsv"
 exit 0
fi
if [ "${1:-}" = "--stage4-app" ]; then
 [ "$#" -eq 2 ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 exec "$DIR/stage4/rollback/ROLLBACK_APP.sh" "$2"
fi
case "${1:-}" in
 --stage2|--stage2-product|--stage2-doc|--stage2-lease|--stage2-workflow|--stage2-native-checks)
 [ "$#" -eq 2 ] && [ -f "$2" ] && [ ! -L "$2" ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 case "$1" in
 --stage2) REL=Tools/IceSelectedQuickInterface/IceSelectedFixture.swift ;;
 --stage2-product) REL=Tools/IceInterfaceProduct/MenuBarIceCandidateProduct.swift ;;
 --stage2-doc) REL=docs/MENUBAR_ICE_INTERFACE_PRODUCT_CANDIDATE.md ;;
 --stage2-lease) REL=Tools/IceInterfaceProductWorker/IceSelectedInterfaceLease.swift ;;
 --stage2-workflow) REL=Tools/IceInterfaceProductWorker/IceSelectedWorkflow.swift ;;
 --stage2-native-checks) REL=Tools/IceSelectedQuickInterface/IceInterfaceNativeChecks.swift ;;
 esac
 cmp -s "$DIR/stage2-modified-sources/$REL" "$2" || { echo 'changed stage2 source: nothing restored' >&2; exit 1; }
 cp "$DIR/stage2-baseline/$REL" "$2"
 exit 0 ;;
esac
if [ "${1:-}" = "--stage1" ]; then
 [ "$#" -eq 2 ] && [ -d "$2" ] && [ ! -L "$2" ] || exit 2
 DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
 TAB=$(printf '\t')
 while IFS="$TAB" read -r action rel; do
  [ ! -L "$2/$rel" ] && cmp -s "$DIR/stage1-modified-sources/$rel" "$2/$rel" || { echo "changed source: $rel; nothing restored" >&2; exit 1; }
 done < "$DIR/stage1-baseline/paths.tsv"
 while IFS="$TAB" read -r action rel; do
  if [ "$action" = restore ]; then cp "$DIR/stage1-baseline/Source/$rel" "$2/$rel"; else rm -f "$2/$rel"; fi
 done < "$DIR/stage1-baseline/paths.tsv"
 exit 0
fi
[ "$#" -eq 1 ] || [ "$#" -eq 2 ] || { echo "usage: ROLLBACK.sh target-copy" >&2; exit 2; }
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET=$1
[ "$#" -ne 2 ] || TARGET=$2
[ -f "$TARGET" ] && [ ! -L "$TARGET" ] || { echo "target must be a regular non-symlink file" >&2; exit 2; }
if [ "$#" -eq 2 ]; then
 case "$1" in
 --plan) cp "$DIR/BASELINE_PLAN.swift" "$2" ;;
 --delay-checks) cp "$DIR/BASELINE_DELAY_CHECKS.swift" "$2" ;;
 --interface-lease) cp "$DIR/BASELINE_INTERFACE_LEASE.swift" "$2" ;;
 --interface-checks) cp "$DIR/BASELINE_INTERFACE_CHECKS.swift" "$2" ;;
 *) exit 2 ;;
 esac
else
 cp "$DIR/BASELINE.swift" "$1"
fi
