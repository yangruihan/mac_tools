#!/usr/bin/env python3
"""Isolated Ice baseline: default read-only; launch needs an explicit session.

The default session follows Ice mouse tracking, without strict ANY admission.
This helper never posts mouse events. The controller waits for local Start.
Do not reuse consumed sessions or invoke launch before coordinating the scene.
"""
import argparse
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys
import time
import uuid

ROOT = pathlib.Path('/tmp/mac-tools-ice-baseline-candidate-20261007')
REPO = pathlib.Path(__file__).resolve().parent.parent
FORMAL = pathlib.Path('/Applications/MacTools.app/Contents/MacOS/MacTools')
BUNDLES = {'controller': ('Ice Baseline Controller.app', 'IceBaselineController'),
           'fixture': ('Ice Baseline Targets.app', 'IceBaselineTargets')}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    return sorted([*REPO.glob('Tools/IceBaseline/*.swift'),
                   REPO/'Tools/IceBaseline/product-source-list.json',
                   *[REPO/p for p in json.loads((REPO/'Tools/IceBaseline/product-source-list.json').read_text())],
                   REPO/'Tools/IceBaseline/upstream-receipt.json',
                   REPO/'Tools/menu-bar-ice-baseline-session.py',
                   REPO/'scripts/build-ice-baseline-candidate.sh',
                   REPO/'Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarProcessSignature.swift',
                   REPO/'Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOperationStop.swift'])


def preflight():
    manifest = json.loads((ROOT/'prepared-build.json').read_text())
    assert manifest['sourceCommit'] == 'd567f1ecac68936a090d6b47d6f0b882c489c6f4'
    assert manifest['repository'] == str(REPO)
    expected = {str(p): sha(p) for p in sources()}
    assert manifest['sources'] == expected, 'source manifest changed/incomplete; rebuild required'
    # Installation was explicitly authorized after the original preservation
    # trial. A separate release binding pins the new host; never rebase here.
    assert sha(FORMAL) == manifest['formalSHA256'], 'bound host app changed'
    if manifest.get('hostBaseline'):
        host = manifest['hostBaseline']
        info = plistlib.loads((FORMAL.parent.parent/'Info.plist').read_bytes())
        assert host['binarySHA256'] == manifest['formalSHA256']
        assert info['CFBundleIdentifier'] == host['bundleIdentifier'] == 'com.ryanai.mactools'
        assert info['CFBundleShortVersionString'] == host['version'] and info['CFBundleVersion'] == host['build']
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(FORMAL.parent.parent.parent)], check=True, capture_output=True)
        signature = subprocess.run(['codesign', '-dvvv', str(FORMAL.parent.parent.parent)], check=True, capture_output=True, text=True).stderr
        assert 'TeamIdentifier='+host['team'] in signature and host['team'] == '58TJ64422P'
    else:
        assert manifest['formalSHA256'] == '51e82865043c50b09fdee6883eb0a74096db8b865f393bf1d6b408cbe14b7c81', 'original trial host changed'
    receipts = {}
    for kind, (name, exe) in BUNDLES.items():
        bundle = ROOT/name
        assert sha(bundle/'Contents/MacOS'/exe) == manifest[kind+'SHA256'], kind+' binary changed'
        result = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], capture_output=True, text=True)
        assert result.returncode == 0, kind+' signature invalid: '+result.stderr
        result = subprocess.run(['codesign', '-dv', '--verbose=4', str(bundle)], capture_output=True, text=True, check=True)
        receipts[kind] = result.stderr
    recovery = {'journalPending': False}
    if manifest.get('durableCandidate'):
        binary = ROOT/BUNDLES['controller'][0]/'Contents/MacOS'/BUNDLES['controller'][1]
        result = subprocess.run([str(binary), '--inspect-recovery'], capture_output=True, text=True, check=True)
        recovery = json.loads(result.stdout)
        assert isinstance(recovery.get('journalPending'), bool), 'recovery result missing'
    return {'prepared': True, 'manifest': manifest, 'signatureReceipts': receipts, 'recovery': recovery,
            'nativePosts': 0, 'nativeTaps': 0, 'windowsOpened': 0,
            'runtimePermissionsAndGeometry': 'checked on local Start; not claimed by static preflight'}


def write_new(path, value):
    with path.open('x') as handle:
        json.dump(value, handle, indent=2)
        handle.write('\n')


