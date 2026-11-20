"""Verify backup/restore ONLY in the fixed synthetic local container; never overwrite a DB."""
import hashlib,json,os,secrets,subprocess,sys
from pathlib import Path
container='cq-v4-local-qa-db-1'
env=os.environ.copy()
for key in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']:env.pop(key,None)
base=['docker','--host=unix:///var/run/docker.sock','exec','-i',container]
report={'scope':'synthetic local PostgreSQL only; no hosted requests or data deletion','checks':[]}
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True);out.chmod(0o700)
def command(args,**kwargs):
 result=subprocess.run(base+args,env=env,capture_output=True,**kwargs)
 if result.returncode:raise RuntimeError('Local backup/restore command failed; private diagnostics not logged')
 return result.stdout

def sql(database,query):return command(['psql','-U','postgres','-d',database,'-X','-v','ON_ERROR_STOP=1','-At'],input=query.encode()).decode().strip()
def snapshot(database):
 names=json.loads(sql(database,"select coalesce(json_agg(json_build_array(schemaname,tablename) order by schemaname,tablename),'[]') from pg_tables where schemaname in ('public','auth','storage');"))
 rows={}
 for schema,name in names:
  table='"'+schema.replace('"','""')+'"."'+name.replace('"','""')+'"'
  payload=sql(database,'select coalesce(string_agg(row_to_json(t)::text,E\'\\n\' order by row_to_json(t)::text),\'\') from '+table+' t;')
  rows[schema+'.'+name]=hashlib.sha256(payload.encode()).hexdigest()
 security=sql(database,"select json_agg(row_to_json(t) order by t.nspname,t.relname) from (select n.nspname,c.relname,c.relrowsecurity,c.relacl::text from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','auth','storage') and c.relkind='r')t;")
 functions=sql(database,"select string_agg(pg_get_functiondef(p.oid),E'\\n' order by n.nspname,p.proname,p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','auth') and p.prokind='f';")
 return rows,security,functions
try:
 before=snapshot('postgres');archive=out/'synthetic-db.backup'
 with archive.open('xb') as file:
  archive.chmod(0o600);file.write(command(['pg_dump','-U','postgres','-Fc','postgres']))
 report['checks'].append({'name':'private custom-format backup created without logging records or credentials','pass':True})
 restored='cq_restore_check_'+secrets.token_hex(6);sql('postgres','create database '+restored+' template template0;')
 command(['pg_restore','-U','postgres','-d',restored,'--exit-on-error'],input=archive.read_bytes())
 after=snapshot(restored)
 assert before[0]==after[0];report['checks'].append({'name':'all public/Auth/Storage fixture rows preserved in independent restored DB','pass':True})
 assert before[1]==after[1];report['checks'].append({'name':'table privileges and RLS flags preserved','pass':True})
 assert before[2]==after[2];report['checks'].append({'name':'public/Auth function definitions preserved','pass':True})
 assert before==snapshot('postgres');report['checks'].append({'name':'source DB unchanged; no DROP/TRUNCATE/DELETE or existing DB overwrite','pass':True})
except Exception as error:report['failure']=str(error)
(out/'results.json').write_text(json.dumps(report,indent=2));print(json.dumps({'checks':len(report['checks']),'passed':not bool(report.get('failure'))}));sys.exit(1 if report.get('failure') else 0)
