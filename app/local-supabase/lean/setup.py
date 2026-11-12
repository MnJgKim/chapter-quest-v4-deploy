"""Apply the schema-only fixture to the named local container. No remote URL input."""
from pathlib import Path
import os,subprocess,time,urllib.request
root=Path(__file__).resolve().parent;env=os.environ.copy()
for key in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']:env.pop(key,None)
base=['docker','--host=unix:///var/run/docker.sock','exec','-i','cq-v4-local-qa-db-1','psql','-U','postgres','-X','-v','ON_ERROR_STOP=1','-At']
def sql(value):
 r=subprocess.run(base,input=value,env=env,capture_output=True,text=True)
 if r.returncode:raise SystemExit('Local schema setup failed; hosted targets were never used.')
 return r.stdout.strip()
for _ in range(30):
 try:
  with urllib.request.urlopen('http://127.0.0.1:9999/health',timeout=2) as response:
   if response.status==200:break
 except Exception:time.sleep(1)
else:raise SystemExit('Local Auth did not become healthy.')
if sql("select to_regclass('public.cq_v4_activities') is null;")=='t':
 fixture=next((root.parent/'supabase/migrations').glob('*cq_local_schema.sql'));sql(fixture.read_text())
sql("create or replace function auth.uid() returns uuid language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),current_setting('request.jwt.claims',true)::jsonb->>'sub')::uuid $$;notify pgrst,'reload schema';")
candidate=next((root.parent/'supabase/migrations').glob('*cq_parent_lesson_context.sql'))
if sql("select to_regprocedure('public.cq_v4_parent_lesson(uuid)') is null;")=='t':sql(candidate.read_text())
print('Local schema-only fixture and JWT helper ready. No production link is configured.')
