"""Browser calls real local Auth/REST through a loopback-only gateway.
No Edge/Storage/AI service is emulated in this test; existing synthetic feedback only.
"""
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler,BaseHTTPRequestHandler
import json,threading,functools,http.client,time,base64,hashlib,hmac,sys
from playwright.sync_api import sync_playwright,expect
ROOT=Path(__file__).resolve().parent;APP=ROOT.parents[1]/'public'
data=json.loads((ROOT/'runtime/test-accounts.json').read_text());secret=json.loads((ROOT/'runtime/credentials.json').read_text())['jwtSecret']
enc=lambda x:base64.urlsafe_b64encode(x).decode().rstrip('=')
raw=enc(json.dumps({'alg':'HS256','typ':'JWT'}).encode())+'.'+enc(json.dumps({'role':'anon','aud':'authenticated','iss':'local-qa','exp':int(time.time())+3600}).encode());anon=raw+'.'+enc(hmac.new(secret.encode(),raw.encode(),hashlib.sha256).digest())
report={'scope':'Chromium app with real loopback Auth/REST requests; synthetic local identities only; hosted, Edge, Storage API and AI are blocked/not tested','checks':[],'page_errors':[],'blocked_external_requests':[]}
def passed(name):report['checks'].append({'name':name,'pass':True})
class Gateway(BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_OPTIONS(self):self.send_response(204);self.cors();self.end_headers()
 def cors(self):
  self.send_header('Access-Control-Allow-Origin','*');self.send_header('Access-Control-Allow-Headers','authorization,apikey,content-type,x-client-info,prefer,x-upsert');self.send_header('Access-Control-Allow-Methods','GET,POST,PUT,OPTIONS')
 def forward(self):
  if self.path.startswith('/auth/v1/') or self.path.startswith('/rest/v1/'):
   auth=self.path.startswith('/auth/v1/');port=9999 if auth else 3000;prefix='/auth/v1' if auth else '/rest/v1'
   body=self.rfile.read(int(self.headers.get('Content-Length',0)))
   conn=http.client.HTTPConnection('127.0.0.1',port,timeout=15)
   headers={k:v for k,v in self.headers.items() if k.lower() not in ['host','connection','content-length','origin']}
   conn.request(self.command,self.path[len(prefix):],body=body,headers=headers);r=conn.getresponse();content=r.read();self.send_response(r.status);self.cors();self.send_header('Content-Type',r.getheader('Content-Type','application/json'));self.send_header('Content-Length',str(len(content)));self.end_headers();self.wfile.write(content);conn.close()
  else:self.send_response(404);self.cors();self.end_headers()
 do_GET=forward;do_POST=forward;do_PUT=forward
class Assets(SimpleHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_GET(self):
  if self.path=='/project-config.js':
   content=('window.CQ_PUBLIC_PROJECT='+json.dumps({'url':'http://127.0.0.1:54321','anonKey':anon})+';').encode();self.send_response(200);self.send_header('Content-Type','application/javascript');self.send_header('Content-Length',str(len(content)));self.end_headers();self.wfile.write(content)
  else:super().do_GET()
gateway=ThreadingHTTPServer(('127.0.0.1',54321),Gateway);assets=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Assets,directory=str(APP)))
for server in [gateway,assets]:threading.Thread(target=server.serve_forever,daemon=True).start()
base=f'http://127.0.0.1:{assets.server_port}'
try:
 with sync_playwright() as p:
  browser=p.chromium.launch(args=['--no-sandbox'])
  def new_page():
   context=browser.new_context(viewport={'width':1280,'height':900})
   def route(r):
    if r.request.url.startswith(base+'/') or r.request.url.startswith('http://127.0.0.1:54321/') or r.request.url in ['https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js','https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js']:r.continue_()
    else:report['blocked_external_requests'].append(r.request.url);r.abort()
   context.route('**/*',route);page=context.new_page();page.on('pageerror',lambda e:report['page_errors'].append(str(e)));page.on('dialog',lambda d:d.accept('123456') if d.type=='prompt' else d.accept());page.goto(base);return page
  pp=new_page();pp.locator('#parentBtn').click();account=data['accounts']['parent'];pp.locator('#cloudEmail').fill(account['email']);pp.locator('#cloudPassword').fill(account['password']);pp.locator('[data-cloud="login"]').click();expect(pp.locator('#cloudStatus')).to_contain_text('로그인 성공');passed('parent app logs into real local Auth and reads RLS-protected snapshot')
  pp.locator('[data-parent-feedback="list"]').click();expect(pp.locator('#cqParentFeedbackStatus')).to_contain_text('제출 1건');expect(pp.locator('#cqParentFeedback')).to_contain_text('The reader helped.');passed('parent browser reads actual submitted answers through PostgREST')
  sp=new_page();sp.locator('[data-stage132="server"]').click();account=data['accounts']['student'];sp.locator('#cqChildEmail').fill(account['email']);sp.locator('#cqChildPassword').fill(account['password']);sp.locator('[data-child="login"]').click();expect(sp.locator('[data-child="list"]')).to_be_visible();sp.locator('[data-child="list"]').click();expect(sp.locator('[data-child="view"]')).to_have_count(1);sp.locator('[data-child="view"]').click();expect(sp.locator('#cqChildDetail')).to_contain_text('Great work!');passed('independent student browser sees only assigned chapter and real released feedback')
  pp.locator('[data-parent-feedback-text]').fill('Local browser feedback verified.');pp.locator('[data-parent-feedback-release]').check();pp.locator('[data-parent-feedback="save"]').click();expect(pp.locator('#cqParentFeedbackStatus')).to_contain_text('再' if False else '다시 확인');sp.locator('#cqChildDetail [data-child="view"]').click();expect(sp.locator('#cqChildDetail')).to_contain_text('Local browser feedback verified.');passed('parent browser writes feedback and student independently reads persisted result')
  op=new_page();op.locator('[data-stage132="server"]').click();account=data['accounts']['outsider'];op.locator('#cqChildEmail').fill(account['email']);op.locator('#cqChildPassword').fill(account['password']);op.locator('[data-child="login"]').click();expect(op.locator('[data-child="list"]')).to_be_visible();op.locator('[data-child="list"]').click();expect(op.locator('#cqChildStatus')).to_contain_text('0개');assert op.locator('[data-child="view"]').count()==0;passed('third real authenticated browser cannot see another student chapter')
  assert not report['page_errors'] and not report['blocked_external_requests'];passed('no runtime errors or hosted service requests')
  out=Path(sys.argv[1]).parent;sp.screenshot(path=str(out/'local-real-auth-student.png'),full_page=True);browser.close()
except Exception as e:report['failure']=str(e)
finally:
 gateway.shutdown();assets.shutdown();Path(sys.argv[1]).write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
if 'failure' in report:raise SystemExit(1)
