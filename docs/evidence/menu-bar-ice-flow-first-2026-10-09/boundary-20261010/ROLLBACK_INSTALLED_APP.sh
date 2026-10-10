#!/bin/sh
set -eu
[ "$#" -eq 1 ] || exit 2
exec "/Users/yangruihan/Documents/MacTools正式版回滚/2026-10-10-before-empty-row-fc3ff002/ROLLBACK_APP.sh" "$1"
