#!/bin/sh
set -eu
python3 - "$1" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
if p.is_file() and p.name == 'MacTools.swift' and (p.parent / 'AppModel.swift').exists(): p = p.parent
s = '\n'.join(f.read_text() for f in sorted(p.rglob('*.swift'))) if p.is_dir() else p.read_text()
assert 'MenuBarExtra(' in s
if 'WindowGroup(' in s:
    print('launch=window; menu=yes')
else:
    assert 'setActivationPolicy(.accessory)' in s
    assert 'isReleasedWhenClosed = false' in s
    assert 'makeKeyAndOrderFront(nil)' in s
    print('launch=window; reopen=reuse-window; close=keep-running')
assert 'min(value, 18)' in s
print('audio-protection=18%; hardware-not-invoked')
PY