def prepare(contract="isolatedOwnedQuietV1"):
    assert not preflight()['recovery']['journalPending'], 'retained recovery blocks a new session; inspect, do not erase'
    nonce = str(uuid.uuid4()).upper()
    directory = ROOT/('session-'+nonce)
    directory.mkdir(mode=0o700)
    (directory/'owner-state').mkdir(mode=0o700)
    write_new(directory/'session.json', {'nonce': nonce, 'directory': str(directory),
        'preparedAtUnix': time.time(), 'nativeActions': 0, 'launched': False, 'contract': contract,
        'inputPolicy': 'strictANYDiagnostic' if contract == 'isolatedOwnedANYV1' else 'iceMouseTracking',
        'buildReceiptSHA256': sha(ROOT/'prepared-build.json')})
    return {'directory': str(directory), 'prepared': True, 'launched': False}


def launch(path):
    # This command is intentionally separate; preparation never launches apps.
    assert not preflight()['recovery']['journalPending'], 'retained recovery blocks launch; inspect, do not replay'
    directory = pathlib.Path(path)
    assert directory.parent == ROOT and directory.resolve() == ROOT.resolve()/directory.name
    nonce = directory.name.removeprefix('session-')
    uuid.UUID(nonce)
    session = json.loads((directory/'session.json').read_text())
    assert session['nonce'] == nonce and session['directory'] == str(directory)
    assert session.get('contract','isolatedOwnedQuietV1') in ('isolatedOwnedQuietV1','isolatedOwnedANYV1')
    assert session['buildReceiptSHA256'] == sha(ROOT/'prepared-build.json')
    assert not (directory/'action-consumed').exists(), 'one-shot action already consumed'
    assert not (directory/'result.json').exists(), 'session already terminal'
    write_new(directory/'launch-consumed.json', {'nonce': nonce, 'atUnix': time.time()})
    snapshot_binary = ROOT/BUNDLES['controller'][0]/'Contents/MacOS'/BUNDLES['controller'][1]
    snapshot = subprocess.run([str(snapshot_binary), '--status-snapshot'], capture_output=True, text=True, check=True)
    write_new(directory/'status-before-fixture.json', json.loads(snapshot.stdout))
    pid_records = {}
    for kind in ('fixture', 'controller'):
        name, exe = BUNDLES[kind]
        binary = ROOT/name/'Contents/MacOS'/exe
        args = ([str(binary), '--diagnostic-directory', str(directory/'owner-state'), '--diagnostic-nonce', nonce]
                if kind == 'fixture' else [str(binary), '--session', str(directory)])
        with (directory/(kind+'.stdout.log')).open('xb') as out, (directory/(kind+'.stderr.log')).open('xb') as err:
            child = subprocess.Popen(args, stdout=out, stderr=err, start_new_session=True)
        pid_records[kind] = {'pid': child.pid, 'executable': str(binary), 'args': args}
        write_new(directory/(kind+'-process.json'), pid_records[kind])
        if kind == 'fixture':
            deadline = time.monotonic()+5
            while time.monotonic() < deadline:
                if child.poll() is not None:
                    raise RuntimeError('fixture exited; inspect fixture.stderr.log; no controller launch')
                try:
                    owner = json.loads((directory/'owner-state/latest.json').read_text())
                    if (owner['nonce'] == nonce and owner['pid'] == child.pid
                            and owner['phase'] == 'timer'
                            and 0 <= time.time()-owner['atUnix'] <= 1):
                        break
                except (OSError, ValueError, KeyError):
                    pass
                time.sleep(0.05)
            else:
                raise RuntimeError('fixture publication timed out; retained process record; no controller/events')
    return {'directory': str(directory), 'processes': pid_records,
            'localStartRequired': True, 'nativePostsByHelper': 0}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--preflight', action='store_true')
    mode.add_argument('--prepare-session', action='store_true')
    mode.add_argument('--prepare-ice-aligned', action='store_true', help='Prepare the default Ice-aligned owned session; no strict ANY gate.')
    mode.add_argument('--prepare-native-any', action='store_true')
    mode.add_argument('--launch-session', metavar='EXACT_PREPARED_DIRECTORY')
    args = parser.parse_args()
    result = prepare("isolatedOwnedANYV1") if args.prepare_native_any else prepare() if args.prepare_session or args.prepare_ice_aligned else launch(args.launch_session) if args.launch_session else preflight()
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(json.dumps({'prepared': False, 'failure': str(error), 'nativePostsByHelper': 0}), file=sys.stderr)
        sys.exit(1)
