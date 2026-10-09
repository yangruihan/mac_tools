#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ICE_PRODUCT_WORKER_ROOT=/tmp/mac-tools-ice-interface-product-candidate-20261009/Worker
ICE_PRODUCT_WORKER_APP="$ICE_PRODUCT_WORKER_ROOT/Ice Selected Controller.app"
mkdir -p "$ICE_PRODUCT_WORKER_ROOT/module-cache"
python3 - "$ICE_PRODUCT_WORKER_ROOT" <<'PY'
import pathlib,sys,json,plistlib,hashlib,shutil
root=pathlib.Path(sys.argv[1]);repo=pathlib.Path.cwd();base=repo/'Tools/IceSelectedQuickInterface';over=repo/'Tools/IceInterfaceProductWorker'
assert not (root/'selected-relative-recovery-v2/ice-selected-relative-v2.json').exists(),'pending recovery: keep current worker'
old=pathlib.Path('/tmp/mac-tools-ice-selected-quick-interface-candidate-20261009')
manifest=json.loads((old/'prepared-build.json').read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert all(sha(pathlib.Path(p))==h for p,h in manifest['sources'].items()),'accepted v9 changed'
sources=sorted(p for p in repo.glob('Sources/MacTools/**/*.swift') if p.name!='MacTools.swift')
sources+=sorted(p for p in base.glob('*.swift') if p.name not in ['IceSelectedFixture.swift','FixtureDiagnostic.swift'] and not (over/p.name).exists())
sources+=sorted(p for p in over.glob('*.swift') if p.name not in ['FixtureDiagnostic.swift','IceProductTargetDirectoryFixture.swift'])
sources += [repo/'Tools/IceRelative/IceRelativeReturn.swift',repo/'Tools/IceBaseline/IceBaselineEngine.swift',repo/'Tools/IceBaseline/EventTap.swift',repo/'Tools/IceBaseline/MouseCursor.swift',repo/'Tools/IceBaseline/IceBaselineSessionLifetime.swift']
(root/'controller-sources.txt').write_text('\n'.join(map(str,sources))+'\n')
for name,exe,bundle in [('Ice Selected Controller','IceSelectedController','com.ryanai.mactools'),('Ice Selected Fixture','IceSelectedFixture','com.ryanai.mactools.nativetargets'),('Ice Interface Focus','IceInterfaceFocus','com.ryanai.mactools.nativefocus'),('Ice Product Targets','IceProductTargets','com.ryanai.mactools.producttargets')]:
 app=root/(name+'.app');(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True);(app/'Contents/Resources').mkdir(exist_ok=True)
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':exe,'CFBundleIdentifier':bundle,'CFBundleName':name,'CFBundleShortVersionString':'0.2.1-product-worker','CFBundleVersion':'3','LSMinimumSystemVersion':'14.0','LSUIElement':True}))
for p in [repo/'COPYING.GPL-3.0',base/'THIRD_PARTY_NOTICES.md']:shutil.copyfile(p,root/'Ice Selected Controller.app/Contents/Resources'/p.name)
PY
swiftc -parse-as-library -module-cache-path "$ICE_PRODUCT_WORKER_ROOT/module-cache" \
 $(cat "$ICE_PRODUCT_WORKER_ROOT/controller-sources.txt") -o "$ICE_PRODUCT_WORKER_APP/Contents/MacOS/IceSelectedController"
swiftc -parse-as-library -module-cache-path "$ICE_PRODUCT_WORKER_ROOT/module-cache" \
 Tools/IceSelectedQuickInterface/IceSelectedFixture.swift Tools/IceInterfaceProductWorker/FixtureDiagnostic.swift Tools/IceBaseline/IceBaselineSessionLifetime.swift Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarProcessSignature.swift \
 -o "$ICE_PRODUCT_WORKER_ROOT/Ice Selected Fixture.app/Contents/MacOS/IceSelectedFixture"
swiftc -parse-as-library -module-cache-path "$ICE_PRODUCT_WORKER_ROOT/module-cache" Tools/IceInterfaceFocusMain.swift -o "$ICE_PRODUCT_WORKER_ROOT/Ice Interface Focus.app/Contents/MacOS/IceInterfaceFocus"
swiftc -parse-as-library -module-cache-path "$ICE_PRODUCT_WORKER_ROOT/module-cache" Tools/IceInterfaceProductWorker/IceProductTargetDirectoryFixture.swift -o "$ICE_PRODUCT_WORKER_ROOT/Ice Product Targets.app/Contents/MacOS/IceProductTargets"
for ICE_PRODUCT_WORKER_NAME in 'Ice Selected Controller' 'Ice Selected Fixture' 'Ice Interface Focus' 'Ice Product Targets'; do
 codesign --force --sign "${MAC_TOOLS_SIGN_IDENTITY:-722852A9656BC9126B2C4585713B724D58F60DB6}" "$ICE_PRODUCT_WORKER_ROOT/$ICE_PRODUCT_WORKER_NAME.app"
 codesign --verify --deep --strict "$ICE_PRODUCT_WORKER_ROOT/$ICE_PRODUCT_WORKER_NAME.app"
done
python3 - "$ICE_PRODUCT_WORKER_ROOT" <<'PY'
import pathlib,sys,json,hashlib,subprocess,shutil,difflib
root=pathlib.Path(sys.argv[1]);repo=pathlib.Path.cwd();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
sources=[pathlib.Path(p) for p in (root/'controller-sources.txt').read_text().splitlines()]
sources += [repo/'Tools/IceSelectedQuickInterface/IceSelectedFixture.swift',repo/'Tools/IceInterfaceProductWorker/FixtureDiagnostic.swift',repo/'Tools/IceInterfaceProductWorker/IceProductTargetDirectoryFixture.swift',repo/'Tools/IceInterfaceFocusMain.swift',repo/'scripts/build-ice-interface-product-worker.sh',repo/'Tools/IceSelectedQuickInterface/THIRD_PARTY_NOTICES.md']
m={'revision':'ordinary-Ice-product-v9.2-delay-boundary','sourceHEAD':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'sources':{str(p):sha(p) for p in sources},'controllerSHA256':sha(root/'Ice Selected Controller.app/Contents/MacOS/IceSelectedController'),'fixtureSHA256':sha(root/'Ice Selected Fixture.app/Contents/MacOS/IceSelectedFixture'),'focusSHA256':sha(root/'Ice Interface Focus.app/Contents/MacOS/IceInterfaceFocus'),'productTargetSHA256':sha(root/'Ice Product Targets.app/Contents/MacOS/IceProductTargets'),'installedSHA256':sha(pathlib.Path('/Applications/MacTools.app/Contents/MacOS/MacTools')),'strictANYRequired':False,'hitTestRequired':False,'automaticStartForProduct':False}
assert m['installedSHA256']=='515c9640ea01039d0157a57cae81893547cfac04b404b6ce41086461bfbce9a2'
(root/'prepared-build.json').write_text(json.dumps(m,indent=2,sort_keys=True)+'\n')
archive=root/'build-history'/m['controllerSHA256'];archive.mkdir(parents=True,exist_ok=True)
for p,n in [(root/'prepared-build.json','prepared-build.json'),(root/'Ice Selected Controller.app/Contents/MacOS/IceSelectedController','controller'),(root/'Ice Selected Fixture.app/Contents/MacOS/IceSelectedFixture','fixture')]:
 d=archive/n
 if d.exists():assert d.read_bytes()==p.read_bytes()
 else:shutil.copyfile(p,d)
patch=[]
for p in sorted((repo/'Tools/IceInterfaceProductWorker').glob('*.swift')):
 original=repo/'Tools/IceSelectedQuickInterface'/p.name
 if original.exists():patch+=difflib.unified_diff(original.read_text().splitlines(True),p.read_text().splitlines(True),fromfile=str(original),tofile=str(p))
(root/'difference-from-accepted-v9.patch').write_text(''.join(patch))
PY
"$ICE_PRODUCT_WORKER_APP/Contents/MacOS/IceSelectedController" --offline-tests

"$ICE_PRODUCT_WORKER_APP/Contents/MacOS/IceSelectedController" --rehide-delay-tests
