#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ROOT="$PWD/build/ice-interface-product/Worker"
STATE="$HOME/Library/Application Support/MacTools/IceInterfaceCandidate"
[ ! -e "$STATE/selected-relative-recovery-v2/ice-selected-relative-v2.json" ] || { echo 'pending recovery: keep current worker' >&2; exit 1; }
mkdir -p "$ROOT/module-cache"
python3 - "$ROOT" <<'PY'
import pathlib,sys,json,plistlib,shutil
root=pathlib.Path(sys.argv[1]);repo=pathlib.Path.cwd();base=repo/'Tools/IceSelectedQuickInterface';over=repo/'Tools/IceInterfaceProductWorker'
sources=sorted(p for p in repo.glob('Sources/MacTools/**/*.swift') if p.name!='MacTools.swift')
sources+=sorted(p for p in base.glob('*.swift') if p.name not in ['IceSelectedFixture.swift','FixtureDiagnostic.swift'] and not (over/p.name).exists())
sources+=sorted(p for p in over.glob('*.swift') if p.name not in ['FixtureDiagnostic.swift','IceProductTargetDirectoryFixture.swift'])
sources += [repo/p for p in ['Tools/IceRelative/IceRelativeReturn.swift','Tools/IceBaseline/IceBaselineEngine.swift','Tools/IceBaseline/EventTap.swift','Tools/IceBaseline/MouseCursor.swift','Tools/IceBaseline/IceBaselineSessionLifetime.swift']]
(root/'controller-sources.txt').write_text('\n'.join(map(str,sources))+'\n')
for name,exe,bundle in [('Ice Selected Controller','IceSelectedController','com.ryanai.mactools'),('Ice Selected Fixture','IceSelectedFixture','com.ryanai.mactools.nativetargets'),('Ice Interface Focus','IceInterfaceFocus','com.ryanai.mactools.nativefocus'),('Ice Product Targets','IceProductTargets','com.ryanai.mactools.producttargets')]:
 app=root/(name+'.app');(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True);(app/'Contents/Resources').mkdir(exist_ok=True)
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':exe,'CFBundleIdentifier':bundle,'CFBundleName':name,'CFBundleShortVersionString':'0.2.1-product-worker','CFBundleVersion':'4','LSMinimumSystemVersion':'14.0','LSUIElement':True}))
for p in [repo/'COPYING.GPL-3.0',base/'THIRD_PARTY_NOTICES.md']:shutil.copyfile(p,root/'Ice Selected Controller.app/Contents/Resources'/p.name)
PY
swiftc -parse-as-library -module-cache-path "$ROOT/module-cache" $(cat "$ROOT/controller-sources.txt") -o "$ROOT/Ice Selected Controller.app/Contents/MacOS/IceSelectedController"
swiftc -parse-as-library -module-cache-path "$ROOT/module-cache" Tools/IceSelectedQuickInterface/IceSelectedFixture.swift Tools/IceInterfaceProductWorker/FixtureDiagnostic.swift Tools/IceBaseline/IceBaselineSessionLifetime.swift Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarProcessSignature.swift -o "$ROOT/Ice Selected Fixture.app/Contents/MacOS/IceSelectedFixture"
swiftc -parse-as-library -module-cache-path "$ROOT/module-cache" Tools/IceInterfaceFocusMain.swift -o "$ROOT/Ice Interface Focus.app/Contents/MacOS/IceInterfaceFocus"
swiftc -parse-as-library -module-cache-path "$ROOT/module-cache" Tools/IceInterfaceProductWorker/IceProductTargetDirectoryFixture.swift -o "$ROOT/Ice Product Targets.app/Contents/MacOS/IceProductTargets"
for NAME in 'Ice Selected Controller' 'Ice Selected Fixture' 'Ice Interface Focus' 'Ice Product Targets'; do
 codesign --force --sign "${MAC_TOOLS_SIGN_IDENTITY:-722852A9656BC9126B2C4585713B724D58F60DB6}" "$ROOT/$NAME.app"
 codesign --verify --deep --strict "$ROOT/$NAME.app"
done
python3 - "$ROOT" <<'PY'
import pathlib,sys,json,hashlib,subprocess,shutil
root=pathlib.Path(sys.argv[1]);repo=pathlib.Path.cwd();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
sources=[pathlib.Path(p) for p in (root/'controller-sources.txt').read_text().splitlines()]
sources += [repo/p for p in ['Tools/IceSelectedQuickInterface/IceSelectedFixture.swift','Tools/IceInterfaceProductWorker/FixtureDiagnostic.swift','Tools/IceInterfaceProductWorker/IceProductTargetDirectoryFixture.swift','Tools/IceInterfaceFocusMain.swift','Tools/IceSelectedQuickInterface/THIRD_PARTY_NOTICES.md']]
sourceRoot=root/'Source'
if sourceRoot.exists():shutil.rmtree(sourceRoot)
for p in sources:
 dest=sourceRoot/p.relative_to(repo);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dest)
fixtures=root/'Fixtures'
if fixtures.exists():shutil.rmtree(fixtures)
shutil.copytree(repo/'Tools/IceInterfaceProductWorker/Fixtures',fixtures)
m={'revision':'ordinary-Ice-product-stage1','sourceHEAD':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'sources':{str(p.relative_to(repo)):sha(p) for p in sources},'controllerSHA256':sha(root/'Ice Selected Controller.app/Contents/MacOS/IceSelectedController'),'fixtureSHA256':sha(root/'Ice Selected Fixture.app/Contents/MacOS/IceSelectedFixture'),'focusSHA256':sha(root/'Ice Interface Focus.app/Contents/MacOS/IceInterfaceFocus'),'productTargetSHA256':sha(root/'Ice Product Targets.app/Contents/MacOS/IceProductTargets'),'strictANYRequired':False,'hitTestRequired':False,'automaticStartForProduct':False}
(root/'prepared-build.json').write_text(json.dumps(m,indent=2,sort_keys=True)+'\n')
PY
"$ROOT/Ice Selected Controller.app/Contents/MacOS/IceSelectedController" --offline-tests
"$ROOT/Ice Selected Controller.app/Contents/MacOS/IceSelectedController" --rehide-delay-tests
"$ROOT/Ice Selected Controller.app/Contents/MacOS/IceSelectedController" --dispatch-validation-tests
