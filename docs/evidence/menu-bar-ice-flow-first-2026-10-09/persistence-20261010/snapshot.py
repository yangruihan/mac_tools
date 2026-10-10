from pathlib import Path
import json,sys,time
D=Path(__file__).resolve().parent
scope=json.loads((D/'scope.json').read_text())
host=json.loads(Path(scope['state']).read_text());fixture=json.loads(Path(scope['fixtureConfig']).read_text())
assert time.time()-host['atUnix']<2 and time.time()-fixture['atUnix']<2
rows={x['kCGWindowNumber']:x for x in host['windows']}
result={'host':host,'fixture':fixture,'order':[],'hidden':[],'resident':[]}
if host['enabled']:
    divider=rows[host['divider']]['kCGWindowBounds'];lo=divider['X'];hi=lo+divider['Width']
    items=[]
    for item in fixture['items']:
        row=rows[item['windowID']];assert row['kCGWindowOwnerPID']==fixture['pid']
        f=row['kCGWindowBounds'];items.append((f['X'],item['title']))
        if f['X']+f['Width']<=lo+1:result['hidden'].append((f['X'],item['title']))
        elif f['X']>=hi-1:result['resident'].append((f['X'],item['title']))
        else:raise AssertionError('fixture intersects divider')
    result['order']=[title for _,title in sorted(items)]
    for key in ['hidden','resident']:result[key]=[title for _,title in sorted(result[key])]
(D/(sys.argv[1]+'.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['order','hidden','resident']}));print(host['savedSettings'])
