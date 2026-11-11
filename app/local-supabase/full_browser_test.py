"""Full real local Auth/Storage/Edge browser flow. Never accepts a hosted URL.
The model is not called: a synthetic parent-reviewed JSON draft is used.
"""
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
import json,threading,functools,sys,secrets,urllib.request,urllib.error,subprocess,uuid,time,os
from playwright.sync_api import sync_playwright,expect
ROOT=Path(__file__).resolve().parents[1];out=Path(sys.argv[2]);out.parent.mkdir(parents=True,exist_ok=True)
status=json.loads(Path(sys.argv[1]).read_text())
def public_key(value):
 if isinstance(value,dict):
  for key,item in value.items():
   if key.lower() in ['anon_key','publishable_key'] and isinstance(item,str):return item
  for item in value.values():
   found=public_key(item)
   if found:return found
 if isinstance(value,str) and value.startswith('sb_publishable_'):return value
 if isinstance(value,str) and value.count('.')==2:
  try:
   part=value.split('.')[1];claims=json.loads(__import__('base64').urlsafe_b64decode(part+'='*(-len(part)%4)))
   if claims.get('role')=='anon':return value
  except Exception:pass
 return None
anon=public_key(status);assert anon,'Local public key unavailable'
base='http://127.0.0.1:54321';report={'scope':'real local Supabase Auth, PostgreSQL, Storage and Edge functions; generated synthetic users/PDF/audio only; no hosted data or AI calls','checks':[],'page_errors':[],'blocked_requests':[]};private=[anon]
def passed(name):report['checks'].append({'name':name,'pass':True})
def api(path,data=None,token=None):
 headers={'Content-Type':'application/json','apikey':anon}
 if token:headers['Authorization']='Bearer '+token
 request=urllib.request.Request(base+path,data=json.dumps(data).encode() if data is not None else None,headers=headers)
 with urllib.request.urlopen(request,timeout=20) as r:return json.load(r)
class Assets(SimpleHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_GET(self):
  if self.path=='/project-config.js':
   payload=('window.CQ_PUBLIC_PROJECT='+json.dumps({'url':base,'anonKey':anon})+';').encode();self.send_response(200);self.send_header('Content-Type','application/javascript');self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload)
  else:super().do_GET()
