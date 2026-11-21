"""Isolated 12-step parent material workflow browser regression; never contacts hosted services."""
import functools,json,sys,threading
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from playwright.sync_api import sync_playwright,expect
from qa_browser import launch_browser

ROOT=Path(__file__).parent
OUT=Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/cq-v4-parent-material')
OUT.mkdir(parents=True,exist_ok=True)
class Quiet(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(ROOT/'public')))
threading.Thread(target=server.serve_forever,daemon=True).start()
origin=f'http://127.0.0.1:{server.server_port}'
report={'checks':[],'errors':[],'blocked_requests':[]}
def check(name,condition):
 assert condition,name
 report['checks'].append(name)
try:
 with sync_playwright() as p:
  browser=launch_browser(p,headless=True,args=['--no-sandbox'])
  ctx=browser.new_context(viewport={'width':800,'height':1100})
  def intercept(route):
   if route.request.url.startswith(origin+'/'):route.continue_()
   else:report['blocked_requests'].append(route.request.url);route.abort()
  ctx.route('**/*',intercept)
  page=ctx.new_page()
  page.on('dialog',lambda dialog:dialog.accept('123456') if dialog.type=='prompt' else dialog.accept())
  page.on('pageerror',lambda error:report['errors'].append(str(error)))
  page.goto(origin+'/index.html')
  page.locator('#parentBtn').click()
  for _ in range(2):
   dialog=page.get_by_role('dialog',name='부모 관리자 PIN')
   if not dialog.is_visible():break
   dialog.get_by_label('숫자 PIN').fill('123456')
   dialog.get_by_role('button',name='확인').click()
  root=page.locator('#cqMaterialWorkflow')
  expect(root).to_have_count(1)
  check('initially collapsed',not root.evaluate('(el)=>el.open'))
  root.locator(':scope > summary').click()
  check('opens on click',root.evaluate('(el)=>el.open'))
  steps=root.locator(':scope > section[data-material-step]')
  expect(steps).to_have_count(12)
  check('ordered steps',steps.evaluate_all('(els)=>els.map(e=>Number(e.dataset.materialStep)).join(",")')==','.join(map(str,range(1,13))))
  def in_step(selector,number):
   return page.locator(selector).evaluate('(el)=>el.closest("[data-material-step]")?.dataset.materialStep')==str(number)
  check('server PDF registration at 1',in_step('#cqPdfParentPanel',1))
  check('book management at 2',in_step('#bookTitle',2))
  check('student/PDF selection at 11',in_step('#cqPublishVerifiedPdf',11))
  page.locator('#bookTitle').fill('Synthetic workflow book')
  page.locator('[data-act="addBook"]').click()
  check('remains expanded after add book',root.evaluate('(el)=>el.open'))
  check('chapter add at 3',in_step('#chapterTitle',3))
  page.locator('#chapterTitle').fill('Synthetic chapter')
  page.locator('[data-act="addChapter"]').click()
  check('AI source at 5',in_step('#sourceText',5))
  check('original PDF/TXT at 6',in_step('#cqOriginalPDF',6))
  check('JSON import at 7',in_step('[data-act="importDraft"]',7))
  check('manual approval at 9',in_step('[data-act="approveManual"]',9))
  check('publication check at 10',in_step('[data-act="checkPublication"]',10))
  check('publication action at 12',in_step('[data-parent-publish="publish"]',12))
  page.locator('#sourceText').fill('Unsubmitted synthetic text')
  root.locator(':scope > summary').click()
  check('collapses on click',not root.evaluate('(el)=>el.open'))
  root.locator(':scope > summary').click()
  check('reopens on click',root.evaluate('(el)=>el.open'))
  check('text retained after toggle',page.locator('#sourceText').input_value()=='Unsubmitted synthetic text')
  check('no browser exceptions',not report['errors'])
  browser.close()
finally:
 server.shutdown()
 (OUT/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False,indent=2))
