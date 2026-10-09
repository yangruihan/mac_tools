#!/bin/sh
set -eu
[ "$#" -eq 2 ] && [ -d "$2" ] && [ ! -L "$2" ] || exit 2
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$1" = source ]; then
 while IFS= read -r REL; do
  [ ! -L "$2/$REL" ] && cmp -s "$DIR/modified/$REL" "$2/$REL" || { echo "source changed; refused" >&2; exit 1; }
 done < "$DIR/paths.txt"
 while IFS= read -r REL; do cp "$DIR/baseline/$REL" "$2/$REL"; done < "$DIR/paths.txt"
elif [ "$1" = worker ]; then
 cmp -s "$DIR/modified-worker" "$2/Contents/MacOS/IceSelectedController" || exit 1
 if ps -axo comm= | grep -F -x "$2/Contents/MacOS/IceSelectedController" >/dev/null; then exit 1; fi
 STAGE="$2.pristine-$$"; SAVED="$2.before-rollback-$$"
 [ ! -e "$STAGE" ] && [ ! -e "$SAVED" ] || exit 1
 ditto --noextattr --norsrc "$DIR/rollback/Baseline Controller.app" "$STAGE"
 codesign --verify --strict "$STAGE"
 mv "$2" "$SAVED"
 if ! mv "$STAGE" "$2"; then mv "$SAVED" "$2"; exit 1; fi
else exit 2; fi
