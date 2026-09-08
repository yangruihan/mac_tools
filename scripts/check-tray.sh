#!/bin/sh
set -eu
python3 - "$1" <<'PY'
import sys
s = open(sys.argv[1]).read()
assert 'MenuBarExtra(' in s
if 'WindowGroup(' in s:
    print('launch=window; menu=yes')
else:
    assert 'setActivationPolicy(.accessory)' in s
    assert 'isReleasedWhenClosed = false' in s
    assert 'makeKeyAndOrderFront(nil)' in s
    print('launch=tray-only; reopen=reuse-window; close=keep-running')
assert 'min(value, 18)' in s
print('audio-protection=18%; hardware-not-invoked')
PY
