"""Local parent page selection; generated book only, hosted services blocked."""
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
import functools,threading,json,sys,hashlib
from reportlab.pdfgen import canvas
from playwright.sync_api import sync_playwright,expect
ROOT=Path(__file__).parent;out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
source=out/'original.pdf';pdf=canvas.Canvas(str(source));pdf.setTitle('Synthetic QA Volume')
for n in range(1,5):
 if n in (2,4):pdf.bookmarkPage('chapter'+str(n));pdf.addOutlineEntry('Chapter 1' if n==2 else 'Chapter 2','chapter'+str(n),0)
 pdf.drawString(40,700,'ONLY_PAGE_'+str(n)+' '+('Mina helped Leo find a book. '*12));pdf.showPage()
pdf.save();original_sha=hashlib.sha256(source.read_bytes()).hexdigest();txt=out/'preserve.txt';txt.write_text('Keep the exact original TXT.\n'*15)
report={'scope':'generated four-page PDF; local IndexedDB/UI only; no hosted requests or real Chapter 1 assumptions','checks':[],'page_errors':[],'blocked_requests':[]}
def passed(name):report['checks'].append({'name':name,'pass':True})
class Quiet(SimpleHTTPRequestHandler):
 def log_message(self,*a):pass
server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(ROOT/'public')));threading.Thread(target=server.serve_forever,daemon=True).start();origin=f'http://127.0.0.1:{server.server_port}'
try:
 with sync_playwright() as p:
  browser=p.chromium.launch(args=['--no-sandbox']);context=browser.new_context(has_touch=True,viewport={'width':800,'height':1280});context.route('**/*',lambda r:r.continue_() if r.request.url.startswith(origin+'/') else (report['blocked_requests'].append(r.request.url),r.abort()))
  page=context.new_page();page.on('dialog',lambda d:d.accept('123456') if d.type=='prompt' else d.accept());page.on('pageerror',lambda e:report['page_errors'].append(str(e)));page.goto(origin);page.locator('#parentBtn').click();page.locator('#bookTitle').fill('Range Book');page.locator('[data-act="addBook"]').click();page.locator('#chapterTitle').fill('Preserve TXT');page.locator('[data-act="addChapter"]').click();page.locator('#cqOriginalPDF').set_input_files(str(txt));page.locator('[data-act="savePDF"]').click();expect(page.locator('#sourceText')).to_have_value(txt.read_text())
  page.locator('#chapterTitle').fill('Full PDF');page.locator('[data-act="addChapter"]').click();page.locator('#cqOriginalPDF').set_input_files(str(source));page.locator('[data-act="savePDF"]').click();original_id=page.evaluate('chapter().id')
  expect(page.locator('#cqRangeStart')).to_have_value('');expect(page.locator('#cqRangeEnd')).to_have_value('');expect(page.locator('#cqRangePrepare')).to_be_disabled();passed('actual chapter bounds start unset and cannot create an unconfirmed lesson')
  page.locator('[data-pdf-range="inspect"]').tap();expect(page.locator('#cqPdfStructure')).to_contain_text('파일 4쪽');expect(page.locator('#cqPdfStructure')).to_contain_text('Synthetic QA Volume');expect(page.locator('#cqPdfStructure')).to_contain_text('Chapter 1 · 파일 2쪽');passed('parent inspects exact page count, PDF title and stored chapter outline')
  for width,height in [(360,800),(412,915),(800,1280),(1280,800)]:
   page.set_viewport_size({'width':width,'height':height});assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),f'range selection overflow at {width}';assert page.locator('[data-pdf-range="pick-start"]').bounding_box()['height']>=44;passed(f'page selection controls fit {width}x{height}')
  page.set_viewport_size({'width':800,'height':1280})
  page.locator('[data-act="previewOriginal"]').tap();expect(page.locator('#cqParentPdfViewer [data-pdf="count"]')).to_have_text('1 / 4 페이지');page.locator('#cqParentPdfViewer [data-pdf="page-number"]').fill('2');page.locator('#cqParentPdfViewer [data-pdf="jump"]').tap();expect(page.locator('#cqParentPdfViewer [data-pdf="count"]')).to_have_text('2 / 4 페이지');page.locator('[data-pdf-range="pick-start"]').tap();expect(page.locator('#cqRangeStart')).to_have_value('2');page.locator('#cqParentPdfViewer [data-pdf="next"]').tap();expect(page.locator('#cqParentPdfViewer [data-pdf="count"]')).to_have_text('3 / 4 페이지');page.locator('[data-pdf-range="pick-end"]').tap();expect(page.locator('#cqRangeEnd')).to_have_value('3');passed('parent browses original pages and selects the displayed start/end with touch controls')
  page.locator('[data-pdf-range="preview"]').tap();expect(page.locator('#cqRangePreview [data-pdf="count"]')).to_have_text('1 / 2 페이지');expect(page.locator('#cqRangePrepare')).to_be_disabled();page.locator('#cqRangePreview [data-pdf="next"]').tap();expect(page.locator('#cqRangePreview [data-pdf="count"]')).to_have_text('2 / 2 페이지');page.locator('#cqRangePreview [data-pdf="next"]').tap();expect(page.locator('#cqRangePreview [data-pdf="count"]')).to_have_text('2 / 2 페이지');passed('derived preview contains only the selected two pages and still requires explicit confirmation')
  page.locator('#cqRangeConfirmed').check();expect(page.locator('#cqRangePrepare')).to_be_enabled();page.locator('#cqRangeEnd').fill('4');expect(page.locator('#cqRangePrepare')).to_be_disabled();expect(page.locator('#cqRangeConfirmed')).not_to_be_checked();passed('changing the range invalidates its preview and confirmation')
  page.locator('#cqRangeStart').fill('0');page.locator('[data-pdf-range="preview"]').tap();expect(page.locator('#cqRangeStatus')).to_contain_text('범위 준비 실패');expect(page.locator('#cqRangePrepare')).to_be_disabled();passed('invalid ranges never register learning material')
  page.locator('#cqRangeStart').fill('2');page.locator('#cqRangeEnd').fill('3');page.locator('[data-pdf-range="preview"]').tap();expect(page.locator('#cqRangeConfirmed')).to_be_enabled();page.locator('#cqRangeConfirmed').check();page.locator('#cqRangePrepare').tap();expect(page.locator('#notice')).to_contain_text('선택 범위만 이 기기에 등록');expect(page.locator('#sourceText')).to_have_value(__import__('re').compile('ONLY_PAGE_2'));value=page.locator('#sourceText').input_value();assert 'ONLY_PAGE_3' in value and 'ONLY_PAGE_1' not in value and 'ONLY_PAGE_4' not in value;assert page.evaluate('chapter().questions.length')==0 and not page.evaluate('!!chapter().approvalReceipt');passed('prepared lesson source contains only selected text and has no automatic question approval')
  derived_id=page.evaluate('chapter().id');data=page.evaluate("async()=>{const b=book(),raw=await pdfGet(pdfKey(b.id,b.chapters[1].id)),old=await pdfGet(pdfKey(b.id,b.chapters[0].id));return {hash:Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await raw.arrayBuffer()))).map(x=>x.toString(16).padStart(2,'0')).join(''),txt:await old.text(),range:chapter().pdfRange,count:b.chapters.length}}")
  assert data['hash']==original_sha and data['txt']==txt.read_text() and data['count']==3 and data['range']['start']==2 and data['range']['end']==3,json.dumps(data);passed('whole original bytes, earlier TXT and source lineage are preserved separately')
  page.evaluate("chapter().questions=[{kind:'short',text:'Keep reviewed question',sample:'Keep answer'}];save()")
  page.locator('[data-act="editChapter"][data-c="'+original_id+'"]').click();page.locator('#cqRangeStart').fill('2');page.locator('#cqRangeEnd').fill('3');page.locator('[data-pdf-range="preview"]').tap();expect(page.locator('#cqRangeConfirmed')).to_be_enabled();page.locator('#cqRangeConfirmed').check();page.locator('#cqRangePrepare').tap();expect(page.locator('#notice')).to_contain_text('이미 준비한 같은 범위를 재사용');assert page.evaluate('book().chapters.length')==3;assert page.evaluate('chapter().id')==derived_id;assert page.evaluate('chapter().questions[0].text')=='Keep reviewed question';passed('repeating a confirmed range reuses the lesson and preserves reviewed questions')
  page.locator('[data-act="previewOriginal"]').tap();expect(page.locator('#cqParentPdfViewer [data-pdf="count"]')).to_have_text('1 / 2 페이지')
  for width,height in [(360,800),(412,915),(800,1280),(1280,800)]:
   page.set_viewport_size({'width':width,'height':height});assert page.evaluate('document.documentElement.scrollWidth<=innerWidth');passed(f'parent range lesson editor fits {width}x{height}')
  page.reload();page.locator('#parentBtn').click();page.locator('[data-act="manageBook"]').click();page.locator('[data-act="editChapter"][data-c="'+derived_id+'"]').click();expect(page.locator('#sourceText')).to_have_value(value);assert page.evaluate('chapter().pdfRange.start')==2;passed('range metadata and selected source persist after reload')
  page.locator('#chapterTitle').fill('Navigation Target');page.locator('[data-act="addChapter"]').click();target_id=page.evaluate('chapter().id');page.locator('[data-act="editChapter"][data-c="'+original_id+'"]').click();delayed=out/'delayed.txt';delayed.write_text('This must never replace a different chapter. '*10)
  page.evaluate("window.qaOriginalAB=File.prototype.arrayBuffer;File.prototype.arrayBuffer=function(){if(this.name==='delayed.txt'){const file=this;return new Promise(resolve=>{window.qaRelease=async()=>resolve(await window.qaOriginalAB.call(file))})}return window.qaOriginalAB.call(this)};void 0")
  page.locator('#cqOriginalPDF').set_input_files(str(delayed));page.locator('[data-act="savePDF"]').click();page.wait_for_function("typeof window.qaRelease==='function'");page.locator('[data-act="editChapter"][data-c="'+target_id+'"]').click()
  with page.expect_event('dialog') as refused:page.evaluate('window.qaRelease();void 0')
  assert '챕터가 변경' in refused.value.message;page.evaluate('File.prototype.arrayBuffer=window.qaOriginalAB;void 0');assert not page.evaluate("async()=>!!await pdfGet(pdfKey(book().id,chapter().id))");passed('a file read started on another chapter cannot write into the newly selected chapter')
  assert not report['page_errors'] and not report['blocked_requests'];passed('no runtime errors, network upload, hosted data changes or AI calls')
  browser.close()
except Exception as error:
 import traceback
 report['failure']=str(error);report['traceback']=traceback.format_exc()
finally:
 server.shutdown();(out/'results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
if 'failure' in report:raise SystemExit(1)
