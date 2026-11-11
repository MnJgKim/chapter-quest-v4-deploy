"""Synthetic browser integration: no requests reach hosted Auth, Storage or AI."""
import json,sys,threading,functools,time
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright,expect
from reportlab.pdfgen import canvas
ROOT=Path(__file__).parent
out=Path(sys.argv[1] if len(sys.argv)>1 else '/workspace/qa/server-flow');out.mkdir(parents=True,exist_ok=True)
class Quiet(SimpleHTTPRequestHandler):
 def log_message(self,*a):pass
server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(ROOT/'public')))
threading.Thread(target=server.serve_forever,daemon=True).start()
base=f'http://127.0.0.1:{server.server_port}'
project='https://ftffxetmqditfqdvzjdd.supabase.co'
parent='11111111-1111-4111-8111-111111111111';child='22222222-2222-4222-8222-222222222222';chapter='44444444-4444-4444-8444-444444444444';approval='55555555-5555-4555-8555-555555555555'
source='A young reader helped a friend find a lost book. Together they learned to be patient and kind. '*8
draft={'questions':[{'kind':'mc','text':'What was lost?','options':['A book','A hat'],'correct':0},{'kind':'inference','text':'Why did they work together?','sample':'They wanted to help.'}],'vocabulary':[{'word':'patient','meaning':'참을성 있는','example':'The reader was patient.'}],'writingPrompt':'Explain how they helped.','speakingPrompt':'Summarize the chapter.'}
state={'students':[{'name':'서우','active':True}],'who':'서우','books':[{'id':'qa-book','title':'QA Book','students':['서우'],'chapters':[{'id':'qa-chapter','title':'QA Chapter','source':source,'pdfStored':True,'questions':[],'vocabulary':[],'writingPrompt':'','speakingPrompt':''}]}],'records':{},'weekly':{},'focus':{},'code':''}
backend={'claimed':False,'approved':False,'pdf':False,'published':False,'bound':False,'submission':None,'audio':None,'audio_type':'audio/webm','feedback':'','released':False,'fail_upload':True,'submit_count':0,'refresh_count':0,'deny_pdf':False,'lose_submit_response':True,'pdf_bytes':None,'context_missing':False}
report={'scope':'isolated Chromium with separate parent/student browser contexts, synthetic Supabase/AI HTTP responses and fake microphone; hosted integration NOT verified','checks':[],'page_errors':[],'unexpected_requests':[],'rpc_calls':[]}
def passed(name):report['checks'].append({'name':name,'pass':True})
c=canvas.Canvas(str(out/'fixture.pdf'));c.drawString(50,750,'Synthetic Chapter Quest reading original');c.save();pdf=(out/'fixture.pdf').read_bytes()
def route(r):
 req=r.request;u=urlparse(req.url);path=u.path
 def reply(data,status=200):r.fulfill(status=status,json=data,headers={'Access-Control-Allow-Origin':'*'})
 if req.method=='OPTIONS':
  r.fulfill(status=204,headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*','Access-Control-Allow-Methods':'GET,POST,PUT,OPTIONS'});return
 if req.url.startswith(base):
  if path=='/api/generate':reply(draft)
  else:r.continue_()
  return
 if u.netloc!='ftffxetmqditfqdvzjdd.supabase.co':report['unexpected_requests'].append(req.url);r.abort();return
 body=req.post_data_json if 'application/json' in req.headers.get('content-type','') and req.post_data else {}
 if path=='/auth/v1/token':
  if 'refresh_token' in u.query:
   backend['refresh_count']+=1;reply({'access_token':'child-refreshed','refresh_token':'refresh-child','expires_in':3600,'user':{'id':child}});return
  is_parent=body.get('email')=='parent@example.test';is_other=body.get('email')=='other@example.test'
  reply({'access_token':'parent-token' if is_parent else 'other-token' if is_other else 'child-token','refresh_token':'refresh-parent' if is_parent else 'refresh-child','expires_in':3600 if is_parent else 1,'user':{'id':parent if is_parent else '33333333-3333-4333-8333-333333333333' if is_other else child}});return
 if path.startswith('/rest/v1/cq_v4_snapshots'):reply([]);return
 if path=='/functions/v1/cq-v4-pdf-parent':
  action=body.get('action')
  if action=='list_students':reply({'students':[{'student_user_id':child}] if backend['approved'] else []})
  elif action=='list_chapters':reply({'chapters':[{'chapter_uuid':chapter,'title':'QA Chapter','pdf_ready':backend['pdf']}] if backend['pdf'] else []})
  elif action=='list_assignments':reply({'assignments':[]})
  elif action=='create_chapter':reply({'chapter_uuid':chapter})
  elif action=='upload_url':reply({'path':parent+'/'+chapter+'.pdf','token':'synthetic-upload','bucket':'cq-v4-originals'})
  elif action=='finalize_upload':backend['pdf']=True;reply({'pdf_ready':True})
  else:reply({'error':'unexpected PDF action'},400)
  return
 if path=='/functions/v1/cq-v4-pdf-link':
  if backend['deny_pdf']:reply({'error':'denied'},403)
  else:reply({'signed_url':project+'/storage/v1/object/sign/cq-v4-originals/'+parent+'/'+chapter+'.pdf?token=synthetic','expires_at':__import__('datetime').datetime.fromtimestamp(time.time()+120,__import__('datetime').timezone.utc).isoformat()})
  return
 if path.startswith('/storage/v1/object/upload/sign/cq-v4-originals/'):
  assert req.headers['content-type']=='application/pdf';backend['pdf_bytes']=req.post_data_buffer;assert backend['pdf_bytes'].startswith(b'%PDF-');reply({'Key':'synthetic'});return
 if path.startswith('/storage/v1/object/sign/cq-v4-originals/'):
  r.fulfill(status=200,body=backend['pdf_bytes'] or pdf,content_type='application/pdf',headers={'Access-Control-Allow-Origin':'*'});return
 if path.startswith('/storage/v1/object/cq-v4-speaking/'):
  if backend['fail_upload']:backend['fail_upload']=False;reply({'message':'synthetic network failure'},503)
  else:backend['audio']=req.post_data_buffer;backend['audio_type']=req.headers.get('content-type','audio/webm');reply({'Key':path})
  return
 if path.startswith('/storage/v1/object/sign/cq-v4-speaking/'):
  if req.method=='POST':
   if backend['audio']:reply({'signedURL':'/storage/v1/object/sign/cq-v4-speaking/synthetic?token=audio'})
   else:reply({'message':'not found'},404)
  else:r.fulfill(status=200,body=backend['audio'] or b'',content_type=backend['audio_type'],headers={'Access-Control-Allow-Origin':'*'})
  return
 if path.startswith('/rest/v1/rpc/'):
  name=path.rsplit('/',1)[1];report['rpc_calls'].append(name)
  if name=='cq_is_admin':reply(req.headers.get('authorization')=='Bearer parent-token')
  elif name=='cq_v4_issue_invite':reply('a'*48)
  elif name=='cq_v4_claim_invite':backend['claimed']=True;reply(True)
  elif name=='cq_v4_list_child_access':reply([{'child_user_id':child,'student_name':'QA Student','active':backend['approved']}] if backend['claimed'] else [])
  elif name=='cq_v4_approve_child':backend['approved']=True;reply(True)
  elif name=='cq_v4_register_approval_once':
   assert 'correct' not in json.dumps(body['p_questions']) and body['p_answer_key']==[0,'They wanted to help.'];reply(approval)
  elif name=='cq_v4_bind_verified_pdf':assert body['p_chapter_uuid']==chapter;backend['bound']=True;reply(chapter)
  elif name=='cq_v4_publish_approved':assert backend['bound'];backend['published']=True;reply(chapter)
  elif name=='cq_v4_my_chapters':reply([{'chapter_uuid':chapter,'chapter_title':'QA Chapter','questions':[{'kind':q['kind'],'text':q['text'],**({'options':q['options']} if q['kind']=='mc' else {})} for q in draft['questions']]}] if backend['published'] else [])
  elif name=='cq_v4_my_chapter_activities':reply([{'vocabulary':draft['vocabulary'],'writing_prompt':draft['writingPrompt'],'speaking_prompt':draft['speakingPrompt']}])
  elif name=='cq_v4_my_submission':reply([{'chapter_uuid':chapter,'submitted_at':backend['submission']['submitted_at'],'feedback':backend['feedback'] if backend['released'] else None,'feedback_released':backend['released']}] if backend['submission'] else [])
  elif name=='cq_v4_submit_answers':
   assert backend['audio'];backend['submit_count']+=1;backend['submission']={'answers':body['p_answers'],'submitted_at':'2026-11-23T00:00:00Z'}
   if backend['lose_submit_response']:backend['lose_submit_response']=False;r.abort()
   else:reply([{'chapter_uuid':chapter,'submitted_at':'2026-11-23T00:00:00Z'}])
  elif name=='cq_v4_parent_lesson':
   if backend['context_missing']:reply({'message':'optional read API unavailable'},404)
   else:reply([{'questions':draft['questions'],'answer_key':[0,'They wanted to help.'],'vocabulary':draft['vocabulary']}])
  elif name=='cq_v4_parent_submissions':reply([{'child_user_id':child,'chapter_uuid':chapter,'student_name':'QA Student','chapter_title':'QA Chapter',**backend['submission'],'feedback':backend['feedback'],'feedback_released':backend['released']}] if backend['submission'] else [])
  elif name=='cq_v4_release_feedback':backend['feedback']=body['p_feedback'];backend['released']=body['p_release'];reply(True)
  else:report['unexpected_requests'].append(req.url);reply({'error':'unexpected rpc'},500)
  return
 report['unexpected_requests'].append(req.url);r.abort()
try:
 with sync_playwright() as p:
  browser=p.chromium.launch(args=['--no-sandbox','--use-fake-device-for-media-stream','--use-fake-ui-for-media-stream'])
  def context():
   ctx=browser.new_context(has_touch=True,permissions=['microphone'],viewport={'width':1280,'height':950});ctx.route('**/*',route)
   page=ctx.new_page();page.on('dialog',lambda d:d.accept('123456') if d.type=='prompt' else d.accept());page.on('pageerror',lambda e:report['page_errors'].append(str(e)))
   return ctx,page
  pc,pp=context();pc.add_init_script('if(!localStorage.getItem("chapter_quest_v4_state"))localStorage.setItem("chapter_quest_v4_state",'+json.dumps(json.dumps(state))+')')
  pp.goto(base);pp.locator('#parentBtn').click();pp.locator('#cloudEmail').fill('parent@example.test');pp.locator('#cloudPassword').fill('synthetic-password');pp.locator('[data-cloud="login"]').click();expect(pp.locator('#cloudStatus')).to_contain_text('로그인 성공');passed('parent login using default project config')
  pp.locator('[data-parent-invite="issue"]').click();expect(pp.locator('#cqInviteCode')).to_have_text('a'*48)
  sc,sp=context();sp.goto(base);sp.locator('[data-stage132="server"]').click();sp.locator('#cqChildEmail').fill('student@example.test');sp.locator('#cqChildPassword').fill('synthetic-password');sp.locator('[data-child="login"]').click();expect(sp.locator('#cqChildInvite')).to_be_visible()
  sp.locator('#cqChildInvite').fill('a'*48);sp.locator('#cqChildInviteName').fill('QA Student');sp.locator('[data-child="claim"]').click();expect(sp.locator('#cqChildStatus')).to_contain_text('연결 요청 완료');passed('student claims parent invitation in independent browser context')
  pp.locator('[data-parent-invite="refresh"]').click();pp.locator('[data-parent-invite="approve"]').click();expect(pp.locator('#cqInviteStatus')).to_contain_text('승인 완료');passed('parent approves child using installed list-child-access RPC')
  pp.locator('[data-act="manageBook"]').click();pp.locator('[data-act="editChapter"]').click()
  (out/'original.txt').write_text(source+'\nOriginal TXT stays in the browser.\n')
  pp.locator('#cqOriginalPDF').set_input_files(str(out/'original.txt'));pp.locator('[data-act="savePDF"]').click()
  pp.locator('[data-pdf-parent="from-local"]').click();expect(pp.locator('#cqPdfParentStatus')).to_contain_text('검증 완료')
  assert backend['pdf_bytes'] and b'/Subtype /Image' in backend['pdf_bytes'];expect(pp.locator('#cqPublishVerifiedPdf')).to_have_value(chapter)
  passed('parent converts local original TXT to PDF, signs upload, verifies and links the selected chapter')
  pp.locator('[data-act="generate"]').click();expect(pp.locator('[data-act="approve"]')).to_be_visible();expect(pp.locator('#app')).to_contain_text('They wanted to help.');passed('parent AI preview includes model answers and vocabulary')
  pp.locator('[data-act="approve"]').click();pp.locator('[data-publish-child]').check();pp.locator('#cqPublishVerifiedPdf').select_option(chapter);pp.locator('[data-parent-publish]').click();expect(pp.locator('#cqPublicationStatus')).to_contain_text('成功' if False else '성공');assert backend['published'];passed('parent approval registers, binds verified PDF, publishes and assigns in order')
  sp.locator('[data-child="list"]').click();sp.locator('[data-child="view"]').click();expect(sp.locator('[data-server-pdf="count"]')).to_have_text('1 / 1 페이지');expect(sp.locator('#cqChildWork [type="submit"]')).to_be_enabled();passed('student assigned chapter opens actual PDF and enables submission after render')
  assert backend['refresh_count']>=1;passed('expired student session refreshes without discarding account or answers')
  expect(sp.locator('[data-word-meaning="0"]')).to_be_hidden();sp.locator('[data-word-reveal="0"]').click();expect(sp.locator('[data-word-meaning="0"]')).to_be_visible();expect(sp.locator('[data-word-done="0"]')).to_be_checked();passed('word review reveals meaning and persists a study check')
  for width,height in [(360,800),(412,915),(800,1280),(1280,800)]:
   sp.set_viewport_size({'width':width,'height':height});assert sp.evaluate('document.documentElement.scrollWidth<=innerWidth');expect(sp.locator('#cqChildWork [type="submit"]')).to_be_in_viewport();passed(f'active learning form fits {width}x{height} mobile/tablet viewport with submit control')
  sp.set_viewport_size({'width':1280,'height':950})
  sp.locator('[name="readComplete"]').check();sp.locator('[name="cqAnswer0"][value="0"]').tap();expect(sp.locator('[name="cqAnswer0"][value="0"]')).to_be_checked();sp.locator('[name="cqAnswer1"]').fill('They wanted to help.');sp.locator('[name="essay"]').fill('The friends learned to help each other.');sp.locator('[name="speaking"]').fill('I will explain the chapter.');
  sp.reload();expect(sp.locator('#cqChildEmail')).to_be_visible();expect(sp.locator('[data-stage132="server"]')).to_have_class('active');sp.locator('#cqChildEmail').fill('student@example.test');sp.locator('#cqChildPassword').fill('synthetic-password');sp.locator('[data-child="login"]').click();expect(sp.locator('[data-child="list"]')).to_be_visible();sp.locator('[data-child="list"]').click();sp.locator('[data-child="view"]').click();expect(sp.locator('[name="essay"]')).to_have_value('The friends learned to help each other.');expect(sp.locator('[name="cqAnswer0"][value="0"]')).to_be_checked();passed('page refresh preserves server mode and restores the signed-in student draft after re-login')
  sp.locator('[data-child="list"]').click();sp.locator('[data-child="view"]').click();expect(sp.locator('[name="essay"]')).to_have_value('The friends learned to help each other.');expect(sp.locator('[data-word-done="0"]')).to_be_checked();passed('chapter navigation restores autosaved answers and vocabulary study')
  sp.locator('[data-child="logout"]').click();sp.locator('#cqChildEmail').fill('other@example.test');sp.locator('#cqChildPassword').fill('synthetic-password');sp.locator('[data-child="login"]').click();expect(sp.locator('[data-child="list"]')).to_be_visible();sp.locator('[data-child="list"]').click();sp.locator('[data-child="view"]').click();expect(sp.locator('[name="essay"]')).to_have_value('');expect(sp.locator('[data-word-done="0"]')).not_to_be_checked();passed('different student in the same browser cannot inherit another student draft')
  sp.locator('[data-child="logout"]').click();sp.locator('#cqChildEmail').fill('student@example.test');sp.locator('#cqChildPassword').fill('synthetic-password');sp.locator('[data-child="login"]').click();expect(sp.locator('[data-child="list"]')).to_be_visible();sp.locator('[data-child="list"]').click();sp.locator('[data-child="view"]').click();expect(sp.locator('[name="essay"]')).to_have_value('The friends learned to help each other.');expect(sp.locator('[data-server-pdf="count"]')).to_have_text('1 / 1 페이지');passed('original student re-login recovers the correct account draft')
  sp.locator('[data-child="voice-start"]').click();expect(sp.locator('#cqVoiceStatus')).to_contain_text('録' if False else '녹음 중');sp.wait_for_timeout(700);sp.locator('[data-child="voice-stop"]').click();expect(sp.locator('#cqVoiceStatus')).to_contain_text('원본 저장 완료');expect(sp.locator('#cqVoicePlayback audio')).to_be_visible();passed('student records, durably saves and previews real MediaRecorder audio')
  sp.locator('#cqChildWork [type="submit"]').click();expect(sp.locator('#cqChildStatus')).to_contain_text('녹음 업로드 실패');assert backend['submit_count']==0;expect(sp.locator('[name="essay"]')).to_have_value('The friends learned to help each other.');passed('failed audio upload blocks server submission and preserves answers')
  sp.locator('#cqChildWork [type="submit"]').click();expect(sp.locator('#cqChildStatus')).to_contain_text('Failed to fetch');assert backend['submit_count']==1;passed('lost submit response preserves local recovery data');sp.locator('#cqChildWork [type="submit"]').click();expect(sp.locator('#cqChildDetail')).to_contain_text('제출 완료');assert backend['submit_count']==1;assert backend['submission']['answers']['hasAudio'];passed('retry uploads audio and submits full answer contract once')
  backend['context_missing']=True;pp.evaluate("state.books[0].chapters[0].questions[0].options[0]='CHANGED LOCAL DRAFT'")
  pp.locator('[data-parent-feedback="list"]').click();expect(pp.locator('.submitted-lesson')).to_contain_text('A book');expect(pp.locator('.submitted-lesson')).not_to_contain_text('CHANGED LOCAL DRAFT');backend['context_missing']=False;passed('missing optional read API uses the frozen published answer context, never an edited local draft')
  pp.locator('[data-parent-feedback-text]').fill('Great work, QA Student!');pp.locator('[data-parent-feedback-release]').check();pp.locator('[data-parent-feedback="save"]').click();expect(pp.locator('#cqParentFeedbackStatus')).to_contain_text('다시 확인');passed('parent sees submitted answers and releases feedback')
  sp.locator('[data-child="view"]').click();expect(sp.locator('#cqChildDetail')).to_contain_text('Great work, QA Student!');assert sp.locator('#cqChildWork').count()==0;passed('student sees released feedback and cannot edit final submission')
  pp.locator('[data-cloud="logout"]').click();assert 'The friends learned to help each other.' not in pp.locator('#cqParentFeedback').inner_text();passed('parent logout clears cached private submission details')
  pp.locator('#cloudEmail').fill('other@example.test');pp.locator('#cloudPassword').fill('synthetic-password');pp.locator('[data-cloud="login"]').click();expect(pp.locator('#cloudStatus')).to_contain_text('부모 관리자로 등록된 계정이 아닙니다');expect(pp.locator('[data-parent-feedback="list"]')).to_be_disabled();passed('student account is rejected at the parent login boundary')
  # A second independent student tab receives a denied signed-link response.
  nc,np=context();np.goto(base);np.locator('[data-stage132="server"]').click();np.locator('#cqChildEmail').fill('student@example.test');np.locator('#cqChildPassword').fill('synthetic-password');np.locator('[data-child="login"]').click();expect(np.locator('[data-child="list"]')).to_be_visible();np.locator('[data-child="list"]').click();backend['submission']=None;backend['deny_pdf']=True;np.locator('[data-child="view"]').click();expect(np.locator('#cqServerPdfViewer')).to_contain_text('불러오지 못했습니다');expect(np.locator('#cqChildWork [type="submit"]')).to_be_disabled();passed('denied PDF access keeps final submission locked')
  assert not report['page_errors'] and not report['unexpected_requests'];passed('no runtime errors or unmocked hosted service requests')
  sp.screenshot(path=str(out/'student-feedback.png'),full_page=True);pp.screenshot(path=str(out/'parent.png'),full_page=True);browser.close()
except Exception as e:
 import traceback
 report['failure']=str(e);report['traceback']=traceback.format_exc()
finally:
 server.shutdown();(out/'results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
if 'failure' in report:sys.exit(1)