server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Assets,directory=str(ROOT/'public')));threading.Thread(target=server.serve_forever,daemon=True).start();origin=f'http://127.0.0.1:{server.server_port}'
try:
 users={}
 for role in ['parent','student','outsider']:
  email=role+'-'+secrets.token_hex(6)+'@example.test';password=secrets.token_urlsafe(24);private.append(password)
  api('/auth/v1/signup',{'email':email,'password':password});login=api('/auth/v1/token?grant_type=password',{'email':email,'password':password});private.append(login['access_token']);private.append(login['refresh_token']);users[role]={'token':login['access_token'],'email':email,'password':password,'uid':str(uuid.UUID(login['user']['id']))}
 passed('three synthetic accounts sign up and log in on the full local stack')
 try:api('/functions/v1/cq-v4-pdf-parent',{'action':'create_chapter','title':'Must be denied'},users['outsider']['token']);raise AssertionError('Non-parent Edge request was not denied')
 except urllib.error.HTTPError as error:assert error.code==403
 passed('real Edge parent endpoint denies a non-parent account before privileged writes')
 env=os.environ.copy()
 for k in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']:env.pop(k,None)
 query="insert into public.cq_admins(user_id) values('"+users['parent']['uid']+"');"
 subprocess.run(['docker','--host=unix:///var/run/docker.sock','exec','-i','supabase_db_cq-v4-local-qa','psql','-U','postgres','-v','ON_ERROR_STOP=1'],input=query,env=env,text=True,capture_output=True,check=True)
 source='Mina helped Leo find a lost book. They searched the library together. Leo thanked Mina for being patient and kind. '*8
 fixture={'questions':[{'kind':'mc','text':'Who helped Leo?','options':['Mina','Nobody'],'correct':0},{'kind':'inference','text':'Why did they search together?','sample':'They wanted to find the book.'}],'vocabulary':[{'word':'patient','meaning':'참을성 있는','example':'Mina was patient.'}],'writingPrompt':'Explain how Mina helped.','speakingPrompt':'Summarize the chapter.'}
 txt=out.parent/'cq-original.txt';txt.write_text(source);draft=out.parent/'cq-draft.json';draft.write_text(json.dumps(fixture))
 with sync_playwright() as p:
  browser=p.chromium.launch(args=['--no-sandbox','--use-fake-device-for-media-stream','--use-fake-ui-for-media-stream'])
  def page():
   context=browser.new_context(permissions=['microphone'],viewport={'width':1280,'height':900});context.set_default_timeout(30000)
   def route(r):
    if r.request.url.startswith(origin+'/') or r.request.url.startswith(base+'/'):r.continue_()
    else:report['blocked_requests'].append(r.request.url);r.abort()
   context.route('**/*',route);tab=context.new_page();tab.on('dialog',lambda d:d.accept('123456') if d.type=='prompt' else d.accept());tab.on('pageerror',lambda e:report['page_errors'].append(str(e)));tab.goto(origin);return tab
  pp=page();pp.locator('#parentBtn').click();pp.locator('#cloudEmail').fill(users['parent']['email']);pp.locator('#cloudPassword').fill(users['parent']['password']);pp.locator('[data-cloud="login"]').click();expect(pp.locator('#cloudStatus')).to_contain_text('로그인 성공');passed('parent browser is authorized through real Auth and admin RPC')
  pp.locator('[data-parent-invite="issue"]').click();expect(pp.locator('#cqInviteCode')).to_have_text(__import__('re').compile('^[0-9a-f]{48}$'));invite=pp.locator('#cqInviteCode').inner_text();private.append(invite)
  sp=page();sp.locator('#cqChildEmail').fill(users['student']['email']);sp.locator('#cqChildPassword').fill(users['student']['password']);sp.locator('[data-child="login"]').click();expect(sp.locator('#cqChildInvite')).to_be_visible();sp.locator('#cqChildInvite').fill(invite);sp.locator('#cqChildInviteName').fill('Synthetic Student');sp.locator('[data-child="claim"]').click();expect(sp.locator('#cqChildStatus')).to_contain_text('연결 요청 완료');pp.locator('[data-parent-invite="refresh"]').click();pp.locator('[data-parent-invite="approve"]').click();expect(pp.locator('#cqInviteStatus')).to_contain_text('승인 완료');passed('real invitation claim and parent enrollment approval')
  pp.locator('#bookTitle').fill('Synthetic Local Book');pp.locator('[data-act="addBook"]').click();pp.locator('#chapterTitle').fill('Synthetic Chapter');pp.locator('[data-act="addChapter"]').click();pp.locator('#cqOriginalPDF').set_input_files(str(txt));pp.locator('[data-act="savePDF"]').click();expect(pp.locator('#sourceText')).to_have_value(source)
  pp.locator('[data-pdf-parent="from-local"]').click();expect(pp.locator('#cqPdfParentStatus')).to_contain_text('検' if False else '検証' if False else '검증 완료',timeout=90000);expect(pp.locator('#cqPublishVerifiedPdf')).not_to_have_value('');passed('TXT converts to PDF and uploads through real signed Storage URL and Edge verification')
  pp.locator('#cqDraftImport').set_input_files(str(draft));expect(pp.locator('[data-act="approve"]')).to_be_visible();pp.locator('[data-act="approve"]').click();pp.locator('[data-publish-child]').check();pp.locator('[data-parent-publish]').click();expect(pp.locator('#cqPublicationStatus')).to_contain_text('성공');passed('approved lesson binds to the real verified PDF and assigns through RPC')
  sp.locator('[data-child="list"]').click();expect(sp.locator('[data-child="view"]')).to_have_count(1);sp.locator('[data-child="view"]').click();expect(sp.locator('[data-server-pdf="count"]')).to_have_text('1 / 1 페이지',timeout=90000);expect(sp.locator('#cqChildWork [type="submit"]')).to_be_enabled();passed('assigned student downloads and renders PDF through the real signed-link Edge function')
  sp.locator('[data-word-reveal="0"]').click();expect(sp.locator('[data-word-done="0"]')).to_be_checked();sp.locator('[name="readComplete"]').check();sp.locator('[name="cqAnswer0"][value="0"]').check();sp.locator('[name="cqAnswer1"]').fill('They wanted to find the book.');sp.locator('[name="essay"]').fill('Mina helped Leo and they found the book.');sp.locator('[name="speaking"]').fill('I will explain how Mina helped Leo.');sp.locator('[data-child="voice-start"]').click();expect(sp.locator('#cqVoiceStatus')).to_contain_text('녹음 중');sp.wait_for_timeout(900);sp.locator('[data-child="voice-stop"]').click();expect(sp.locator('#cqVoiceStatus')).to_contain_text('원본 저장 완료');sp.locator('#cqChildWork [type="submit"]').click();expect(sp.locator('#cqChildStatus')).to_contain_text('제출 완료',timeout=60000);passed('real MediaRecorder audio uploads to private Storage and final answers submit through RPC')
  pp.locator('[data-parent-feedback="list"]').click();expect(pp.locator('#cqParentFeedback')).to_contain_text('Mina helped Leo and they found the book.');pp.locator('[data-parent-feedback="audio"]').click();expect(pp.locator('[data-audio-player] audio')).to_be_visible();passed('parent receives a real authorized signed recording playback link');pp.locator('[data-parent-feedback-text]').fill('Great explanation!');pp.locator('[data-parent-feedback-release]').check();pp.locator('[data-parent-feedback="save"]').click();expect(pp.locator('#cqParentFeedbackStatus')).to_contain_text('다시 확인');sp.locator('[data-child="view"]').click();expect(sp.locator('#cqChildDetail')).to_contain_text('Great explanation!');passed('parent reads real answers and releases feedback visible in independent student browser')
  op=page();op.locator('#cqChildEmail').fill(users['outsider']['email']);op.locator('#cqChildPassword').fill(users['outsider']['password']);op.locator('[data-child="login"]').click();expect(op.locator('[data-child="list"]')).to_be_visible();op.locator('[data-child="list"]').click();expect(op.locator('#cqChildStatus')).to_contain_text('0개');passed('unassigned real account sees no other student chapter')
  assert not report['page_errors'] and not report['blocked_requests'];passed('no runtime errors or non-local service requests')
  browser.close()
except Exception as error:
 message=str(error)
 for value in sorted(private,key=len,reverse=True):message=message.replace(value,'[local-private-value]')
 report['failure']=message
finally:
 server.shutdown();out.write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
if 'failure' in report:raise SystemExit(1)
