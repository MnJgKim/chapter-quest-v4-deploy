"""Synthetic device-backup and touch checks; no hosted endpoints or paid model."""
import json,sys,threading,functools,hashlib,time,re
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from playwright.sync_api import sync_playwright,expect
from reportlab.pdfgen import canvas
from qa_browser import launch_browser
ROOT=Path(__file__).parent;out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
class Quiet(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(ROOT/'public')));threading.Thread(target=server.serve_forever,daemon=True).start();origin=f'http://127.0.0.1:{server.server_port}'
pdf=out/'original.pdf';c=canvas.Canvas(str(pdf))
for line in range(12):c.drawString(40,740-line*25,'A reader helped a friend find a lost book.')
c.showPage();c.save()
draft={'questions':[{'kind':'inference','text':'Why did the reader help?','sample':'To help a friend.'}],'vocabulary':[{'word':'reader','meaning':'독자','example':'A reader helps.'}],'writingPrompt':'Explain.','speakingPrompt':'Summarize.'};(out/'draft.json').write_text(json.dumps(draft))
report={'scope':'new disposable browser contexts, local assets, fake microphone and synthetic data; no hosted traffic','checks':[],'page_errors':[],'blocked_requests':[]}
def passed(name):report['checks'].append({'name':name,'pass':True})
try:
 with sync_playwright() as pw:
  browser=launch_browser(pw,args=['--no-sandbox','--use-fake-device-for-media-stream','--use-fake-ui-for-media-stream'])
  def page():
   ctx=browser.new_context(has_touch=True,permissions=['microphone'],viewport={'width':800,'height':1280});ctx.route('**/*',lambda r:r.continue_() if r.request.url.startswith(origin+'/') else (report['blocked_requests'].append('external-blocked'),r.abort()));p=ctx.new_page();p.on('pageerror',lambda e:report['page_errors'].append(str(e)));p.on('dialog',lambda d:d.accept('123456') if d.type=='prompt' else d.accept());p.goto(origin);p.locator('[data-stage132="local-demo"]').click();return p
  p=page();p.locator('#parentBtn').click();p.locator('#bookTitle').fill('Backup QA');p.locator('[data-act="addBook"]').click();p.locator('#chapterTitle').fill('Recovery chapter');p.locator('[data-act="addChapter"]').click();p.locator('#cqOriginalPDF').set_input_files(str(pdf));p.locator('[data-act="savePDF"]').click();expect(p.locator('#notice')).to_contain_text('원본 PDF 저장 완료');p.locator('[data-act="extractSource"]').click();expect(p.locator('#sourceText')).to_have_value(re.compile('A reader helped'));p.locator('[data-act="saveSource"]').click();p.locator('#cqDraftImport').set_input_files(str(out/'draft.json'));p.locator('[data-act="approve"]').click();p.locator('#studentBtn').click();p.get_by_role('button',name='Recovery chapter',exact=True).click()
  for width,height in [(360,800),(412,915),(800,1280),(1280,800)]:
   p.set_viewport_size({'width':width,'height':height});p.locator('[data-act="tab"][data-tab="words"]').tap();expect(p.get_by_role('heading',name='핵심 단어 1개')).to_be_visible();p.locator('[data-act="tab"][data-tab="write"]').tap();p.locator('[data-field="writing"]').tap();assert p.locator('[data-field="writing"]').evaluate('(e)=>document.activeElement===e');assert p.evaluate('document.documentElement.scrollWidth<=innerWidth');passed(f'touch vocabulary/writing focus with no overflow at {width}x{height}')
  p.locator('[data-field="writing"]').fill('Original saved essay');p.locator('[data-act="tab"][data-tab="questions"]').click();p.locator('[data-q="0"]').fill('To help a friend.');p.locator('[data-act="tab"][data-tab="speak"]').click();p.locator('[data-field="speaking"]').fill('Original speaking script');p.locator('[data-act="record"]').click();expect(p.locator('#notice')).to_have_text('녹음 중...');time.sleep(.5);p.locator('[data-act="stop"]').click();expect(p.locator('#audioPreview audio')).to_be_visible()
  refs=p.evaluate('({book:selectedBook,chapter:selectedChapter,record:key()})');before=p.evaluate('async r=>{const pdf=await pdfGet(pdfKey(r.book,r.chapter)),voice=await CQAudio.get(r.record);const digest=async b=>Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",await b.arrayBuffer())),v=>v.toString(16).padStart(2,"0")).join("");return {pdf:await digest(pdf),voice:await digest(voice)}}',refs)
  with p.expect_download() as download:p.locator('[data-act="downloadAudio"]').click()
  download.value.save_as(str(out/'voice.webm'));assert hashlib.sha256((out/'voice.webm').read_bytes()).hexdigest()==before['voice'];passed('separate audio backup matches actual IndexedDB recording bytes')
  p.locator('#parentBtn').click()
  with p.expect_download() as download:p.locator('[data-act="backup"]').click()
  backup=out/'records.json';download.value.save_as(str(backup));saved=json.loads(backup.read_text());assert saved['state']['code']=='';passed('JSON backup contains records and omits access code')
  (out/'malformed.json').write_text(json.dumps({'format':'chapter-quest-v4','state':{'books':{}}}));old=p.evaluate('localStorage.getItem("chapter_quest_v4_state")');p.locator('#restoreInput').set_input_files(str(out/'malformed.json'));assert p.evaluate('localStorage.getItem("chapter_quest_v4_state")')==old;passed('malformed JSON restore cannot erase existing books or records')
  p.locator('#studentBtn').click();p.get_by_role('button',name='Recovery chapter',exact=True).click();p.locator('[data-act="tab"][data-tab="write"]').click();p.locator('[data-field="writing"]').fill('Later unsent essay');p.locator('#parentBtn').click();p.locator('#restoreInput').set_input_files(str(backup));expect(p.locator('#notice')).to_contain_text('학습 기록 복원 완료');assert p.evaluate('JSON.parse(localStorage.getItem("chapter_quest_v4_state")).records',)==saved['state']['records'];assert p.evaluate('Object.keys(localStorage).some(k=>k.includes(":before-restore:"))');passed('restore recovers exact saved answers and keeps an independent copy of prior records')
  after=p.evaluate('async r=>{const pdf=await pdfGet(pdfKey(r.book,r.chapter)),voice=await CQAudio.get(r.record);const digest=async b=>Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",await b.arrayBuffer())),v=>v.toString(16).padStart(2,"0")).join("");return {pdf:await digest(pdf),voice:await digest(voice)}}',refs);assert before==after;passed('JSON restore preserves existing PDF and voice bytes without touching IndexedDB')
  p.locator('#studentBtn').click();p.get_by_role('button',name='Recovery chapter',exact=True).click();p.locator('[data-act="tab"][data-tab="write"]').click();expect(p.locator('[data-field="writing"]')).to_have_value('Original saved essay');p.locator('[data-act="tab"][data-tab="speak"]').click();expect(p.locator('#audioPreview audio')).to_be_visible();passed('restored student can read saved essay and play original recording')
  fresh=page();fresh.locator('#parentBtn').click();fresh.locator('#restoreInput').set_input_files(str(backup));fresh.locator('#studentBtn').click();fresh.get_by_role('button',name='Recovery chapter',exact=True).click();assert fresh.locator('#cqPdfViewer').count()==0;assert fresh.evaluate('JSON.parse(localStorage.getItem("chapter_quest_v4_state")).books.length')==1;passed('fresh profile preserves restored records but refuses learning without separately restored PDF')
  assert not report['page_errors'] and not report['blocked_requests'];passed('no JavaScript errors, hosted requests or paid inference');browser.close()
except Exception as error:report['failure']=str(error)
finally:server.shutdown();(out/'results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({'checks':len(report['checks']),'passed':not bool(report.get('failure')),'failure':report.get('failure')},ensure_ascii=False));sys.exit(1 if report.get('failure') else 0)
