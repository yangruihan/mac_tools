#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ROOT="$PWD/build/ice-interface-product"
APP="$ROOT/MacTools Ice Interface Candidate.app"
sh scripts/build-ice-interface-product-worker.sh
mkdir -p "$ROOT/module-cache"
python3 - "$ROOT" <<'PY'
import pathlib,sys,json,hashlib,shutil,plistlib,subprocess
root=pathlib.Path(sys.argv[1]);repo=pathlib.Path.cwd();app=root/'MacTools Ice Interface Candidate.app';worker=root/'Worker';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
if app.exists():
 exe=app/'Contents/MacOS/MacTools'
 if exe.exists():
  saved=root/'build-history'/sha(exe)/app.name
  if not saved.exists():saved.parent.mkdir(parents=True,exist_ok=True);shutil.copytree(app,saved)
 shutil.rmtree(app)
(app/'Contents/MacOS').mkdir(parents=True);resources=app/'Contents/Resources';resources.mkdir()
m=json.loads((worker/'prepared-build.json').read_text());assert m['revision']=='ordinary-Ice-product-stage1'
for p,h in m['sources'].items():assert sha(repo/p)==h,p
sources=sorted(p for p in repo.glob('Sources/MacTools/**/*.swift') if p.name not in ['MacTools.swift','MenuBarIceCandidateProduct.swift'])+sorted((repo/'Tools/IceInterfaceProduct').glob('*.swift'))
(root/'sources.txt').write_text('\n'.join(map(str,sources))+'\n')
(resources/'ice-interface-bridge.json').write_text(json.dumps({'revision':m['revision'],'manifestSHA256':sha(worker/'prepared-build.json'),'automaticStart':False},indent=2)+'\n')
shutil.copyfile(repo/'Assets/AppIcon/AppIcon.icns',resources/'AppIcon.icns')
package=resources/'IceWorker';package.mkdir()
for name in ['Ice Selected Controller','Ice Selected Fixture','Ice Interface Focus','Ice Product Targets']:shutil.copytree(worker/(name+'.app'),package/(name+'.app'))
for name in ['Source','Fixtures']:shutil.copytree(worker/name,package/name)
for p in [repo/'COPYING.GPL-3.0',repo/'THIRD_PARTY_NOTICES.md',worker/'prepared-build.json']:shutil.copyfile(p,package/p.name)
for p in sources:
 dest=resources/'Source'/p.relative_to(repo);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dest)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'MacTools','CFBundleIdentifier':'com.ryanai.mactools.iceinterfacecandidate','CFBundleName':'MacTools Ice Interface Candidate','CFBundleIconFile':'AppIcon','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.2.1-ice-interface-candidate','CFBundleVersion':'4','LSMinimumSystemVersion':'14.0','LSUIElement':True,'NSHighResolutionCapable':True,'MacToolsSourceRevision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'MacToolsUncommittedSource':True}))
(root/'source-manifest.json').write_text(json.dumps({str(p.relative_to(repo)):sha(p) for p in sources},indent=2,sort_keys=True)+'\n')
PY
swiftc -parse-as-library -DICE_MENU_BAR_CANDIDATE -module-name MacTools -module-cache-path "$ROOT/module-cache" $(cat "$ROOT/sources.txt") -o "$APP/Contents/MacOS/MacTools"
codesign --force --sign "${MAC_TOOLS_SIGN_IDENTITY:-722852A9656BC9126B2C4585713B724D58F60DB6}" "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/MacTools" --ice-interface-bridge-tests "$PWD/Tools/IceInterfaceProduct/Fixtures/accepted-ordinary-window.json"
"$APP/Contents/MacOS/MacTools" --ice-candidate-preflight
printf '%s\n' "$APP"
