from pathlib import Path
import subprocess,json,hashlib,shutil,uuid
repo=Path.cwd();D=repo/'docs/evidence/menu-bar-ice-flow-first-2026-10-09';rows=[line.split('\t') for line in (D/'stage1-baseline/paths.tsv').read_text().splitlines()];baseline=D/'stage1-baseline/Source';modified=D/'stage1-modified-sources'
copy=Path.home()/'Library/Caches'/('MacTools-stage1-transaction-'+str(uuid.uuid4()));copy.mkdir();ledger=[]
def run(label,cmd):
 p=subprocess.run(cmd,capture_output=True,text=True);v={'label':label,'command':cmd,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr};ledger.append(v);print(json.dumps(v,indent=2));return p
for a,rel in rows:
 if a=='restore':dst=copy/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(baseline/rel,dst)
check=['python3',str(D/'stage1-source-check.py'),str(copy)]
assert run('stage1-final-BASELINE',check).returncode==1
for a,rel in rows:
 dst=copy/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(modified/rel,dst)
assert run('stage1-final-MODIFIED',check).returncode==0
assert run('stage1-final-ROLLBACK-execute',[str(D/'ROLLBACK.sh'),'--stage1',str(copy)]).returncode==0
assert run('stage1-final-ROLLBACK',check).returncode==1
hashes=json.loads((D/'stage1-baseline/sources-before.json').read_text());h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for a,rel in rows:
 if a=='restore':assert h(copy/rel)==hashes[rel]['sha256'],rel
 else:assert not (copy/rel).exists(),rel
assert run('stage1-final-reapply',['patch','-p1','-d',str(copy),'-i',str(D/'stage1-sources.patch')]).returncode==0
for a,rel in rows:assert (copy/rel).read_bytes()==(modified/rel).read_bytes()==(repo/rel).read_bytes(),rel
assert run('stage1-final-MODIFIED-reapplied',check).returncode==0
# An unrelated edit must block the whole rollback before any source is restored.
tamper=copy/rows[0][1];tamper.write_bytes(tamper.read_bytes()+b'\n// unrelated edit\n');edited=h(tamper);other=h(copy/rows[1][1]);assert run('stage1-final-ROLLBACK-unrelated-edit-rejected',[str(D/'ROLLBACK.sh'),'--stage1',str(copy)]).returncode==1;assert h(tamper)==edited and h(copy/rows[1][1])==other;shutil.copyfile(modified/rows[0][1],tamper)
v={'restoredOriginalHashes':True,'reappliedEqualsNormalSourceBytes':True,'unrelatedEditPreserved':True,'fileCount':len(rows),'copy':str(copy),'patchSHA256':h(D/'stage1-sources.patch'),'modifiedSHA256':{rel:h(modified/rel) for a,rel in rows},'originalSHA256':hashes};(D/'stage1-final-transaction.json').write_text(json.dumps(v,indent=2)+'\n');(D/'stage1-final-command-ledger.json').write_text(json.dumps(ledger,indent=2)+'\n')
with (D/'VERIFICATION.txt').open('a') as f:f.write('\nSTAGE1 FINAL SAME-INPUT BASELINE / MODIFIED / ROLLBACK / REAPPLY\n'+json.dumps(ledger,indent=2)+'\n'+json.dumps(v,indent=2)+'\n')
print(json.dumps({'passed':True,'fileCount':len(rows),'restoredOriginalHashes':True,'reappliedEqualsNormalSourceBytes':True,'unrelatedEditPreserved':True},indent=2))
