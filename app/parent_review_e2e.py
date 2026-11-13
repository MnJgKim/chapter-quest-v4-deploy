import sys as _qa_sys
from pathlib import Path as _QAPath
_qa_sys.path.insert(0,str(_QAPath(__file__).resolve().parents[0]))
from qa_browser import launch_browser
"""Parent-only editable review using synthetic content, no hosted requests."""
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
import functools,threading,json,sys
from playwright.sync_api import sync_playwright,expect
ROOT=Path(__file__).parent;out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
class Quiet(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(ROOT/'public')));threading.Thread(target=server.serve_forever,daemon=True).start();origin=f'http://127.0.0.1:{server.server_port}'
report={'scope':'synthetic parent review in isolated local browser; no hosted data','checks':[],'page_errors':[],'blocked_requests':[]}
def passed(n):report['checks'].append({'name':n,'pass':True})
evidence=lambda:{'filePages':'1','printedPages':'표시 없음','note':'PARENT_ONLY_EVIDENCE'}
draft={'questions':[{'kind':'mc','text':'Which object is blue?','options':['Boat','Tree'],'correct':0},{'kind':'inference','text':'Why might someone wait?','sample':'They may want more information.'}],'vocabulary':[{'word':'wait','meaning':'기다리다','example':'Please wait here.'}],'writingPrompt':'Write an opinion.','speakingPrompt':'Explain your opinion.','parentReview':{'questions':[evidence(),evidence()],'vocabulary':[evidence()]}}
(out/'source.txt').write_text('Synthetic source for reviewing a small blue boat. '*20);(out/'draft.json').write_text(json.dumps(draft))
try:
 with sync_playwright() as p:
  browser=launch_browser(p,args=['--no-sandbox']);context=browser.new_context(has_touch=True,viewport={'width':800,'height':1280});context.route('**/*',lambda r:r.continue_() if r.request.url.startswith(origin+'/') else (report['blocked_requests'].append(r.request.url),r.abort()));page=context.new_page();page.on('dialog',lambda d:d.accept('123456') if d.type=='prompt' else d.accept());page.on('pageerror',lambda e:report['page_errors'].append(str(e)));page.goto(origin);page.locator('#parentBtn').click();page.locator('#bookTitle').fill('Synthetic review');page.locator('[data-act="addBook"]').click();page.locator('#chapterTitle').fill('Synthetic chapter');page.locator('[data-act="addChapter"]').click();page.locator('#cqOriginalPDF').set_input_files(str(out/'source.txt'));page.locator('[data-act="savePDF"]').click();page.locator('#cqDraftImport').set_input_files(str(out/'draft.json'));expect(page.locator('#cqParentDraftReview')).to_contain_text('PARENT_ONLY_EVIDENCE');assert page.evaluate('chapter().questions.length')==0;passed('private evidence imports without approving or releasing questions')
  page.locator('[data-review-q="0"][data-review-option="1"]').fill('Stone');page.locator('[data-review-q="0"][data-review-field="correct"]').select_option('1');page.locator('[data-review-q="1"][data-review-field="sample"]').fill('Another supported explanation.');page.locator('[data-draftq="1"]').fill('Why could the character wait?');page.locator('[data-evidence-q="1"][data-evidence-field="note"]').fill('Updated private evidence.');page.locator('[data-review-v="0"][data-review-field="meaning"]').fill('잠시 기다리다');page.locator('[data-draftactivity="writingPrompt"]').fill('Write two supported sentences.');page.locator('[data-draftactivity="speakingPrompt"]').fill('Record a short explanation.');passed('parent edits options, key, model answer, question, evidence, vocabulary and activities')
  page.reload();page.locator('#parentBtn').click();page.locator('[data-act="manageBook"]').click();page.locator('[data-act="editChapter"]').click();expect(page.locator('[data-review-q="0"][data-review-option="1"]')).to_have_value('Stone');expect(page.locator('[data-review-q="0"][data-review-field="correct"]')).to_have_value('1');expect(page.locator('[data-review-q="1"][data-review-field="sample"]')).to_have_value('Another supported explanation.');expect(page.locator('[data-evidence-q="1"][data-evidence-field="note"]')).to_have_value('Updated private evidence.');expect(page.locator('[data-draftactivity="speakingPrompt"]')).to_have_value('Record a short explanation.');assert not page.evaluate('!!chapter().approvalReceipt');passed('all review edits survive reload and remain unapproved')
  page.locator('[data-act="approve"]').click();assert not page.evaluate('!!chapter().approvalReceipt');passed('approval requires explicit source confirmation')
  page.locator('#cqEvidenceConfirmed').check();page.locator('[data-evidence-q="0"][data-evidence-field="note"]').fill('');expect(page.locator('#cqEvidenceConfirmed')).not_to_be_checked();page.locator('#cqEvidenceConfirmed').check();page.locator('[data-act="approve"]').click();assert not page.evaluate('!!chapter().approvalReceipt');passed('missing evidence blocks approval and edits reset confirmation')
  page.locator('[data-evidence-q="0"][data-evidence-field="note"]').fill('PARENT_ONLY_EVIDENCE');page.locator('#cqEvidenceConfirmed').check();page.locator('[data-act="approve"]').click();expect(page.locator('[data-act="reviewSaved"]')).to_be_enabled();assert page.evaluate('chapter().questions[0].correct')==1;assert page.evaluate('chapter().parentReview.questions[1].note')=='Updated private evidence.';assert page.evaluate('isApprovalCurrent(chapter())');passed('approval commits the reviewed answer and evidence with a content receipt')
  page.evaluate("chapter().parentReview.questions[0].note='Changed after approval'");assert page.evaluate('isApprovalCurrent(chapter())') is False;passed('changing evidence invalidates content approval digest')
  page.locator('[data-act="reviewSaved"]').click();assert not page.evaluate('!!chapter().approvalReceipt');passed('reopening saved content invalidates approval before editing')
  for width,height in [(360,800),(800,1280),(1280,800)]:
   page.set_viewport_size({'width':width,'height':height});assert page.evaluate('document.documentElement.scrollWidth<=innerWidth');passed(f'review controls fit {width}x{height}')
  before=page.evaluate('draft.questions[0].text');page.evaluate("mode='student';parentUnlocked=false;const el=document.querySelector('[data-draftq=\"0\"]');el.value='Unauthorized edit';el.dispatchEvent(new Event('input',{bubbles:true}))");assert page.evaluate('draft.questions[0].text')==before;passed('review input handler rejects edits after parent mode is lost')
  assert not report['page_errors'] and not report['blocked_requests'];passed('no runtime errors or hosted requests');browser.close()
except Exception as e:report['failure']=str(e)
finally:server.shutdown();(out/'results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
if 'failure' in report:raise SystemExit(1)
