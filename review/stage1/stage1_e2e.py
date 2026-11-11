import json,sys,threading,functools,time
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from playwright.sync_api import sync_playwright,expect
ROOT=Path(__file__).parent
target=Path(sys.argv[1]).resolve()
out=Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True)
class Quiet(SimpleHTTPRequestHandler):
 def log_message(self,*a):pass
server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(target.parent)))
threading.Thread(target=server.serve_forever,daemon=True).start()
url=f'http://127.0.0.1:{server.server_port}/{target.name}'
from reportlab.pdfgen import canvas
c=canvas.Canvas(str(out/'fixture.pdf'));c.drawString(70,740,'Chapter Quest isolated test PDF');c.showPage();c.drawString(70,740,'Page two');c.save()
result={'scope':'isolated localhost Chromium; synthetic records only; only pinned PDF.js CDN allowed; no live Supabase or AI calls','target':str(target),'checks':[],'dialogs':[],'external_requests':[],'page_errors':[]}
def passed(name):result['checks'].append({'name':name,'pass':True})
try:
 with sync_playwright() as p:
  browser=p.chromium.launch(headless=True,args=['--no-sandbox','--use-fake-device-for-media-stream','--use-fake-ui-for-media-stream'])
  context=browser.new_context(permissions=['microphone'],viewport={'width':1280,'height':900})
  def route(r):
   if r.request.url.startswith(f'http://127.0.0.1:{server.server_port}/') or r.request.url in ['https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js','https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js']:r.continue_()
   else:result['external_requests'].append(r.request.url);r.abort()
  context.route('**/*',route)
  page=context.new_page();page.on('pageerror',lambda e:result['page_errors'].append(str(e)))
  prompt_answers=[]
  def dialog(d):
   result['dialogs'].append(d.message)
   if d.type=='prompt':d.accept(prompt_answers.pop(0) if prompt_answers else '123456')
   else:d.accept()
  page.on('dialog',dialog)
  page.goto(url);expect(page.get_by_role('heading',name='서우의 영어원서 학습')).to_be_visible();passed('initial student screen')
  page.get_by_role('button',name='부모 관리자',exact=True).click()
  expect(page.locator('#bookTitle')).to_be_visible()
  page.locator('#bookTitle').fill('ISOLATED QA BOOK');page.locator('[data-act="addBook"]').click()
  page.locator('#chapterTitle').fill('QA Chapter 1');page.locator('[data-act="addChapter"]').click()
  page.locator('#cqOriginalPDF').set_input_files(str(out/'fixture.pdf'));page.locator('[data-act="savePDF"]').click()
  expect(page.get_by_text('원본 PDF 저장 완료 · 학생 읽기 화면에 표시됩니다.')).to_be_visible();passed('original PDF upload and IndexedDB verification')
  prompt_answers.extend(['What did the character learn?','The character learned to help.']);page.locator('[data-act="manualQuestion"]').click()
  expect(page.locator('[data-act="approveManual"]')).to_be_visible();page.locator('[data-act="approveManual"]').click()
  expect(page.get_by_text('로컬 승인 기록 있음 · 수정 시 승인 무효화')).to_be_visible();passed('manual question parent approval')
  original=page.evaluate('JSON.parse(localStorage.getItem("chapter_quest_v4_state"))')
  # Synthetic sentinel belongs only to this brand-new test browser.
  ids=(original['books'][0]['id'],original['books'][0]['chapters'][0]['id'])
  page.get_by_role('button',name='학생 화면',exact=True).click()
  page.get_by_role('button',name='QA Chapter 1',exact=True).click()
  expect(page.locator('[data-pdf="open"]')).to_be_visible();passed('student opens original PDF, not reconstructed text')
  expect(page.locator('[data-pdf="count"]')).to_have_text('1 / 2 페이지');passed('PDF.js renders real two-page PDF')
  page.locator('[data-pdf="next"]').click();expect(page.locator('[data-pdf="count"]')).to_have_text('2 / 2 페이지');passed('PDF page navigation')
  page.locator('[data-pdf="in"]').click();expect(page.locator('[data-pdf="count"]')).to_have_text('2 / 2 페이지');passed('PDF zoom remains on the current page')
  page.locator('[data-act="tab"][data-tab="questions"]').click()
  with page.expect_event('dialog') as blocked:page.locator('[data-act="submit"]').click()
  assert '읽기 완료' in blocked.value.message;passed('incomplete submission blocked')
  page.locator('[data-q="0"]').fill('The character learned to help a friend.')
  page.locator('[data-act="tab"][data-tab="read"]').click();page.locator('[data-field="read"]').check()
  page.locator('[data-act="tab"][data-tab="write"]').click();page.locator('[data-field="writing"]').fill('The character helped a friend and solved the problem.')
  page.locator('[data-act="tab"][data-tab="speak"]').click();page.locator('[data-field="speaking"]').fill('I will explain how the character helped a friend.')
  page.locator('[data-act="record"]').click();expect(page.locator('#notice')).to_have_text('녹음 중...')
  time.sleep(.6);page.locator('[data-act="stop"]').click();expect(page.locator('#audioPreview audio')).to_be_visible();passed('MediaRecorder records and stores audio in IndexedDB')
  page.locator('[data-act="tab"][data-tab="feedback"]').click();page.locator('[data-act="submit"]').click()
  expect(page.locator('[data-act="submit"]')).to_be_disabled();passed('submission succeeds and locks answers')
  page.reload();page.get_by_role('button',name='QA Chapter 1 ✓',exact=True).click()
  page.locator('[data-act="tab"][data-tab="questions"]').click();expect(page.locator('[data-q="0"]')).to_be_disabled()
  expect(page.locator('[data-q="0"]')).to_have_value('The character learned to help a friend.');passed('submission and answers persist after reload')
  page.locator('[data-act="tab"][data-tab="speak"]').click();expect(page.locator('#audioPreview audio')).to_be_visible();passed('audio playback reloads from IndexedDB')
  page.get_by_role('button',name='부모 관리자',exact=True).click();page.locator('summary').filter(has_text='답변 확인').click()
  expect(page.locator('details')).to_contain_text('The character learned to help a friend.');passed('parent views submitted answers')
  page.locator('[data-feedback]').fill('Great explanation of the character!');page.locator('[data-release]').check()
  page.get_by_role('button',name='학생 화면',exact=True).click();page.get_by_role('button',name='QA Chapter 1 ✓',exact=True).click()
  page.locator('[data-act="tab"][data-tab="feedback"]').click();expect(page.get_by_text('Great explanation of the character!',exact=True)).to_be_visible();passed('released parent feedback visible to student')
  page.reload();page.get_by_role('button',name='QA Chapter 1 ✓',exact=True).click();page.locator('[data-act="tab"][data-tab="feedback"]').click()
  expect(page.get_by_text('Great explanation of the character!',exact=True)).to_be_visible();passed('feedback release persists after reload')
  before=page.evaluate('JSON.parse(localStorage.getItem("chapter_quest_v4_state")).records')
  page.locator('#student').select_option('서진');expect(page.get_by_role('heading',name='서진의 영어원서 학습')).to_be_visible()
  assert page.get_by_role('button',name='QA Chapter 1 ✓',exact=True).count()==0
  after=page.evaluate('JSON.parse(localStorage.getItem("chapter_quest_v4_state")).records');assert before==after;passed('student switch preserves records and filters unassigned books')
  page.locator('#student').select_option('서우')
  for width,height in [(360,800),(412,915),(800,1280)]:
   page.set_viewport_size({'width':width,'height':height})
   assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),width
   passed(f'viewport {width}x{height} has no page overflow')
  page.screenshot(path=str(out/'tablet.png'),full_page=True)
  preserved=page.evaluate('JSON.parse(localStorage.getItem("chapter_quest_v4_state")).records')
  page.get_by_role('button',name='부모 관리자',exact=True).click();page.locator('[data-act="manageBook"]').click()
  page.locator('#chapterTitle').fill('QA Chapter 2 TXT');page.locator('[data-act="addChapter"]').click()
  txt='Original TXT lines stay unchanged.\n<img src=x onerror="window.qaInjected=true">\n'+'A character helps a friend and learns a lesson. '*8
  (out/'fixture.txt').write_text(txt)
  page.locator('#cqOriginalPDF').set_input_files(str(out/'fixture.txt'));page.locator('[data-act="savePDF"]').click()
  expect(page.locator('#sourceText')).to_have_value(txt);passed('UTF-8 TXT original registration also prepares AI source')
  ai={'questions':[{'kind':'mc','text':'Who helped a friend?','options':['The character','Nobody'],'correct':0},{'kind':'inference','text':'Why was helping important?','sample':'It solved a problem.'}],'vocabulary':[{'word':'friend','meaning':'친구','example':'A friend helps.'}],'writingPrompt':'Explain the lesson.','speakingPrompt':'Summarize the chapter.'}
  (out/'invalid-draft.json').write_text(json.dumps({**ai,'questions':[{**ai['questions'][0],'correct':99}]}))
  with page.expect_event('dialog') as invalid_draft:page.locator('#cqDraftImport').set_input_files(str(out/'invalid-draft.json'))
  assert '초안 가져오기 실패' in invalid_draft.value.message;passed('invalid imported answer key is rejected')
  (out/'valid-draft.json').write_text(json.dumps(ai))
  with page.expect_file_chooser() as chooser:page.locator('[data-act="importDraft"]').click()
  chooser.value.set_files(str(out/'valid-draft.json'));expect(page.locator('[data-act="approve"]')).to_be_visible()
  expect(page.locator('#app')).to_contain_text('It solved a problem.');passed('no-cost JSON lesson import previews complete answers without API calls')
  assert not page.evaluate('JSON.parse(localStorage.getItem("chapter_quest_v4_state")).books[0].chapters[1].questions.length')
  page.locator('[data-act="cancelDraft"]').click();passed('imported draft requires parent approval and cancellation preserves lesson')
  with page.expect_event('dialog') as blocked_ai:page.locator('[data-act="generate"]').click()
  assert '부모 Supabase 계정으로 로그인' in blocked_ai.value.message;passed('AI UI rejects generation without parent Supabase login')
  page.evaluate("window.CQParentAI={authorization:async()=>({Authorization:'Bearer synthetic-test-token'})}")
  page.route('**/api/generate',lambda r:r.fulfill(status=200,json=ai))
  page.locator('[data-act="generate"]').click();expect(page.locator('[data-act="approve"]')).to_be_visible();page.locator('[data-act="approve"]').click()
  expect(page.get_by_text('로컬 승인 기록 있음 · 수정 시 승인 무효화')).to_be_visible();passed('AI response review and approval UI works with mocked API; live generation NOT verified')
  page.get_by_role('button',name='학생 화면',exact=True).click();page.get_by_role('button',name='QA Chapter 2 TXT',exact=True).click()
  expect(page.locator('[data-original-text]')).to_have_text(txt);assert page.evaluate('window.qaInjected===undefined');passed('TXT reader preserves original text and renders HTML as inert text')
  page.locator('[data-act="tab"][data-tab="words"]').click();expect(page.get_by_text('1. friend',exact=True)).to_be_visible();passed('approved vocabulary visible to student')
  page.locator('[data-act="tab"][data-tab="questions"]').click();page.locator('[data-q="0"][value="0"]').check();page.locator('textarea[data-q="1"]').fill('Helping solved the problem.')
  page.reload();page.get_by_role('button',name='QA Chapter 2 TXT',exact=True).click();page.locator('[data-act="tab"][data-tab="questions"]').click()
  expect(page.locator('[data-q="0"][value="0"]')).to_be_checked();expect(page.locator('textarea[data-q="1"]')).to_have_value('Helping solved the problem.');passed('multiple-choice and inference drafts persist after reload')
  records=page.evaluate('JSON.parse(localStorage.getItem("chapter_quest_v4_state")).records')
  assert all(records.get(k)==v for k,v in preserved.items());passed('adding a chapter preserves previously submitted records')
  # An independent browser context sees none of the local records.
  separate=browser.new_context();separate.route('**/*',route);other=separate.new_page();other.goto(url)
  assert other.get_by_role('button',name='QA Chapter 1 ✓',exact=True).count()==0;passed('local mode correctly remains device-local; not claimed as cloud sync')
  assert not result['page_errors'],result['page_errors'];passed('no application JavaScript runtime errors')
  browser.close()
except Exception as e:
 import traceback
 result['failure']=type(e).__name__+': '+str(e);result['traceback']=traceback.format_exc();result['checks'].append({'name':'remaining flow','pass':False,'error':result['failure']})
finally:
 server.shutdown();(out/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print(json.dumps(result,ensure_ascii=False,indent=2))
sys.exit(1 if result.get('failure') else 0)
