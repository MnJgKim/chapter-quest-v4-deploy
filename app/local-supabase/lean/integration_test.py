"""Real local Supabase Auth + PostgreSQL + PostgREST; no hosted requests.
Storage objects are SQL fixtures, not evidence of Storage API/Edge behavior.
"""
from pathlib import Path
import json,os,subprocess,secrets,urllib.request,urllib.error,time,uuid,base64,hmac,hashlib
ROOT=Path(__file__).resolve().parent;runtime=ROOT/'runtime'
report={'scope':'real local GoTrue v2.197.0, PostgreSQL 17 and PostgREST v16.5; synthetic users only; storage objects are SQL fixtures; hosted/Edge/Storage API/AI not tested','checks':[]}
env=os.environ.copy()
for k in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']:env.pop(k,None)
def sql(query):
 r=subprocess.run(['docker','--host=unix:///var/run/docker.sock','exec','-i','cq-v4-local-qa-db-1','psql','-U','postgres','-X','-v','ON_ERROR_STOP=1','-At'],input=query,env=env,capture_output=True,text=True)
 if r.returncode:raise RuntimeError('Local SQL operation failed: '+r.stderr[-500:])
 return r.stdout.strip()
def req(service,path,data=None,token=None,method=None):
 base={'auth':'http://127.0.0.1:9999','rest':'http://127.0.0.1:3000'}[service]
 headers={'Content-Type':'application/json'}
 if token:headers['Authorization']='Bearer '+token
 request=urllib.request.Request(base+path,data=json.dumps(data).encode() if data is not None else None,headers=headers,method=method or ('POST' if data is not None else 'GET'))
 try:
  with urllib.request.urlopen(request,timeout=10) as r:return r.status,json.load(r)
 except urllib.error.HTTPError as e:
  try:body=json.load(e)
  except:body={}
  return e.code,body

def passed(name):report['checks'].append({'name':name,'pass':True})
def rpc(name,args=None,token=None):return req('rest','/rpc/'+name,args or {},token)
def ok(result):
 status,body=result
 if status not in [200,201]:raise AssertionError('Local API rejected operation: HTTP '+str(status)+' code '+str(body.get('code') if isinstance(body,dict) else ''))
 return body
