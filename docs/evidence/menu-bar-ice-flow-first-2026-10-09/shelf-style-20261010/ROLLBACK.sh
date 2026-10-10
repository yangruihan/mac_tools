#!/bin/sh
set -eu
[ "$#" -eq 1 ] && [ -d "$1" ] && [ ! -L "$1" ] || exit 2
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
while IFS= read -r REL; do
 [ ! -L "$1/$REL" ] && cmp -s "$DIR/modified/$REL" "$1/$REL" || { echo "changed source; refused" >&2; exit 1; }
done < "$DIR/paths.txt"
while IFS= read -r REL; do cp "$DIR/baseline/$REL" "$1/$REL"; done < "$DIR/paths.txt"
