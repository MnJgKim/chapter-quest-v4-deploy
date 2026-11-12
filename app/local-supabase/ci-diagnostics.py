"""Print sanitized local-only CI diagnostics; never emit generated credentials."""
from pathlib import Path
import os,re,json,subprocess
root=Path(os.environ.get('RUNNER_TEMP','/tmp'));values=[]
def collect(value):
 if isinstance(value,dict):
  for v in value.values():collect(v)
 elif isinstance(value,str) and len(value)>8:values.append(value)
try:collect(json.loads((root/'cq-local-status.json').read_text()))
except Exception:pass
try:
 result=subprocess.run(['docker','logs','--tail','80','supabase_edge_runtime_cq-v4-local-qa'],text=True,capture_output=True,timeout=10)
 if result.returncode==0:(root/'cq-edge-runtime.log').write_text(result.stdout+result.stderr)
except Exception:pass
for name in ['supabase-start.log','cq-functions.log','cq-edge-runtime.log']:
 path=root/name
 if not path.exists():continue
 print(name)
 for line in path.read_text(errors='replace').splitlines()[-35:]:
  if re.search(r'password|secret.key|authorization|service.role.key|publishable.key',line,re.I):continue
  for value in sorted(values,key=len,reverse=True):line=line.replace(value,'[local-setting]')
  line=re.sub(r'eyJ[\w-]+\.[\w-]+\.[\w-]+','[local-jwt]',line)
  line=re.sub(r'(postgres(?:ql)?://)[^@\s]+@',r'\1[credentials]@',line)
  print(line)
