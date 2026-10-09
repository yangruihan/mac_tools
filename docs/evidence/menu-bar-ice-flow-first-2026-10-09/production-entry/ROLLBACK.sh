#!/bin/sh
set -eu
[ "$#" -eq 2 ] && [ -d "$2" ] && [ ! -L "$2" ] || exit 2
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$1" = source ]; then
 while IFS= read -r REL; do
  [ ! -L "$2/$REL" ] && cmp -s "$DIR/modified/$REL" "$2/$REL" || { echo "changed source; refused: $REL" >&2; exit 1; }
 done < "$DIR/paths.txt"
 while IFS= read -r REL; do cp "$DIR/baseline/$REL" "$2/$REL"; done < "$DIR/paths.txt"
elif [ "$1" = app ]; then
 cmp -s "$DIR/modified.app/Contents/MacOS/MacTools" "$2/Contents/MacOS/MacTools" || exit 1
 cp "$DIR/baseline.app/Contents/MacOS/MacTools" "$2/Contents/MacOS/MacTools"
else exit 2; fi
