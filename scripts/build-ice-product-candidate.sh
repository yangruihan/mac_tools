#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ICE_PRODUCT_BUILD=/tmp/mac-tools-ice-product-build
ICE_PRODUCT_WORKER=/tmp/mac-tools-ice-baseline-candidate-20261007
ICE_PRODUCT_APP="$PWD/build/MacTools Ice Candidate.app"
ICE_PRODUCT_FLAG=ICE_MENU_BAR_CANDIDATE
if [ "${MAC_TOOLS_ICE_INTEGRATED:-0}" = 1 ]; then
    ICE_PRODUCT_BUILD=/tmp/mac-tools-ice-integrated-build
    ICE_PRODUCT_APP="$PWD/build/MacTools.app"
    ICE_PRODUCT_FLAG=ICE_MENU_BAR_INTEGRATED
fi
# Reuse the verified worker; building this host never launches a scene.
python3 Tools/menu-bar-ice-baseline-session.py --preflight > "$ICE_PRODUCT_WORKER/product-preflight.json"
swift build --scratch-path "$ICE_PRODUCT_BUILD" -c release -Xswiftc -D"$ICE_PRODUCT_FLAG"
ICE_PRODUCT_BIN=$(swift build --scratch-path "$ICE_PRODUCT_BUILD" -c release -Xswiftc -D"$ICE_PRODUCT_FLAG" --show-bin-path)
mkdir -p "$ICE_PRODUCT_APP/Contents/MacOS" "$ICE_PRODUCT_APP/Contents/Resources/IceWorker"
cp "$ICE_PRODUCT_BIN/MacTools" "$ICE_PRODUCT_APP/Contents/MacOS/MacTools"
cp Assets/AppIcon/AppIcon.icns "$ICE_PRODUCT_APP/Contents/Resources/AppIcon.icns"
cp COPYING.GPL-3.0 THIRD_PARTY_NOTICES.md "$ICE_PRODUCT_APP/Contents/Resources/IceWorker/"
cp -R "$ICE_PRODUCT_WORKER/Ice Baseline Controller.app" "$ICE_PRODUCT_WORKER/Ice Baseline Targets.app" "$ICE_PRODUCT_APP/Contents/Resources/IceWorker/"
python3 - "$ICE_PRODUCT_APP" "$ICE_PRODUCT_WORKER" <<'PY'
import hashlib,json,pathlib,plistlib,shutil,sys
app,worker=map(pathlib.Path,sys.argv[1:]);repo=pathlib.Path.cwd();m=json.loads((worker/'prepared-build.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert m['defaultSessionContract']=='isolatedOwnedQuietV1' and m['strictANYRequiredForDefault'] is False
helper=repo/'Tools/menu-bar-ice-baseline-session.py'
import os,subprocess
integrated=os.environ.get('MAC_TOOLS_ICE_INTEGRATED')=='1'
identifier='com.ryanai.mactools' if integrated else 'com.ryanai.mactools.icecandidate'
receipt={'contract':'isolatedOwnedQuietV1','strictANYRequired':False,'inputPolicy':'iceMouseTracking','workerRevision':m['revision'],
 'hostBundleIdentifier':identifier,
 'helper':str(helper),'helperSHA256':sha(helper),'python':shutil.which('python3'),
 'controllerSHA256':m['controllerSHA256'],'fixtureSHA256':m['fixtureSHA256'],'repository':str(repo),'scope':'thisMacSingleScreenOwnedTN'}
(app/'Contents/Resources/ice-candidate-bridge.json').write_text(json.dumps(receipt,indent=2)+'\n')
(app/'Contents/Resources/IceWorker/prepared-build.json').write_bytes((worker/'prepared-build.json').read_bytes())
for path in m['sources']:
 p=pathlib.Path(path);dest=app/'Contents/Resources/IceWorker/source'/p.relative_to(repo);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(p.read_bytes())
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'MacTools','CFBundleIdentifier':identifier,
 'CFBundleIconFile':'AppIcon','CFBundleName':'Mac 工具箱' if integrated else 'MacTools Ice Candidate','CFBundlePackageType':'APPL',
 'CFBundleShortVersionString':'0.2.1' if integrated else '0.2.1-ice-candidate',
 'CFBundleVersion':'5' if integrated else '1','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'LSUIElement':True,
 'MacToolsSourceRevision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
 'MacToolsUncommittedSource':True,'MacToolsIceIntegrationEnabled':integrated}))
PY
if [ "${MAC_TOOLS_ICE_INTEGRATED:-0}" = 1 ]; then
    codesign --force --options runtime --sign "${MAC_TOOLS_SIGN_IDENTITY:-722852A9656BC9126B2C4585713B724D58F60DB6}" "$ICE_PRODUCT_APP"
else
    codesign --force --sign "${MAC_TOOLS_SIGN_IDENTITY:-722852A9656BC9126B2C4585713B724D58F60DB6}" "$ICE_PRODUCT_APP"
fi
codesign --verify --deep --strict "$ICE_PRODUCT_APP"
"$ICE_PRODUCT_APP/Contents/MacOS/MacTools" --ice-candidate-preflight
printf '%s\n' "$ICE_PRODUCT_APP"
