#!/bin/sh
set -eu
[ "$#" -eq 1 ]
cp "$(dirname "$0")/ICON-BUILD-BASELINE.sh" "$1"
