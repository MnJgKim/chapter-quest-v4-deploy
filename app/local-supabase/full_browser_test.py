"""Full real local Auth/Storage/Edge browser flow. Never accepts a hosted URL.
The model is not called: a synthetic parent-reviewed JSON draft is used.
"""
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
import json,threading,functools,sys,secrets,urllib.request,urllib.error,subprocess,uuid,time,os,hashlib,textwrap
from playwright.sync_api import sync_playwright,expect
ROOT=Path(__file__).resolve().parents[1];out=Path(sys.argv[2]);out.parent.mkdir(parents=True,exist_ok=True)
original_kind=sys.argv[3] if len(sys.argv)>3 else 'txt'
assert original_kind in ('txt','pdf','range'),'Only local PDF/TXT fixtures are supported'
lesson_pages=2 if original_kind=='range' else 1
expected_server_pdfs=2 if original_kind=='range' else 1
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
base='http://127.0.0.1:54321';report={'scope':'real local Supabase Auth, PostgreSQL, Storage and Edge functions; generated synthetic users/PDF/audio only; no hosted data or AI calls','originalKind':original_kind,'checks':[],'page_errors':[],'blocked_requests':[]};private=[anon]
def passed(name):report['checks'].append({'name':name,'pass':True})
def api(path,data=None,token=None):
 headers={'Content-Type':'application/json','apikey':anon}
 if token:headers['Authorization']='Bearer '+token
 request=urllib.request.Request(base+path,data=json.dumps(data).encode() if data is not None else None,headers=headers)
 with urllib.request.urlopen(request,timeout=90 if path.startswith('/functions/') else 20) as r:return json.load(r)
class Assets(SimpleHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_GET(self):
  if self.path=='/project-config.js':
   payload=('window.CQ_PUBLIC_PROJECT='+json.dumps({'url':base,'anonKey':anon})+';').encode();self.send_response(200);self.send_header('Content-Type','application/javascript');self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload)
  else:super().do_GET()
