#!/bin/sh
set -eu
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
