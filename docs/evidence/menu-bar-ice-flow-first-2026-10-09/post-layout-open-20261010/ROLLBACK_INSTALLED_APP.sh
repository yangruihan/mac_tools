#!/bin/sh
set -eu
[ "$#" -eq 1 ] || exit 2
exec "/Users/yangruihan/Documents/MacTools正式版回滚/2026-10-10-before-visible-open-e7c3371f/ROLLBACK_APP.sh" "$1"
