#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ICE_INTERFACE_PRODUCT_ROOT=/tmp/mac-tools-ice-interface-product-candidate-20261009
ICE_INTERFACE_PRODUCT_APP="$ICE_INTERFACE_PRODUCT_ROOT/MacTools Ice Interface Candidate.app"
if [ ! -f "$ICE_INTERFACE_PRODUCT_ROOT/Worker/prepared-build.json" ]; then
 sh scripts/build-ice-interface-product-worker.sh
fi
mkdir -p "$ICE_INTERFACE_PRODUCT_APP/Contents/MacOS" "$ICE_INTERFACE_PRODUCT_APP/Contents/Resources/IceWorker" "$ICE_INTERFACE_PRODUCT_ROOT/module-cache"
python3 - "$ICE_INTERFACE_PRODUCT_ROOT" <<'PY'
import pathlib,sys,json,hashlib,shutil,plistlib,subprocess
root=pathlib.Path(sys.argv[1]);repo=pathlib.Path.cwd();app=root/'MacTools Ice Interface Candidate.app'
worker=root/'Worker'
if app.exists():
 previous=app/'Contents/MacOS/MacTools'
 if previous.exists():
  previousSHA=hashlib.sha256(previous.read_bytes()).hexdigest();archive=root/'build-history'/previousSHA/'MacTools Ice Interface Candidate.app'
  if not archive.exists():archive.parent.mkdir(parents=True,exist_ok=True);shutil.copytree(app,archive)
  assert hashlib.sha256((archive/'Contents/MacOS/MacTools').read_bytes()).hexdigest()==previousSHA
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((worker/'prepared-build.json').read_text())
assert m['revision']=='ordinary-Ice-product-v9.2-delay-boundary'
for p,h in m['sources'].items():assert sha(pathlib.Path(p))==h,p
assert sha(worker/'Ice Selected Controller.app/Contents/MacOS/IceSelectedController')==m['controllerSHA256']
assert sha(pathlib.Path('/Applications/MacTools.app/Contents/MacOS/MacTools'))==m['installedSHA256']
sources=sorted(p for p in repo.glob('Sources/MacTools/**/*.swift') if p.name not in ['MacTools.swift','MenuBarIceCandidateProduct.swift'])
sources+=sorted((repo/'Tools/IceInterfaceProduct').glob('*.swift'))
(root/'sources.txt').write_text('\n'.join(map(str,sources))+'\n')
oldReceipt=app/'Contents/Resources/ice-candidate-bridge.json'
if oldReceipt.exists():oldReceipt.unlink()
(app/'Contents/Resources/ice-interface-bridge.json').write_text(json.dumps({'revision':m['revision'],'manifestSHA256':sha(worker/'prepared-build.json'),'developmentWorkerRoot':str(worker),'automaticStart':False},indent=2)+'\n')
shutil.copyfile(repo/'Assets/AppIcon/AppIcon.icns',app/'Contents/Resources/AppIcon.icns')
for name in ['Ice Selected Controller','Ice Selected Fixture','Ice Interface Focus','Ice Product Targets']:
 target=app/'Contents/Resources/IceWorker'/(name+'.app')
 if target.exists():shutil.rmtree(target)
 shutil.copytree(worker/(name+'.app'),target)
for p in [repo/'COPYING.GPL-3.0',repo/'THIRD_PARTY_NOTICES.md',worker/'prepared-build.json']:
 shutil.copyfile(p,app/'Contents/Resources/IceWorker'/p.name)
for p in sources:
 dest=app/'Contents/Resources/Source'/p.relative_to(repo);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dest)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'MacTools','CFBundleIdentifier':'com.ryanai.mactools.iceinterfacecandidate','CFBundleName':'MacTools Ice Interface Candidate','CFBundleIconFile':'AppIcon','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.2.1-ice-interface-candidate','CFBundleVersion':'3','LSMinimumSystemVersion':'14.0','LSUIElement':True,'NSHighResolutionCapable':True,'MacToolsSourceRevision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'MacToolsUncommittedSource':True}))
(root/'source-manifest.json').write_text(json.dumps({str(p):sha(p) for p in sources},indent=2,sort_keys=True)+'\n')
PY
swiftc -parse-as-library -DICE_MENU_BAR_CANDIDATE -module-name MacTools -module-cache-path "$ICE_INTERFACE_PRODUCT_ROOT/module-cache" \
  $(cat "$ICE_INTERFACE_PRODUCT_ROOT/sources.txt") -o "$ICE_INTERFACE_PRODUCT_APP/Contents/MacOS/MacTools"
codesign --force --sign "${MAC_TOOLS_SIGN_IDENTITY:-722852A9656BC9126B2C4585713B724D58F60DB6}" "$ICE_INTERFACE_PRODUCT_APP"
codesign --verify --deep --strict "$ICE_INTERFACE_PRODUCT_APP"
"$ICE_INTERFACE_PRODUCT_APP/Contents/MacOS/MacTools" --ice-interface-bridge-tests /tmp/mac-tools-ice-selected-quick-interface-candidate-20261009/session-FAE73121-4A53-48AC-AB8E-8D62608D5CE2/result.json
"$ICE_INTERFACE_PRODUCT_APP/Contents/MacOS/MacTools" --ice-candidate-preflight
printf '%s\n' "$ICE_INTERFACE_PRODUCT_APP"
