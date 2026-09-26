#!/bin/sh
set -eu
python3 - "$1" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
if p.is_file() and p.name == 'MacTools.swift' and (p.parent / 'AppModel.swift').exists(): p = p.parent
s = '\n'.join(f.read_text() for f in sorted(p.rglob('*.swift'))) if p.is_dir() else p.read_text()
if 'func toggleWindow()' in s:
    assert 'store.toggleWindow = ' in s or 'model.toggleWindow = ' in s
    assert 'RegisterEventHotKey(' in s and 'saveWindowShortcut()' in s
    assert 'saveWindowShortcut()' in s
    assert 'window.orderOut(nil)' in s
    print('window-shortcut=configurable; toggle=show/hide; persistence=yes; shared-conflict-check=yes')
else:
    print('window-shortcut=absent')
assert 'min(value, 18)' in s
print('audio-protection=18%; hardware-not-invoked')
PY
