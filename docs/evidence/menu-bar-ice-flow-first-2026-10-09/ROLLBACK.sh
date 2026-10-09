#!/bin/sh
set -eu
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
