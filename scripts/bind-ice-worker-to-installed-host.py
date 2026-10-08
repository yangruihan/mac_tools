#!/usr/bin/env python3
"""Explicit release binding after an authorized MacTools install; no GUI/posts.

Requires the reviewed installed host's exact SHA as an argument. Never rebases
from a failed preflight and never changes recovery records or worker binaries.
"""
import argparse,datetime,hashlib,json,os,pathlib,plistlib,subprocess,tempfile
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--approved-sha256',required=True);args=parser.parse_args()
repo=pathlib.Path(__file__).resolve().parent.parent;root=pathlib.Path('/tmp/mac-tools-ice-baseline-candidate-20261007')
app=pathlib.Path('/Applications/MacTools.app');binary=app/'Contents/MacOS/MacTools';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(binary)==args.approved_sha256,'installed host differs from explicitly supplied release'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert (info['CFBundleIdentifier'],info['CFBundleShortVersionString'],info['CFBundleVersion'])==('com.ryanai.mactools','0.2.1','5')
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
sig=subprocess.run(['codesign','-dvvv',str(app)],capture_output=True,text=True,check=True).stderr
assert 'TeamIdentifier=58TJ64422P' in sig
rows=subprocess.check_output(['ps','-axo','pid=,comm='],text=True).splitlines()
assert not any('/mac-tools-ice-baseline-candidate-20261007/Ice Baseline' in s for s in rows),'worker active; do not rebind'
p=root/'prepared-build.json';original=p.read_bytes();manifest=json.loads(original)
expected=set(map(str,[*repo.glob('Tools/IceBaseline/*.swift'),repo/'Tools/IceBaseline/product-source-list.json',
 *[repo/f for f in json.loads((repo/'Tools/IceBaseline/product-source-list.json').read_text())],repo/'Tools/IceBaseline/upstream-receipt.json',
 repo/'Tools/menu-bar-ice-baseline-session.py',repo/'scripts/build-ice-baseline-candidate.sh',
 repo/'Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarProcessSignature.swift',repo/'Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOperationStop.swift']))
assert set(manifest['sources'])==expected
allowed={str(repo/'Tools/menu-bar-ice-baseline-session.py'),str(repo/'scripts/build-ice-baseline-candidate.sh')}
for source,digest in manifest['sources'].items():
 assert source in allowed or sha(pathlib.Path(source))==digest,source
for name,key,exe in [('Ice Baseline Controller.app','controllerSHA256','IceBaselineController'),('Ice Baseline Targets.app','fixtureSHA256','IceBaselineTargets')]:
 worker=root/name;assert sha(worker/'Contents/MacOS'/exe)==manifest[key]
 subprocess.run(['codesign','--verify','--deep','--strict',str(worker)],check=True)
recovery=json.loads(subprocess.check_output([str(root/'Ice Baseline Controller.app/Contents/MacOS/IceBaselineController'),'--inspect-recovery'],text=True))
assert recovery['journalPending'] is False,'do not rebind a retained responsibility'
archive=root/('host-baseline-before-'+sha(p)+'.json')
if not archive.exists():
 with archive.open('xb') as f:f.write(original);f.flush();os.fsync(f.fileno())
manifest.update(revision='isolated-Ice-0.11.12-baseline-v3.7.1-authorized-host-binding',formalSHA256=args.approved_sha256,
 hostBaseline={'path':str(app),'binarySHA256':args.approved_sha256,'bundleIdentifier':info['CFBundleIdentifier'],
 'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'team':'58TJ64422P','boundAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat()},
 sources={source:sha(pathlib.Path(source)) for source in manifest['sources']})
fd,tmp=tempfile.mkstemp(prefix='host-bind-',dir=root)
with os.fdopen(fd,'w') as f:json.dump(manifest,f,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())
assert p.read_bytes()==original,'manifest changed during binding'
os.replace(tmp,p)
fd=os.open(root,os.O_RDONLY);os.fsync(fd);os.close(fd)
print(json.dumps({'hostBound':True,'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'binarySHA256':args.approved_sha256,'revision':manifest['revision'],'workerBinariesChanged':False,'mousePosts':0,'windowsOpened':0,'recoveryChanged':False},indent=2))
