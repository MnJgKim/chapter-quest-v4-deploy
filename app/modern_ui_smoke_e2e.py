"""Current V4 entrypoint smoke check; isolated localhost, no hosted traffic."""
import json,sys,threading,functools
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from playwright.sync_api import sync_playwright,expect
from qa_browser import launch_browser
root=Path(__file__).parent
out=Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/cq-v4-modern-smoke');out.mkdir(parents=True,exist_ok=True)
class Quiet(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(root/'public')))
threading.Thread(target=server.serve_forever,daemon=True).start()
origin=f'http://127.0.0.1:{server.server_port}'
report={'scope':'current V4 local entrypoint, isolated synthetic browser; no hosted requests','checks':[],'errors':[],'blocked':[]}
try:
 with sync_playwright() as p:
  browser=launch_browser(p,headless=True,args=['--no-sandbox'])
  context=browser.new_context(viewport={'width':800,'height':1100})
  def route(request):
   if request.request.url.startswith(origin+'/'):request.continue_()
   else:report['blocked'].append(request.request.url);request.abort()
  context.route('**/*',route)
  page=context.new_page();page.on('pageerror',lambda error:report['errors'].append(str(error)))
  page.goto(origin+'/index.html')
  expect(page.locator('#studentBtn')).to_be_visible()
  expect(page.locator('#parentBtn')).to_be_visible()
  expect(page.locator('#student')).to_be_visible()
  expect(page.locator('#app')).not_to_be_empty()
  report['checks'].append('current student entrypoint renders')
  expect(page.locator('#app h2').first).to_contain_text('영어원서 학습')
  report['checks'].append('student library heading renders')
  assert not report['errors'],report['errors']
  browser.close()
finally:
 server.shutdown()
 (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False))
