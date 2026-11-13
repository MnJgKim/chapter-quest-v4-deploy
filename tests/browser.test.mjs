import {test,before,after} from 'node:test';import assert from 'node:assert/strict';import {createServer} from 'node:http';import {readFile} from 'node:fs/promises';import {chromium} from 'playwright';
let server,browser,base;
before(async()=>{
 server=createServer(async(req,res)=>{try{const name=req.url.split('?')[0];const file=name==='/'?'index.html':name.slice(1);if(!['index.html','runtime-config.js','account-activation.js'].includes(file)){res.writeHead(404).end();return;}res.setHeader('Content-Type',file.endsWith('.js')?'application/javascript':'text/html');res.end(await readFile(new URL('../public/'+file,import.meta.url)));}catch{res.writeHead(500).end();}});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));base=`http://127.0.0.1:${server.address().port}`;
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
});
after(async()=>{await browser?.close();if(server)await new Promise(resolve=>server.close(resolve));});
async function page(){const page=await browser.newPage();await page.route('**/*',async route=>{if(route.request().url().startsWith(base))await route.continue();else await route.abort();});return page;}
test('parent account issuance and PDF upload use selected local book/chapter IDs',async()=>{
 const p=await page();const calls=[];const errors=[];p.on('pageerror',e=>errors.push(e.message));p.on('dialog',dialog=>dialog.accept(dialog.type()==='prompt'?'123456':undefined));
 await p.route('https://test.supabase.co/**',async route=>{
 const req=route.request(),url=req.url();let result={};const body=req.headers()['content-type']?.includes('application/json')?req.postDataJSON():null;calls.push({url,body});
 if(url.includes('/auth/v1/token'))result={access_token:'test-user-token',refresh_token:'test-refresh',user:{id:'11111111-1111-4111-8111-111111111111'},expires_in:3600};
 if(url.includes('/rest/v1/cq_v4_snapshots'))result=[];
 if(url.includes('/functions/v1/cq-v4-student-account'))result={invited:true};
 if(url.includes('/functions/v1/cq-v4-pdf-parent')){
  if(body.action==='create_chapter')result={chapter_uuid:'33333333-3333-4333-8333-333333333333'};
  if(body.action==='upload_url')result={bucket:'cq-v4-originals',path:'test-path',token:'test-token'};
  if(body.action==='finalize_upload')result={pdf_ready:true};
 }
 await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(result)});
 });
 try{
 await p.goto(base);await p.locator('#parentBtn').click();await p.locator('#cloudUrl').fill('https://test.supabase.co');await p.locator('#cloudKey').fill('public-test-key');await p.locator('[data-cloud="project"]').click();
 await p.locator('#cloudEmail').fill('parent@example.test');await p.locator('#cloudPassword').fill('not-a-real-password');await p.locator('[data-cloud="login"]').click();await p.locator('#cloudStatus').filter({hasText:'로그인 성공'}).waitFor();
 await p.locator('#cqNewStudentEmail').fill('student@example.test');await p.locator('[data-parent-invite="account"]').click();await p.locator('#cqInviteStatus').filter({hasText:'계정 초대 메일을 요청했습니다'}).waitFor();
 await p.locator('#bookTitle').fill('P0 Book');await p.locator('[data-act="addBook"]').click();await p.locator('#chapterTitle').fill('P0 Chapter');await p.locator('[data-act="addChapter"]').click();
 await p.locator('#cqPdfServerFile').setInputFiles({name:'test.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.4\nfixture')});
 await p.locator('[data-pdf-parent="create"]').click();await p.locator('#cqPdfParentStatus').filter({hasText:'PDF 업로드 및 서버 검증 완료'}).waitFor();
 const stored=await p.evaluate(()=>JSON.parse(localStorage.getItem('chapter_quest_v4_state')));const create=calls.find(c=>c.body?.action==='create_chapter');
 assert.equal(create.body.book_id,stored.books[0].id);assert.equal(create.body.chapter_id,stored.books[0].chapters[0].id);assert.equal(create.body.title,'P0 Chapter');
 assert.equal(calls.find(c=>c.url.endsWith('cq-v4-student-account')).body.email,'student@example.test');assert.deepEqual(errors,[]);
 }finally{await p.close();}
});
test('email callback removes URL tokens, verifies identity and sets password without persisting tokens',async()=>{
 const p=await page();const calls=[];await p.route('https://test.supabase.co/auth/v1/user',async route=>{calls.push({method:route.request().method(),body:route.request().postDataJSON()});await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:'33333333-3333-4333-8333-333333333333'})});});
 try{
 await p.goto(base+'/#access_token=disposable-test-token&refresh_token=disposable-test-refresh&type=invite');await p.locator('#cqActivate').waitFor();assert.equal(new URL(p.url()).hash,'');
 await p.locator('#cqActivate [name="url"]').fill('https://test.supabase.co');await p.locator('#cqActivate [name="key"]').fill('public-test');await p.locator('#cqActivate [name="password"]').fill('test-password-12345');await p.locator('#cqActivate button').click();await p.locator('#cqActivate [role="status"]').filter({hasText:'설정 완료'}).waitFor();
 assert.deepEqual(calls.map(c=>c.method),['GET','PUT']);assert.equal(calls[1].body.password,'test-password-12345');assert.equal((await p.evaluate(()=>JSON.stringify(localStorage))).includes('disposable-test'),false);
 }finally{await p.close();}
});
