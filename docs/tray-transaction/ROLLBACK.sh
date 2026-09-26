#!/bin/sh
# Preserve the original single-file role; --sources restores a disposable source-tree copy.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$#" -eq 2 ] && [ "$1" = '--sources' ]; then
    TARGET=${2%/}
    [ -d "$TARGET" ] && [ -f "$TARGET/MacTools.swift" ] || { echo 'Expected a copied MacTools source directory' >&2; exit 2; }
    BACKUP="$TARGET.before-rollback.$$"
    [ ! -e "$BACKUP" ] || { echo 'Backup path already exists' >&2; exit 2; }
    mv "$TARGET" "$BACKUP"
    mkdir -p "$TARGET"
    cp "$HERE/BASELINE.swift" "$TARGET/MacTools.swift"
    printf 'Prior source copy preserved: %s\n' "$BACKUP"
else
    [ "$#" -eq 1 ] || { echo 'usage: ROLLBACK.sh TARGET_FILE_COPY | --sources TARGET_SOURCE_DIRECTORY_COPY' >&2; exit 2; }
    cp "$HERE/BASELINE.swift" "$1"
fi
