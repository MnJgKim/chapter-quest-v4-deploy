"""Browser-level verification of the shipped student API, with an isolated RPC stub.
This does not claim to exercise the full authenticated student UI or production DB.
"""
from pathlib import Path
from playwright.sync_api import sync_playwright

source=Path("app/public/js/student-api.js").read_text(encoding="utf-8")
uuid="12345678-1234-4234-8234-123456789abc"
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True)
    page=browser.new_page()
    page.goto("about:blank")
    page.evaluate(source)
    result=page.evaluate("""async (uuid) => {
      const calls=[];
      let reply=[{required:true,completed:false}];
      const api=window.CQStudentAPI.createStudentAPI({
        url:'https://isolated-test.supabase.co',
        anonKey:'public-test-key',
        getAccessToken:async()=> 'isolated-token',
        fetchImpl:async(url,options)=>{
          calls.push({url,headers:options.headers,body:JSON.parse(options.body)});
          return {ok:true,json:async()=>reply};
        }
      });
      const before=await api.rereadStatus(uuid);
      reply=true;
      const completed=await api.completeReread(uuid);
      reply=[{required:true,completed:true}];
      const after=await api.rereadStatus(uuid);
      return {before,completed,after,calls};
    }""",uuid)
    assert result["before"]=={"required":True,"completed":False},result
    assert result["completed"] is True,result
    assert result["after"]=={"required":True,"completed":True},result
    assert [c["url"].split("/")[-1] for c in result["calls"]]==[
      "cq_v4_my_reread_status","cq_v4_complete_reread","cq_v4_my_reread_status"],result
    assert all(c["headers"]["Authorization"]=="Bearer isolated-token" for c in result["calls"])
    assert all(c["body"]["p_chapter_uuid"]==uuid for c in result["calls"])
    print("REAL_CHROMIUM_STUDENT_API_REREAD_RPC_SEQUENCE_PASSED")
    browser.close()
