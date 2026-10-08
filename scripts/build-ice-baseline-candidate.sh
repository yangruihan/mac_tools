#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ICE_BASELINE_ROOT=/tmp/mac-tools-ice-baseline-candidate-20261007
ICE_BASELINE_SIGN=${MAC_TOOLS_SIGN_IDENTITY:-722852A9656BC9126B2C4585713B724D58F60DB6}
ICE_BASELINE_CONTROLLER="$ICE_BASELINE_ROOT/Ice Baseline Controller.app"
ICE_BASELINE_FIXTURE="$ICE_BASELINE_ROOT/Ice Baseline Targets.app"
mkdir -p "$ICE_BASELINE_CONTROLLER/Contents/MacOS" "$ICE_BASELINE_FIXTURE/Contents/MacOS" "$ICE_BASELINE_ROOT/module-cache"
swiftc -parse-as-library -D OWNED_LIVE_CONTROLLER -module-cache-path "$ICE_BASELINE_ROOT/module-cache" \
  Tools/IceBaseline/EventTap.swift Tools/IceBaseline/MouseCursor.swift \
  Tools/IceBaseline/IceBaselineEngine.swift Tools/IceBaseline/IceBaselineNative.swift \
  Tools/IceBaseline/IceBaselineCandidateJournal.swift Tools/IceBaseline/IceBaselineCandidateCoordinator.swift Tools/IceBaseline/IceBaselineCandidateTests.swift \
  Tools/IceBaseline/IceBaselineRecovery.swift Tools/IceBaseline/IceBaselineMenuLease.swift Tools/IceBaseline/IceBaselineANYBridge.swift Tools/IceBaseline/IceBaselineNativePlan.swift Tools/IceBaseline/IceBaselineIntegrationTests.swift \
  Tools/IceBaseline/IceBaselineLayout.swift \
  Tools/IceBaseline/IceBaselineSessionLifetime.swift \
  Tools/IceBaseline/IceBaselineOffline.swift Tools/IceBaseline/IceBaselineSessionLifetimeTests.swift Tools/IceBaseline/IceBaselineController.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarProcessSignature.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOperationStop.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarIconActivation.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarIconIdentity.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarRecoveryJournal.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarMoveInterference.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarInputAttribution.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarHiddenInterferenceSource.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarListenOnlyInterferenceSource.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarHiddenMoveModel.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarDispatchWitness.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarMoveStageRecorder.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarRealLocalAuthorization.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarLocalDiagnosticReceipt.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarLocalContinuityLedger.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarLocalNoMoveInput.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarLocalAcceptanceGate.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarLocalStartReceipt.swift \
  -o "$ICE_BASELINE_CONTROLLER/Contents/MacOS/IceBaselineController"
swiftc -parse-as-library -module-cache-path "$ICE_BASELINE_ROOT/module-cache" \
  Tools/IceBaseline/FixtureDiagnostic.swift Tools/IceBaseline/IceBaselineFixture.swift \
  Tools/IceBaseline/IceBaselineSessionLifetime.swift \
  Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarProcessSignature.swift \
  -o "$ICE_BASELINE_FIXTURE/Contents/MacOS/IceBaselineTargets"
python3 - "$ICE_BASELINE_ROOT" <<'PY'
import pathlib,plistlib,sys
root=pathlib.Path(sys.argv[1])
for name,executable,identifier in [('Ice Baseline Controller.app','IceBaselineController','com.ryanai.mactools'),('Ice Baseline Targets.app','IceBaselineTargets','com.ryanai.mactools.nativetargets')]:
 (root/name/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable=executable,CFBundleIdentifier=identifier,CFBundleName=executable,CFBundlePackageType='APPL',CFBundleShortVersionString='0.11.12-baseline',CFBundleVersion='1',LSMinimumSystemVersion='14.0',LSUIElement=True)))
PY
codesign --force --sign "$ICE_BASELINE_SIGN" "$ICE_BASELINE_CONTROLLER"
codesign --force --sign "$ICE_BASELINE_SIGN" "$ICE_BASELINE_FIXTURE"
codesign --verify --deep --strict "$ICE_BASELINE_CONTROLLER"
codesign --verify --deep --strict "$ICE_BASELINE_FIXTURE"
"$ICE_BASELINE_CONTROLLER/Contents/MacOS/IceBaselineController" --offline-tests > "$ICE_BASELINE_ROOT/offline-tests.log"
python3 - "$ICE_BASELINE_ROOT" <<'PY'
import pathlib,hashlib,json,sys,datetime,subprocess,os,plistlib
root=pathlib.Path(sys.argv[1]); sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
sources=list(pathlib.Path('Tools/IceBaseline').glob('*.swift'))+[pathlib.Path('Tools/IceBaseline/upstream-receipt.json'),pathlib.Path('Tools/menu-bar-ice-baseline-session.py'),pathlib.Path('scripts/build-ice-baseline-candidate.sh'),pathlib.Path('Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarProcessSignature.swift'),pathlib.Path('Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOperationStop.swift')]
sources += [pathlib.Path('Tools/IceBaseline/product-source-list.json')] + [pathlib.Path(p) for p in json.loads(pathlib.Path('Tools/IceBaseline/product-source-list.json').read_text())]
formal=sha(pathlib.Path('/Applications/MacTools.app/Contents/MacOS/MacTools'))
originalHost='51e82865043c50b09fdee6883eb0a74096db8b865f393bf1d6b408cbe14b7c81'
assert formal == os.environ.get('MAC_TOOLS_APPROVED_HOST_SHA',originalHost), 'host differs from explicitly approved build baseline'
manifest=dict(revision='isolated-Ice-0.11.12-baseline-v3.7-ice-aligned-candidate',repository=str(pathlib.Path.cwd()),formalSHA256=formal,atUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),sourceCommit='d567f1ecac68936a090d6b47d6f0b882c489c6f4',controllerSHA256=sha(root/'Ice Baseline Controller.app/Contents/MacOS/IceBaselineController'),fixtureSHA256=sha(root/'Ice Baseline Targets.app/Contents/MacOS/IceBaselineTargets'),sources={str(p.resolve()):sha(p) for p in sources},policy='default owned Ice mouse tracking with no strict ANY gate; strict ANY retained only as explicit diagnostic; product backend unchanged',defaultSessionContract='isolatedOwnedQuietV1',strictANYRequiredForDefault=False,durableCandidate=dict(schemaVersion=1,recoveryDirectory=str(root/'candidate-recovery-v1'),reservedIntentIsActualPost=False),sessionLifetime=dict(readySeconds=120,operationSeconds=50,cleanupSeconds=15,absoluteSeconds=200,freshnessSeconds=1),nativeActionsDuringPreparation=0)
if formal != originalHost:
 app=pathlib.Path('/Applications/MacTools.app');info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
 assert (info['CFBundleIdentifier'],info['CFBundleShortVersionString'],info['CFBundleVersion'])==('com.ryanai.mactools','0.2.1','5')
 subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
 signature=subprocess.run(['codesign','-dvvv',str(app)],capture_output=True,text=True,check=True).stderr
 assert 'TeamIdentifier=58TJ64422P' in signature
 manifest['revision']='isolated-Ice-0.11.12-baseline-v3.7.1-authorized-host-binding'
 manifest['hostBaseline']=dict(path=str(app),binarySHA256=formal,bundleIdentifier=info['CFBundleIdentifier'],version=info['CFBundleShortVersionString'],build=info['CFBundleVersion'],team='58TJ64422P')
(root/'prepared-build.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({k:v for k,v in manifest.items() if k!='sources'},indent=2))
PY
