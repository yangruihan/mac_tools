#!/bin/sh
set -eu
[ "$#" -eq 1 ] || { echo 'usage: ROLLBACK.sh TARGET_COPY' >&2; exit 2; }
cp "$(dirname "$0")/BASELINE.swift" "$1"