server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Assets,directory=str(ROOT/'public')));threading.Thread(target=server.serve_forever,daemon=True).start();origin=f'http://127.0.0.1:{server.server_port}'
try:
 # The function-serving process starts asynchronously in CI; preflight is read-only.
 for attempt in range(30):
  try:
   request=urllib.request.Request(base+'/functions/v1/cq-v4-pdf-parent',method='OPTIONS',headers={'apikey':anon,'Origin':origin,'Access-Control-Request-Method':'POST'})
   with urllib.request.urlopen(request,timeout=3) as ready:
    if ready.status in (200,204):break
  except (urllib.error.URLError,TimeoutError):pass
  time.sleep(2)
 else:raise RuntimeError('Local Edge preflight never became ready')
 users={}
 for role in ['parent','student','outsider','otherparent','sibling']:
  email=role+'-'+secrets.token_hex(6)+'@example.test';password=secrets.token_urlsafe(24);private.append(password)
  api('/auth/v1/signup',{'email':email,'password':password});login=api('/auth/v1/token?grant_type=password',{'email':email,'password':password});private.append(login['access_token']);private.append(login['refresh_token']);users[role]={'token':login['access_token'],'email':email,'password':password,'uid':str(uuid.UUID(login['user']['id']))}
 passed('five synthetic accounts sign up and log in on the full local stack')
 # Kong can answer OPTIONS before the replacement Edge runtime is ready. Probe a read-only
 # authenticated action and retry gateway startup errors only; never hide a role/auth failure.
 for attempt in range(60):
  try:api('/functions/v1/cq-v4-pdf-parent',{'action':'list_chapters'},users['outsider']['token']);raise AssertionError('Non-parent Edge request was not denied')
  except urllib.error.HTTPError as error:
   if error.code==403:break
   if error.code not in (502,503,504) or attempt==59:raise AssertionError('Expected local role denial 403, got '+str(error.code)+' '+error.read(400).decode(errors='replace'))
  except (urllib.error.URLError,TimeoutError):
   if attempt==59:raise
  time.sleep(2)
 passed('real Edge parent endpoint denies a non-parent account before privileged writes')
 env=os.environ.copy()
 for k in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']:env.pop(k,None)
 query="insert into public.cq_admins(user_id) values('"+users['parent']['uid']+"'),('"+users['otherparent']['uid']+"');"
 subprocess.run(['docker','--host=unix:///var/run/docker.sock','exec','-i','supabase_db_cq-v4-local-qa','psql','-U','postgres','-v','ON_ERROR_STOP=1'],input=query,env=env,text=True,capture_output=True,check=True)
 source='Mina helped Leo find a lost book. They searched the library together. Leo thanked Mina for being patient and kind. '*8
 fixture={'questions':[{'kind':'mc','text':'Who helped Leo?','options':['Mina','Nobody'],'correct':0},{'kind':'inference','text':'Why did they search together?','sample':'They wanted to find the book.'}],'vocabulary':[{'word':'patient','meaning':'참을성 있는','example':'Mina was patient.'}],'writingPrompt':'Explain how Mina helped.','speakingPrompt':'Summarize the chapter.'}
 original=out.parent/('cq-original.'+('pdf' if original_kind=='range' else original_kind))
 if original_kind=='txt':original.write_text(source)
 else:
  from reportlab.pdfgen import canvas
  document=canvas.Canvas(str(original));document.setTitle('Synthetic QA Volume')
  for page_index in range(1,5 if original_kind=='range' else 2):
   if original_kind=='range' and page_index in (2,4):document.bookmarkPage('part'+str(page_index));document.addOutlineEntry('Synthetic Chapter 1' if page_index==2 else 'Synthetic Chapter 2','part'+str(page_index),0)
   page_source=source if original_kind!='range' or page_index in (2,3) else 'OUTSIDE_SELECTED_CHAPTER original page '+str(page_index)
   for i,line in enumerate(textwrap.wrap(page_source,width=85)):document.drawString(40,790-i*18,line)
   document.showPage()
  document.save()
 original_sha=hashlib.sha256(original.read_bytes()).hexdigest()
 draft=out.parent/'cq-draft.json';draft.write_text(json.dumps(fixture))
 with sync_playwright() as p:
  browser=p.chromium.launch(args=['--no-sandbox','--use-fake-device-for-media-stream','--use-fake-ui-for-media-stream'])
  def page():
   context=browser.new_context(has_touch=True,permissions=['microphone'],viewport={'width':1280,'height':900});context.set_default_timeout(30000)
   def route(r):
    if r.request.url.startswith(origin+'/') or r.request.url.startswith(base+'/'):r.continue_()
    else:report['blocked_requests'].append(r.request.url);r.abort()
   context.route('**/*',route);tab=context.new_page();tab.on('dialog',lambda d:d.accept('123456') if d.type=='prompt' else d.accept());tab.on('pageerror',lambda e:report['page_errors'].append(str(e)));tab.goto(origin);return tab
  pp=page();pp.locator('#parentBtn').click();pp.locator('#cloudEmail').fill(users['parent']['email']);pp.locator('#cloudPassword').fill(users['parent']['password']);pp.locator('[data-cloud="login"]').click();expect(pp.locator('#cloudStatus')).to_contain_text('로그인 성공');passed('parent browser is authorized through real Auth and admin RPC')
  pp.locator('[data-parent-invite="issue"]').click();expect(pp.locator('#cqInviteCode')).to_have_text(__import__('re').compile('^[0-9a-f]{48}$'));invite=pp.locator('#cqInviteCode').inner_text();private.append(invite)
  sp=page();sp.locator('#cqChildEmail').fill(users['student']['email']);sp.locator('#cqChildPassword').fill(users['student']['password']);sp.locator('[data-child="login"]').click();expect(sp.locator('#cqChildInvite')).to_be_visible();sp.locator('#cqChildInvite').fill(invite);sp.locator('#cqChildInviteName').fill('Synthetic Student');sp.locator('[data-child="claim"]').click();expect(sp.locator('#cqChildStatus')).to_contain_text('연결 요청 완료');pp.locator('[data-parent-invite="refresh"]').click();pp.locator('[data-parent-invite="approve"]').click();expect(pp.locator('#cqInviteStatus')).to_contain_text('승인 완료');passed('real invitation claim and parent enrollment approval')
  pp.locator('#bookTitle').fill('Synthetic Local Book');pp.locator('[data-act="addBook"]').click();pp.locator('#chapterTitle').fill('Synthetic Chapter');pp.locator('[data-act="addChapter"]').click();pp.locator('#cqOriginalPDF').set_input_files(str(original));pp.locator('[data-act="savePDF"]').click()
  if original_kind=='txt':expect(pp.locator('#sourceText')).to_have_value(source)
  else:
   pp.locator('[data-act="extractSource"]').click();expect(pp.locator('#sourceText')).to_have_value(__import__('re').compile('Mina helped Leo'));pp.locator('[data-act="saveSource"]').click()
  pp.locator('[data-act="previewOriginal"]').click()
  if original_kind!='txt':expect(pp.locator('#cqParentPdfViewer [data-pdf="count"]')).to_have_text('1 / '+('4' if original_kind=='range' else '1')+' 페이지')
  else:expect(pp.locator('#cqParentPdfViewer [data-original-text]')).to_have_text(source)
  passed('parent verifies the actual local '+original_kind.upper()+' original and source before question approval')
  pp.locator('[data-pdf-parent="from-local"]').click();expect(pp.locator('#cqPdfParentStatus')).to_contain_text('検' if False else '検証' if False else '검증 완료',timeout=90000);expect(pp.locator('#cqPublishVerifiedPdf')).not_to_have_value('');passed(original_kind.upper()+' original uploads through real signed Storage URL and Edge verification')
  local_sha=pp.evaluate("async()=>{const f=await pdfGet(pdfKey(book().id,chapter().id));return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await f.arrayBuffer()))).map(x=>x.toString(16).padStart(2,'0')).join('')}");assert local_sha==original_sha;passed('server registration preserves exact bytes of the original local '+original_kind.upper())
  if original_kind=='range':
   original_uuid=pp.locator('#cqPublishVerifiedPdf').input_value();original_rows=api('/functions/v1/cq-v4-pdf-parent',{'action':'list_chapters'},users['parent']['token']);assert len(original_rows['chapters'])==1
   pp.locator('[data-pdf-parent="use-existing"]').click();expect(pp.locator('#cqPdfParentStatus')).to_contain_text('이 기기에 준비했습니다');expect(pp.locator('#cqRangeStart')).to_have_value('');expect(pp.locator('#cqRangeEnd')).to_have_value('')
   pp.locator('[data-pdf-parent="from-local"]').click();expect(pp.locator('#cqPdfParentStatus')).to_contain_text('재업로드하지 않았습니다');assert api('/functions/v1/cq-v4-pdf-parent',{'action':'list_chapters'},users['parent']['token'])==original_rows;passed('existing server original is reused without duplicate upload or a new server chapter')
   pp.locator('[data-parent-publish]').click();expect(pp.locator('#cqPublicationStatus')).to_contain_text('학습 범위가 미정');assert api('/functions/v1/cq-v4-pdf-parent',{'action':'list_chapters'},users['parent']['token'])==original_rows;passed('unconfirmed original chapter range cannot publish or assign learning material')
   pp.locator('[data-pdf-range="inspect"]').click();expect(pp.locator('#cqPdfStructure')).to_contain_text('파일 4쪽');expect(pp.locator('#cqPdfStructure')).to_contain_text('Synthetic Chapter 1 · 파일 2쪽');pp.locator('[data-act="previewOriginal"]').click();expect(pp.locator('#cqParentPdfViewer [data-pdf="count"]')).to_have_text('1 / 4 페이지');pp.locator('#cqParentPdfViewer [data-pdf="page-number"]').fill('2');pp.locator('#cqParentPdfViewer [data-pdf="jump"]').click();expect(pp.locator('#cqParentPdfViewer [data-pdf="count"]')).to_have_text('2 / 4 페이지');pp.locator('[data-pdf-range="pick-start"]').click();pp.locator('#cqParentPdfViewer [data-pdf="next"]').click();expect(pp.locator('#cqParentPdfViewer [data-pdf="count"]')).to_have_text('3 / 4 페이지');pp.locator('[data-pdf-range="pick-end"]').click();pp.locator('[data-pdf-range="preview"]').click();expect(pp.locator('#cqRangePreview [data-pdf="count"]')).to_have_text('1 / 2 페이지');expect(pp.locator('#cqRangePrepare')).to_be_disabled();pp.locator('#cqRangeConfirmed').check();pp.locator('#cqRangePrepare').click();expect(pp.locator('#notice')).to_contain_text('선택 범위만 이 기기에 등록');expect(pp.locator('#sourceText')).to_have_value(__import__('re').compile('Mina helped Leo'));assert 'OUTSIDE_SELECTED_CHAPTER' not in pp.locator('#sourceText').input_value();assert api('/functions/v1/cq-v4-pdf-parent',{'action':'list_chapters'},users['parent']['token'])==original_rows;passed('parent chooses visible original pages and prepares only confirmed selected text locally')
   pp.locator('[data-pdf-parent="from-local"]').click();expect(pp.locator('#cqPdfParentStatus')).to_contain_text('검증 완료',timeout=90000);assert pp.locator('#cqPublishVerifiedPdf').input_value()!=original_uuid;assert len(api('/functions/v1/cq-v4-pdf-parent',{'action':'list_chapters'},users['parent']['token'])['chapters'])==2
   link=api('/functions/v1/cq-v4-pdf-parent',{'action':'download_url','chapter_uuid':original_uuid},users['parent']['token']);private.append(link['signed_url']);assert link['signed_url'].startswith('/storage/v1/object/sign/cq-v4-originals/')
   with urllib.request.urlopen(urllib.request.Request(base+link['signed_url'],headers={'apikey':anon,'Authorization':'Bearer '+users['parent']['token']}),timeout=30) as r:assert hashlib.sha256(r.read()).hexdigest()==original_sha
   passed('only a derived two-page PDF is registered and the complete server original remains byte-identical')
  pp.locator('#cqDraftImport').set_input_files(str(draft));expect(pp.locator('[data-act="approve"]')).to_be_visible();pp.locator('[data-act="approve"]').click();pp.locator('[data-publish-child]').check();pp.locator('[data-parent-publish]').click();expect(pp.locator('#cqPublicationStatus')).to_contain_text('성공');passed('approved lesson binds to the real verified PDF and assigns through RPC')
  sp.locator('[data-child="list"]').click();expect(sp.locator('[data-child="view"]')).to_have_count(1);chapter_uuid=sp.locator('[data-child="view"]').get_attribute('data-uuid');context=api('/rest/v1/rpc/cq_v4_parent_lesson',{'p_chapter_uuid':chapter_uuid},users['parent']['token']);assert context[0]['answer_key'][0]==0
  if original_kind=='range':
   try:api('/functions/v1/cq-v4-pdf-link',{'chapter_uuid':original_uuid},users['student']['token']);raise AssertionError('Range assignment exposed the complete original PDF')
   except urllib.error.HTTPError as error:assert error.code==403,'The unassigned complete original must remain private'
   passed('a student assigned the selected pages cannot request a download link for the complete original')
  try:api('/rest/v1/rpc/cq_v4_parent_lesson',{'p_chapter_uuid':chapter_uuid},users['student']['token']);raise AssertionError('Student could read parent context')
  except urllib.error.HTTPError as error:assert error.code==403,'Expected local role denial 403, got '+str(error.code)+' '+error.read(400).decode(errors='replace')
  passed('real parent lesson context includes model answers and denies the student')
  sp.locator('[data-child="view"]').click();expect(sp.locator('[data-server-pdf="count"]')).to_have_text('1 / '+str(lesson_pages)+' 페이지',timeout=90000);expect(sp.locator('#cqChildWork [type="submit"]')).to_be_enabled();passed('assigned student downloads and renders PDF through the real signed-link Edge function')
  sp.locator('[data-word-reveal="0"]').tap();expect(sp.locator('[data-word-done="0"]')).to_be_checked();sp.locator('[name="readComplete"]').check();sp.locator('[name="cqAnswer0"][value="0"]').check();sp.locator('[name="cqAnswer1"]').fill('They wanted to find the book.');sp.locator('[name="essay"]').fill('Mina helped Leo and they found the book.');sp.locator('[name="speaking"]').fill('I will explain how Mina helped Leo.')
  for width,height in [(360,800),(412,915),(800,1280),(1280,800)]:
   sp.set_viewport_size({'width':width,'height':height});sp.locator('[name="cqAnswer0"][value="0"]').tap();expect(sp.locator('[name="cqAnswer0"][value="0"]')).to_be_checked();sp.locator('[name="essay"]').fill('Mina helped Leo and they found the book.');assert sp.evaluate('document.documentElement.scrollWidth<=innerWidth');expect(sp.locator('#cqChildWork [type="submit"]')).to_be_in_viewport();assert sp.locator('[data-child="voice-start"]').bounding_box()['height']>=44;passed(f'real learning controls accept touch and text at {width}x{height}')
  def reopen_student():
   sp.reload();expect(sp.locator('#cqChildEmail')).to_be_visible();sp.locator('#cqChildEmail').fill(users['student']['email']);sp.locator('#cqChildPassword').fill(users['student']['password']);sp.locator('[data-child="login"]').click();expect(sp.locator('[data-child="list"]')).to_be_visible();sp.locator('[data-child="list"]').click();sp.locator('[data-child="view"]').click();expect(sp.locator('[data-server-pdf="count"]')).to_have_text('1 / '+str(lesson_pages)+' 페이지',timeout=90000)
  reopen_student();expect(sp.locator('[name="essay"]')).to_have_value('Mina helped Leo and they found the book.');expect(sp.locator('[name="cqAnswer0"][value="0"]')).to_be_checked();expect(sp.locator('[name="cqAnswer1"]')).to_have_value('They wanted to find the book.');expect(sp.locator('[name="speaking"]')).to_have_value('I will explain how Mina helped Leo.');expect(sp.locator('[data-word-done="0"]')).to_be_checked();expect(sp.locator('[name="readComplete"]')).to_be_checked();passed('real Auth re-login after reload restores vocabulary and all answer drafts before recording')
  sp.set_viewport_size({'width':800,'height':1280});sp.locator('[data-child="voice-start"]').tap();expect(sp.locator('#cqVoiceStatus')).to_contain_text('녹음 중');sp.wait_for_timeout(900);sp.locator('[data-child="voice-stop"]').tap();expect(sp.locator('#cqVoiceStatus')).to_contain_text('원본 저장 완료');reopen_student();expect(sp.locator('#cqVoiceStatus')).to_contain_text('녹음 원본을 복원했습니다');expect(sp.locator('#cqVoicePlayback audio')).to_be_visible();passed('recorded audio survives reload and real re-login on the tablet viewport before final upload')
  sp.locator('#cqChildWork [type="submit"]').tap();expect(sp.locator('#cqChildStatus')).to_contain_text('제출 완료',timeout=60000);passed('real MediaRecorder audio uploads to private Storage and final answers submit through RPC')
  pp.locator('[data-parent-feedback="list"]').click();expect(pp.locator('#cqParentFeedback')).to_contain_text('Mina helped Leo and they found the book.');pp.locator('[data-parent-feedback="audio"]').click();expect(pp.locator('[data-audio-player] audio')).to_be_visible();expect(pp.locator('[data-audio-player] audio')).to_have_js_property('readyState',4);passed('parent receives a real authorized signed recording playback link')
  for width,height in [(360,800),(412,915),(800,1280),(1280,800)]:
   pp.set_viewport_size({'width':width,'height':height});assert pp.evaluate('document.documentElement.scrollWidth<=innerWidth');assert pp.locator('[data-parent-feedback="save"]').bounding_box()['height']>=44;passed(f'real parent results and recording controls fit {width}x{height}')
  pp.set_viewport_size({'width':1280,'height':900});pp.locator('[data-parent-feedback-text]').fill('Great explanation!');pp.locator('[data-parent-feedback-release]').check();pp.locator('[data-parent-feedback="save"]').click();expect(pp.locator('#cqParentFeedbackStatus')).to_contain_text('다시 확인');sp.locator('[data-child="feedback"]').click();expect(sp.locator('#cqChildDetail')).to_contain_text('Great explanation!');passed('parent reads real answers and releases feedback visible in independent student browser')
  # Fresh browser has no local book: recover the parent's existing private original read-only.
  before=api('/functions/v1/cq-v4-pdf-parent',{'action':'list_chapters'},users['parent']['token'])
  rp=page();rp.locator('#parentBtn').click();rp.locator('#cloudEmail').fill(users['parent']['email']);rp.locator('#cloudPassword').fill(users['parent']['password']);rp.locator('[data-cloud="login"]').click();expect(rp.locator('#cloudStatus')).to_contain_text('로그인 성공');rp.locator('[data-pdf-parent="refresh"]').click();expect(rp.locator('[data-pdf-parent="use-existing"]')).to_have_count(expected_server_pdfs);selected_title=next(x['title'] for x in before['chapters'] if x['chapter_uuid']==chapter_uuid);rp.locator('#cqPdfParentPanel .book').filter(has=rp.get_by_text(selected_title,exact=True)).locator('[data-pdf-parent="use-existing"]').click();expect(rp.locator('#cqPdfParentStatus')).to_contain_text('이 기기에 준비했습니다',timeout=90000)
  assert rp.evaluate("async()=>{const c=chapter(),f=await pdfGet(pdfKey(book().id,c.id));return c.serverPdfUuid==='"+chapter_uuid+"'&&f.size>5&&(await f.slice(0,5).text())==='%PDF-'}")
  assert api('/functions/v1/cq-v4-pdf-parent',{'action':'list_chapters'},users['parent']['token'])==before
  try:api('/functions/v1/cq-v4-pdf-parent',{'action':'download_url','chapter_uuid':chapter_uuid},users['student']['token']);raise AssertionError('Student read parent PDF endpoint')
  except urllib.error.HTTPError as error:assert error.code==403,'Parent download should deny student, got '+str(error.code)
  passed('fresh parent browser retrieves real private original without creating a chapter and student is denied')
  for action in ['download_url','audio_download_url']:
   try:api('/functions/v1/cq-v4-pdf-parent',{'action':action,'chapter_uuid':chapter_uuid,'student_user_id':users['student']['uid']},users['otherparent']['token']);raise AssertionError('Other registered parent received private link')
   except urllib.error.HTTPError as error:assert error.code==403,'Other parent must be denied, got '+str(error.code)
  assert api('/rest/v1/rpc/cq_v4_parent_lesson',{'p_chapter_uuid':chapter_uuid},users['otherparent']['token'])==[]
  passed('another registered parent cannot obtain this PDF, recording or answer context')

  op=page();op.locator('#cqChildEmail').fill(users['outsider']['email']);op.locator('#cqChildPassword').fill(users['outsider']['password']);op.locator('[data-child="login"]').click();expect(op.locator('[data-child="list"]')).to_be_visible();op.locator('[data-child="list"]').click();expect(op.locator('#cqChildStatus')).to_contain_text('0개');passed('unassigned real account sees no other student chapter')
  pp.locator('[data-cloud="logout"]').click();pp.locator('#cloudEmail').fill(users['parent']['email']);pp.locator('#cloudPassword').fill(users['parent']['password']);pp.locator('[data-cloud="login"]').click();expect(pp.locator('#cloudStatus')).to_contain_text('로그인 성공');pp.locator('[data-pdf-parent="refresh"]').click();expect(pp.locator('[data-pdf-parent="use-existing"]')).to_have_count(expected_server_pdfs)
  # Two genuinely assigned students share the PDF but never submissions, feedback or audio.
  pp.locator('[data-parent-invite="issue"]').click();expect(pp.locator('#cqInviteCode')).not_to_have_text(invite);expect(pp.locator('#cqInviteCode')).to_have_text(__import__('re').compile('^[0-9a-f]{48}$'));second_invite=pp.locator('#cqInviteCode').inner_text();private.append(second_invite)
  sibling=page();sibling.locator('#cqChildEmail').fill(users['sibling']['email']);sibling.locator('#cqChildPassword').fill(users['sibling']['password']);sibling.locator('[data-child="login"]').click();expect(sibling.locator('#cqChildInvite')).to_be_visible();sibling.locator('#cqChildInvite').fill(second_invite);sibling.locator('#cqChildInviteName').fill('Second Synthetic Student');sibling.locator('[data-child="claim"]').click();expect(sibling.locator('#cqChildStatus')).to_contain_text('연결 요청 완료');pp.locator('[data-parent-invite="refresh"]').click();pp.locator('[data-parent-invite="approve"]').click();expect(pp.locator('#cqInviteStatus')).to_contain_text('승인 완료');pp.locator('[data-publish-child="'+users['sibling']['uid']+'"]').check();pp.locator('[data-parent-publish]').click();expect(pp.locator('#cqPublicationStatus')).to_contain_text('성공')
  assert len(api('/rest/v1/rpc/cq_v4_my_chapters',{},users['student']['token']))==1;passed('parent re-login assigns the same approved chapter to a second real student without duplicate binding or removing the first assignment')
  sibling.locator('[data-child="list"]').click();expect(sibling.locator('[data-child="view"]')).to_have_count(1);sibling.locator('[data-child="view"]').click();expect(sibling.locator('[data-server-pdf="count"]')).to_have_text('1 / '+str(lesson_pages)+' 페이지',timeout=90000);expect(sibling.locator('[name="essay"]')).to_have_value('');assert 'Great explanation!' not in sibling.locator('#cqChildDetail').inner_text()
  sibling.locator('[name="readComplete"]').check();sibling.locator('[name="cqAnswer0"][value="1"]').check();sibling.locator('[name="cqAnswer1"]').fill('This student has a different explanation.');sibling.locator('[name="essay"]').fill('A separate essay from the second student.');sibling.locator('[name="speaking"]').fill('My own spoken summary.');sibling.locator('[data-child="voice-start"]').click();expect(sibling.locator('#cqVoiceStatus')).to_contain_text('녹음 중');sibling.wait_for_timeout(900);sibling.locator('[data-child="voice-stop"]').click();expect(sibling.locator('#cqVoiceStatus')).to_contain_text('원본 저장 완료');sibling.locator('#cqChildWork [type="submit"]').click();expect(sibling.locator('#cqChildStatus')).to_contain_text('제출 완료',timeout=60000);passed('second assigned student starts without the first result and submits independent answers and real recorded audio')
  rows=api('/rest/v1/rpc/cq_v4_parent_submissions',{},users['parent']['token']);by_user={row['child_user_id']:row for row in rows};assert len(rows)==2 and by_user[users['student']['uid']]['answers']['essay']=='Mina helped Leo and they found the book.' and by_user[users['sibling']['uid']]['answers']['essay']=='A separate essay from the second student.'
  api('/rest/v1/rpc/cq_v4_release_feedback',{'p_child_user_id':users['sibling']['uid'],'p_chapter_uuid':chapter_uuid,'p_feedback':'Feedback only for the second student.','p_release':True},users['parent']['token']);assert api('/rest/v1/rpc/cq_v4_my_submission',{'p_chapter_uuid':chapter_uuid},users['student']['token'])[0]['feedback']=='Great explanation!';assert api('/rest/v1/rpc/cq_v4_my_submission',{'p_chapter_uuid':chapter_uuid},users['sibling']['token'])[0]['feedback']=='Feedback only for the second student.';passed('parent receives two distinct submissions and released feedback remains scoped to each real student')
  for caller,target in [('student','sibling'),('sibling','student')]:
   try:api('/storage/v1/object/sign/cq-v4-speaking/'+users[target]['uid']+'/'+chapter_uuid+'.webm',{'expiresIn':30},users[caller]['token']);raise AssertionError('Assigned students could read one another recording')
   except urllib.error.HTTPError as error:assert error.code in (400,403,404),'Unexpected cross-student recording response '+str(error.code)
  passed('two students assigned to the same chapter cannot sign each other private recording')
  assert not report['page_errors'] and not report['blocked_requests'];passed('no runtime errors or non-local service requests')
  browser.close()
except Exception as error:
 message=str(error)
 for value in sorted(private,key=len,reverse=True):message=message.replace(value,'[local-private-value]')
 report['failure']=type(error).__name__+': '+message
finally:
 server.shutdown();out.write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
if 'failure' in report:raise SystemExit(1)
