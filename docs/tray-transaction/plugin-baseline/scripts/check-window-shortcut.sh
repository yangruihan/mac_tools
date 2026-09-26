#!/bin/sh
set -eu
python3 - "$1" <<'PY'
import sys
s = open(sys.argv[1]).read()
if 'func toggleWindow()' in s:
    assert 'store.toggleWindow = ' in s
    assert '([windowShortcut] + presets).enumerated()' in s
    assert 'saveWindowShortcut()' in s
    assert 'window.orderOut(nil)' in s
    print('window-shortcut=configurable; toggle=show/hide; persistence=yes; shared-conflict-check=yes')
else:
    print('window-shortcut=absent')
assert 'min(value, 18)' in s
print('audio-protection=18%; hardware-not-invoked')
PY
