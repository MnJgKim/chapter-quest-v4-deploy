import sys as _qa_sys
from pathlib import Path as _QAPath
_qa_sys.path.insert(0,str(_QAPath(__file__).resolve().parents[0]))
from qa_browser import launch_browser
"""Synthetic existing-session probe; every remote request is intercepted."""
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
import functools,threading,json,sys,base64,time
from playwright.sync_api import sync_playwright,expect
root=Path(__file__).parent;out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
class Quiet(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(root/'public')));threading.Thread(target=server.serve_forever,daemon=True).start();origin=f'http://127.0.0.1:{server.server_port}'
uid='11111111-1111-4111-8111-111111111111';key='sb-ftffxetmqditfqdvzjdd-auth-token';raw=json.dumps({'access_token':'h.'+base64.urlsafe_b64encode(json.dumps({'exp':int(time.time())+3600}).encode()).decode().rstrip('=')+'.s','refresh_token':'NEVER_USE'})
report={'scope':'synthetic existing anonymous session; no hosted requests','checks':[]};calls=[];expired=False;assignment_failure=False;probe_uid=uid;held_logins=[]
def passed(s):report['checks'].append({'name':s,'pass':True})
try:
 with sync_playwright() as p:
  browser=launch_browser(p,args=['--no-sandbox']);ctx=browser.new_context(viewport={'width':800,'height':1280},has_touch=True)
  def route(r):
   if r.request.url.startswith(origin+'/'):return r.continue_()
   calls.append((r.request.method,r.request.url));url=r.request.url
   if '/auth/v1/token?grant_type=password' in url:held_logins.append(r);return
   if '/auth/v1/user' in url:return r.fulfill(status=401 if expired else 200,json={'id':probe_uid,'is_anonymous':True})
   if '/rest/v1/cq_v4_pdf_enrollments?' in url:return r.fulfill(json=[{'student_user_id':probe_uid}])
   if url.endswith('/rpc/cq_v4_my_chapters'):return r.fulfill(status=503 if assignment_failure else 200,json={'message':'synthetic unavailable'} if assignment_failure else [])
   raise AssertionError('Unexpected remote operation')
  ctx.route('**/*',route);page=ctx.new_page();page.goto(origin);page.evaluate('([k,v])=>localStorage.setItem(k,v)',[key,raw]);page.locator('[data-stage132="server"]').click();assert not calls;passed('no automatic token access or hosted request before explicit probe')
  page.locator('[data-child="inspect-existing"]').click();expect(page.locator('[data-child-reference]')).to_have_text(uid[-8:]);assert page.locator('[data-child="claim"]').count()==0 and page.locator('[data-child="signup"]').count()==0;passed('verified existing UID resumes without invitation or replacement account')
  expect(page.locator('[data-session-summary]')).to_contain_text('0개 학습 가능');expect(page.locator('[data-session-summary]')).to_contain_text('미승인인지 미배정인지는');passed('automatic assignment check distinguishes no visible lessons from approval status unknown');page.locator('[data-child="list"]').click();expect(page.locator('#cqChildStatus')).to_contain_text('0');assert page.evaluate('(k)=>localStorage.getItem(k)',key)==raw;assert all(m=='GET' or '/rpc/cq_v4_my_chapters' in u for m,u in calls);passed('assignment read preserves the exact SDK record and never refreshes Auth')
  page.evaluate("document.querySelector('#cqChildDetail').innerHTML='<textarea name=\"essay\">Keep this draft</textarea><div id=\"cqVoicePlayback\">Keep recording controls</div>'")
  page.locator('[data-child="recheck-existing"]').click();expect(page.locator('#cqChildStatus')).to_contain_text('같은 계정의 유효 세션');expect(page.locator('[name="essay"]')).to_have_value('Keep this draft');expect(page.locator('#cqVoicePlayback')).to_have_text('Keep recording controls');passed('same UID recheck preserves working answers and recording UI without redraw')
  probe_uid='22222222-2222-4222-8222-222222222222';page.locator('[data-child="recheck-existing"]').click();expect(page.locator('#cqChildStatus')).to_contain_text('다른 계정의 세션');expect(page.locator('[data-child-reference]')).to_have_text(uid[-8:]);expect(page.locator('[name="essay"]')).to_have_value('Keep this draft');passed('foreign UID recheck refuses switching and preserves current draft');probe_uid=uid
  expired=True;page.locator('[data-child="recheck-existing"]').click();expect(page.locator('#cqChildStatus')).to_contain_text('다시 확인하지 못했습니다');expect(page.locator('[name="essay"]')).to_have_value('Keep this draft');assert page.evaluate('(k)=>localStorage.getItem(k)',key)==raw;passed('failed recheck preserves current account, answers and SDK record');expired=False
  saved_project=page.evaluate("localStorage.getItem('cq_v4_cloud_project')");before_calls=len(calls)
  page.evaluate("localStorage.setItem('cq_v4_cloud_project',JSON.stringify({url:'https://foreignproject.supabase.co',anonKey:'synthetic-other-public'}))")
  page.locator('[data-child="recheck-existing"]').click();expect(page.locator('#cqChildStatus')).to_contain_text('프로젝트 설정이 변경');page.locator('[data-child="list"]').click();expect(page.locator('#cqChildStatus')).to_contain_text('프로젝트 설정이 변경');assert len(calls)==before_calls;expect(page.locator('[name="essay"]')).to_have_value('Keep this draft');passed('changed project blocks recheck and assigned lookup before any token is sent, preserving draft')
  page.evaluate("([v])=>{if(v===null)localStorage.removeItem('cq_v4_cloud_project');else localStorage.setItem('cq_v4_cloud_project',v)}",[saved_project]);page.locator('[data-child="recheck-existing"]').click();expect(page.locator('#cqChildStatus')).to_contain_text('같은 계정의 유효 세션');passed('restoring original project permits same-UID continuation without replacing the account')
  original_config=page.evaluate('CQProject.read()');before_calls=len(calls);page.evaluate("(p)=>localStorage.setItem('cq_v4_cloud_project',JSON.stringify({...p,anonKey:'changed-synthetic-public-key'}))",original_config);page.locator('[data-child="list"]').click();expect(page.locator('#cqChildStatus')).to_contain_text('프로젝트 설정이 변경');assert len(calls)==before_calls;expect(page.locator('[name="essay"]')).to_have_value('Keep this draft');page.evaluate("([v])=>{if(v===null)localStorage.removeItem('cq_v4_cloud_project');else localStorage.setItem('cq_v4_cloud_project',v)}",[saved_project]);passed('changed public key on the same project also blocks requests and preserves draft')
  other=browser.new_context();other.route('**/*',route);login_page=other.new_page();login_page.goto(origin);login_page.locator('[data-stage132="server"]').click();login_page.locator('#cqChildEmail').fill('student@example.test');login_page.locator('#cqChildPassword').fill('synthetic-password');login_page.locator('[data-child="login"]').click();login_page.evaluate("localStorage.setItem('cq_v4_cloud_project',JSON.stringify({url:'https://foreignproject.supabase.co',anonKey:'synthetic-other-public'}))");assert len(held_logins)==1
  held_logins.pop().fulfill(json={'access_token':'synthetic-token-from-original-project','refresh_token':'unused-synthetic','expires_in':3600,'user':{'id':uid}});expect(login_page.locator('#cqChildStatus')).to_contain_text('로그인 중 프로젝트가 변경');assert login_page.locator('[data-child-reference]').count()==0;assert not any('foreignproject' in url for _,url in calls);passed('late login response cannot install original-project credentials in a changed project');other.close()
  for w,h in [(360,800),(800,1280),(1280,800)]:
   page.set_viewport_size({'width':w,'height':h});assert page.evaluate('document.documentElement.scrollWidth<=innerWidth');passed(f'controls fit {w}x{h}')
  assignment_failure=True;page.reload();page.locator('[data-child="inspect-existing"]').click();expect(page.locator('#cqChildStatus')).to_contain_text('배정 조회에 실패');expect(page.locator('[data-session-summary]')).to_contain_text('기존 연결 확인됨');passed('assignment failure retains authenticated identity without falsely claiming zero assignments');assignment_failure=False;page.reload();page.evaluate('(k)=>localStorage.removeItem(k)',key);page.locator('[data-child="inspect-existing"]').click();expect(page.locator('#cqChildStatus')).to_contain_text('계정이 삭제됐다는 뜻은 아닙니다');expect(page.locator('details')).to_contain_text('익명 계정은 이메일 입력이나 새 가입으로 복구되지 않습니다');passed('missing record explains preservation and recovery without claiming account deletion');page.evaluate('([k,v])=>localStorage.setItem(k,v)',[key,raw]);page.reload();expect(page.locator('[data-child="inspect-existing"]')).to_be_visible();expired=True;page.locator('[data-child="inspect-existing"]').click();expect(page.locator('#cqChildStatus')).to_contain_text('자동 갱신하지 않았습니다');assert page.evaluate('(k)=>localStorage.getItem(k)',key)==raw;assert not any('grant_type=refresh_token' in u or '/signup' in u for _,u in calls);assert sum('grant_type=password' in u for _,u in calls)==1;passed('expired record remains intact and blocks renewal or signup');browser.close()
except Exception as e:report['failure']=str(e)
finally:server.shutdown();(out/'results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
if 'failure' in report:raise SystemExit(1)
