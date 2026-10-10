from pathlib import Path
import json
D=Path(__file__).resolve().parent
read=lambda name:json.loads((D/(name+'.json')).read_text())
def verify_pair(before,after,both=False):
    a,b=read(before),read(after)
    assert a['host']['pid']!=b['host']['pid']
    assert b['host']['enabled'] and b['host']['presentationMode']=='panel' and b['host']['visibleLimit']==7
    assert a['host']['savedSettings']==b['host']['savedSettings']
    assert b['host']['savedSettings']=={'optedIn':'true','presentationMode':'"panel"','visibleLimit':'7'}
    for key,expected in [('order',['N','R','T']),('hidden',['N','R']),('resident',['T'])]:
        assert a[key]==b[key]==expected
    if both:
        assert a['fixture']['pid']!=b['fixture']['pid']
        assert a['fixture']['items']!=b['fixture']['items']
        assert a['fixture']['savedPositions']==b['fixture']['savedPositions']
        assert all(isinstance(v,(int,float)) for v in b['fixture']['savedPositions'].values())
    else:assert a['fixture']['pid']==b['fixture']['pid']
verify_pair('before-host-restart','after-host-restart')
verify_pair('before-graceful-both-restart','after-graceful-both-restart',both=True)
a,b=read('disabled-before-restart'),read('disabled-after-restart')
assert a['host']['pid']!=b['host']['pid'] and not b['host']['enabled']
assert b['host']['control']==b['host']['divider']==0
assert a['host']['savedSettings']==b['host']['savedSettings']
assert b['host']['savedSettings']=={'optedIn':'false','presentationMode':'"panel"','visibleLimit':'7'}
assert b['host']['presentationMode']=='panel' and b['host']['visibleLimit']==7
failed=read('after-both-restart')
assert failed['order']!=read('before-both-restart')['order']
assert all(v=='missing' for v in failed['fixture']['savedPositions'].values())
print(json.dumps({'passed':True,'hostRestart':True,'hostAndNamedFixtureGracefulRestart':True,'disabledRestart':True,'order':['N','R','T'],'hidden':['N','R'],'resident':['T'],'settingsReadBackWithoutRewrite':True,'originalExplicitRemovalFixtureFailureRetained':True,'OSRebootTested':False},indent=2))
