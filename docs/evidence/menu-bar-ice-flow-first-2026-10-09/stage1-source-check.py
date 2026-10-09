from pathlib import Path
import sys,json
root=Path(sys.argv[1]);files=['scripts/build-ice-interface-product-worker.sh','scripts/build-ice-interface-product-candidate.sh','Tools/IceInterfaceProductWorker/IceSelectedSession.swift','Tools/IceInterfaceProduct/MenuBarIceInterfaceProductBridge.swift'];issues=[]
for rel in files:
 s=(root/rel).read_text()
 if '/tmp/mac-tools-' in s:issues.append(rel+': depends on dated temporary candidate')
 if '/docs/evidence/' in s:issues.append(rel+': depends on evidence source')
 if '/Users/yangruihan/Workspace/mac_tools/' in s:issues.append(rel+': depends on developer workspace at runtime')
worker=(root/files[2]).read_text();host=(root/files[3]).read_text()
if 'Bundle.main.bundleURL.deletingLastPathComponent()' not in worker:issues.append('worker resource root not executable-relative')
if 'Bundle.main.resourceURL!' not in host:issues.append('host worker root not packaged resource')
if 'applicationSupportDirectory' not in worker or 'applicationSupportDirectory' not in host:issues.append('persistent state not separated from build resources')
print(json.dumps({'passed':not issues,'issues':issues,'checkedFiles':files,'nativePosts':0},indent=2));sys.exit(1 if issues else 0)