try:
 sql("create or replace function auth.uid() returns uuid language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),current_setting('request.jwt.claims',true)::jsonb->>'sub')::uuid $$;notify pgrst,'reload schema';")
 identities={}
 for name in ['parent','student','outsider']:
  email=name+'-'+secrets.token_hex(6)+'@example.test';password=secrets.token_urlsafe(32)
  created=ok(req('auth','/signup',{'email':email,'password':password}));assert created.get('user',created).get('id')
  login=ok(req('auth','/token?grant_type=password',{'email':email,'password':password}));assert login['access_token'] and login['refresh_token']
  identities[name]={'uid':login['user']['id'],'token':login['access_token'],'refresh':login['refresh_token'],'email':email,'password':password}
 passed('three synthetic accounts sign up and log in through real local Auth')
 parent,child,other=(identities[x] for x in ['parent','student','outsider'])
 assert req('auth','/token?grant_type=password',{'email':child['email'],'password':'incorrect-password'})[0]==400;passed('wrong password is denied by real local Auth')
 assert ok(req('auth','/user',token=child['token']))['id']==child['uid'];passed('Auth verifies the issued student token')
 assert ok(rpc('cq_is_admin',token=parent['token'])) is False
 sql("insert into public.cq_admins(user_id) values('"+parent['uid']+"');")
 assert ok(rpc('cq_is_admin',token=parent['token'])) is True;assert ok(rpc('cq_is_admin',token=child['token'])) is False;passed('parent authorization is enforced through JWT and cq_admins')
 assert rpc('cq_v4_my_chapters')[0] in [401,403];passed('anonymous caller cannot list chapters')
 assert rpc('cq_v4_issue_invite',token=child['token'])[0]==403;passed('student cannot issue parent invitations')
 invite=ok(rpc('cq_v4_issue_invite',token=parent['token']));assert len(invite)==48
 assert ok(rpc('cq_v4_claim_invite',{'p_token':invite,'p_student_name':'Synthetic Student'},child['token'])) is True
 links=ok(rpc('cq_v4_list_child_access',token=parent['token']));assert any(x['child_user_id']==child['uid'] and not x['active'] for x in links);passed('real student invitation claim is pending until parent approval')
 assert ok(rpc('cq_v4_approve_child',{'p_child_user_id':child['uid']},parent['token'])) is True;passed('parent explicitly approves local student enrollment')
 chapter=str(uuid.uuid4());request_key=str(uuid.uuid4())
 sql("insert into public.cq_v4_pdf_chapters(chapter_id,parent_user_id,title,storage_path,pdf_ready,pdf_verified_at) values('"+chapter+"','"+parent['uid']+"','Synthetic lesson','"+parent['uid']+'/'+chapter+".pdf',true,now());")
 payload={'p_request_key':request_key,'p_book_id':'local-qa-book','p_chapter_id':'local-qa-chapter','p_title':'Synthetic lesson','p_source':'A reader helped a friend. '*20,'p_questions':[{'kind':'mc','text':'Who helped?','options':['A reader','Nobody']},{'kind':'inference','text':'Why?'}],'p_answer_key':[0,'To help a friend.'],'p_vocabulary':[{'word':'reader','meaning':'독자','example':'A reader helps.'}],'p_writing_prompt':'Explain.','p_speaking_prompt':'Summarize.'}
 approval=ok(rpc('cq_v4_register_approval_once',payload,parent['token']));assert ok(rpc('cq_v4_register_approval_once',payload,parent['token']))==approval;passed('approval registration is idempotent through real REST')
 assert rpc('cq_v4_register_approval_once',{**payload,'p_title':'Changed'},parent['token'])[0]==409;passed('reusing request key with different content is denied')
 assert ok(rpc('cq_v4_bind_verified_pdf',{'p_approval_id':approval,'p_chapter_uuid':chapter},parent['token']))==chapter
 assert ok(rpc('cq_v4_publish_approved',{'p_approval_id':approval,'p_children':[child['uid']]},parent['token']))==chapter;passed('parent binds verified PDF fixture and publishes to approved student')
 chapters=ok(rpc('cq_v4_my_chapters',token=child['token']));assert len(chapters)==1 and chapters[0]['chapter_uuid']==chapter and 'answer_key' not in json.dumps(chapters) and 'correct' not in json.dumps(chapters);passed('assigned student sees published questions without answer keys')
 assert ok(rpc('cq_v4_my_chapters',token=other['token']))==[];passed('unassigned authenticated account sees no chapters')
 assert req('rest','/cq_v4_approval_requests?select=*',token=child['token'])[0]==403;passed('direct approval answer-key table access is denied')
 ok(req('auth','/user',{'data':{'role':'parent'}},child['token'],method='PUT'));assert ok(rpc('cq_is_admin',token=child['token'])) is False;passed('editable user metadata cannot grant parent authorization')
 args={'p_chapter_uuid':chapter};assert len(ok(rpc('cq_v4_my_chapter_activities',args,child['token'])))==1
 full={'readComplete':True,'answers':['0','To help a friend.'],'essay':'The reader helped.','speaking':'I will summarize.','hasAudio':True}
 assert rpc('cq_v4_submit_answers',{**args,'p_answers':full},child['token'])[0]==400;passed('submission without uploaded storage object is denied')
 # Test the actual SQL storage policy; no Storage API is claimed here.
 claims=json.dumps({'sub':child['uid'],'role':'authenticated'})
 sql("begin;set local role authenticated;select set_config('request.jwt.claims','"+claims+"',true);insert into storage.objects(bucket_id,name,metadata) values('cq-v4-speaking','"+child['uid']+'/'+chapter+".webm','{\"size\":123,\"mimetype\":\"audio/webm\"}');commit;")
 passed('authorized student audio-object INSERT passes the copied real RLS policy')
 assert rpc('cq_v4_submit_answers',{**args,'p_answers':{**full,'answers':['0']}},child['token'])[0]==400;passed('short answer array is rejected through real REST')
 assert rpc('cq_v4_submit_answers',{**args,'p_answers':{**full,'answers':['9','Text']}},child['token'])[0]==400;passed('out-of-range multiple-choice answer is rejected')
 assert rpc('cq_v4_parent_lesson',args)[0] in [401,403];passed('anonymous caller cannot execute the parent answer-key read API')
 context=ok(rpc('cq_v4_parent_lesson',args,parent['token']));assert len(context)==1 and context[0]['answer_key'][0]==0;passed('real parent JWT can retrieve owned question text and model answers')
 assert rpc('cq_v4_parent_lesson',args,child['token'])[0]==403;passed('real student JWT cannot retrieve parent model answers')
 assert rpc('cq_v4_parent_lesson',args,other['token'])[0]==403;passed('unrelated non-parent account cannot read parent lesson context')
 assert len(ok(rpc('cq_v4_submit_answers',{**args,'p_answers':full},child['token'])))==1;passed('complete authorized student submission succeeds')
 ok(rpc('cq_v4_submit_answers',{**args,'p_answers':{**full,'essay':'Changed'}},child['token']))
 rows=ok(rpc('cq_v4_parent_submissions',token=parent['token']));assert rows[0]['answers']['essay']==full['essay'];passed('duplicate submission preserves the original essay')
 ok(rpc('cq_v4_release_feedback',{'p_child_user_id':child['uid'],'p_chapter_uuid':chapter,'p_feedback':'Private draft','p_release':False},parent['token']))
 assert ok(rpc('cq_v4_my_submission',args,child['token']))[0]['feedback'] is None;passed('unreleased parent feedback is hidden')
 ok(rpc('cq_v4_release_feedback',{'p_child_user_id':child['uid'],'p_chapter_uuid':chapter,'p_feedback':'Great work!','p_release':True},parent['token']))
 assert ok(rpc('cq_v4_my_submission',args,child['token']))[0]['feedback']=='Great work!';passed('released parent feedback is visible only to the assigned student')
 assert ok(rpc('cq_v4_my_submission',args,other['token']))==[];passed('unrelated authenticated account cannot read the submission')
 refreshed=ok(req('auth','/token?grant_type=refresh_token',{'refresh_token':child['refresh']}));assert refreshed['user']['id']==child['uid'];passed('real Auth refresh token retains the student identity')
 # Preserve local credentials in ignored runtime only for an additional browser check.
 p=runtime/'test-accounts.json';p.write_text(json.dumps({'accounts':identities,'chapter':chapter}));p.chmod(0o600)
 passed('credentials remain only in ignored local runtime, never test report')
except Exception as error:
 report['failure']=str(error)
finally:
 destination=Path(__import__('sys').argv[1] if len(__import__('sys').argv)>1 else ROOT/'results.json');destination.write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
if 'failure' in report:raise SystemExit(1)
