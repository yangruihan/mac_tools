from pathlib import Path
import json
D=Path(__file__).resolve().parent
read=lambda path:json.loads((D/path).read_text())
failed=read('session-9CCFCFEC-77E4-48DE-925E-99721ECDB993/result.json')
assert failed['failure']=='binding' and failed['posts']==0
assert not read('session-9CCFCFEC-77E4-48DE-925E-99721ECDB993/cleanup.json')['journalPending']
fixture=read('fixture-fresh-start.json')
source=next(x['windowID'] for x in fixture['items'] if x['title']=='N')
results=[]
for name in ['session-1ED9E38E-B424-43F8-AB9A-146107D6B685','session-5C620D0E-8927-4A59-AC9D-1BA454F7E1B6']:
    x=read(name+'/result.json')
    assert x['posts']==14 and x['realClosedLoopVerified'] and x['icePositionVerified']
    assert x['journal']['phase']=='returned' and x['journal']['clearAdmitted']
    assert not x['journal']['pendingRecovery'] and not x['journal']['possibleDown']
    assert x['interfaceCompletion']['kind']=='ordinaryWindow' and x['interfaceCompletion']['nativeObservation']
    assert x['returnEvidence']['targetID']==source and x['returnEvidence']['targetPID']==fixture['pid']
    seconds=x['returnEvidence']['atUptime']-x['interfaceCompletion']['firstInactiveAt']
    assert seconds>=15
    assert not read(name+'/cleanup.json')['journalPending']
    results.append({'session':name,'posts':14,'inactiveToReturnProofSeconds':seconds,'trackedWindowID':x['interfaceCompletion']['windowID'],'returned':True})
closed=read('candidate-new-window-closed.json')
assert closed['nativeClicks']['N']==1 and not closed['ordinaryWindows'][0]['visible']
before=read('existing-background-before.json');active=read('existing-background-reactivated.json');after=read('candidate-background-fixture-after.json')
assert before['ordinaryWindows'][0]['visible'] and not before['ownerActive']
assert active['nativeClicks']['N']==2 and active['ownerActive']
assert active['ordinaryWindows'][0]['windowID']==before['ordinaryWindows'][0]['windowID']==results[1]['trackedWindowID']
assert after['ordinaryWindows'][0]['visible'] and not after['ownerActive']
for name in ['candidate-new-window-after.json','candidate-background-after.json']:
    x=read(name);assert x['visibility']=='collapsed' and not x['workerRunning']
assert read('user-icon-order.json')['relativeOrderEqual']
print(json.dumps({'passed':True,'cases':results,'restoredCollapsed':True,'nonfixtureOrderUnchanged':True},indent=2))
