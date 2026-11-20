import {test,before,after} from 'node:test';import assert from 'node:assert/strict';import {createServer} from 'node:http';import {readFile} from 'node:fs/promises';import {chromium} from 'playwright';
let server,browser,base;
before(async()=>{
 server=createServer(async(req,res)=>{try{const name=req.url.split('?')[0];const file=name==='/'?'index.html':name.slice(1);if(!['index.html','runtime-config.js','account-activation.js','student-session.js'].includes(file)){res.writeHead(404).end();return;}res.setHeader('Content-Type',file.endsWith('.js')?'application/javascript':'text/html');res.end(await readFile(new URL('../public/'+file,import.meta.url)));}catch{res.writeHead(500).end();}});
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
const testDraft={questions:[{kind:'inference',text:'Why did the character leave?',sample:'To help a friend.'}],vocabulary:[{word:'friend',meaning:'친구',example:'A good friend.'}],writingPrompt:'Describe the story.',speakingPrompt:'Summarize the story.'};
async function parentPage(){
 const p=await page();p.on('dialog',dialog=>dialog.accept(dialog.type()==='prompt'?(dialog.message().includes('문제 내용')?'Why did it happen?':'123456'):undefined));await p.goto(base);await p.locator('#parentBtn').click();return p;
}
async function book(p){await p.locator('#bookTitle').fill('TXT Book');await p.locator('[data-act="addBook"]').click();}
async function txtChapter(p){await p.locator('#txtChapterFile').setInputFiles({name:'Chapter 1.txt',mimeType:'text/plain',buffer:Buffer.from('The character helped a friend. '.repeat(20))});await p.locator('[data-act="addTxtChapter"]').click();}
test('TXT registration, approval-only disclosure, reload verification and edit revocation work in browser',async()=>{
 const p=await parentPage();const errors=[];p.on('pageerror',e=>errors.push(e.message));
 try{
 await book(p);await txtChapter(p);await p.locator('[data-act="manualQuestion"]').click();
 await p.locator('#studentBtn').click();assert.equal(await p.locator('[data-act="open"]').count(),0);
 await p.locator('#parentBtn').click();await p.locator('[data-act="manageBook"]').click();await p.locator('[data-act="editChapter"]').click();await p.locator('[data-act="approveManual"]').click();
 await p.locator('#studentBtn').click();await p.locator('[data-act="open"]').first().waitFor();await p.reload();await p.locator('[data-act="open"]').first().waitFor();await p.locator('[data-act="open"]').first().click();await p.getByRole('heading',{name:'원문 TXT 읽기'}).waitFor();assert.match(await p.locator('.source').innerText(),/character helped/);
 await p.locator('#parentBtn').click();await p.locator('[data-act="manageBook"]').click();await p.locator('[data-act="editChapter"]').click();
 await p.locator('#textFile').setInputFiles({name:'changed.txt',mimeType:'text/plain',buffer:Buffer.from('Changed chapter text. '.repeat(20))});await p.locator('#notice').filter({hasText:'텍스트 저장 완료'}).waitFor();await p.locator('#studentBtn').click();assert.equal(await p.locator('[data-act="open"]').count(),0);assert.deepEqual(errors,[]);
 }finally{await p.close();}
});
test('AI client sends parent JWT and keeps model output unpublished until explicit approval',async()=>{
 const p=await parentPage();let authorization;await p.route('https://test.supabase.co/**',route=>route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(route.request().url().includes('/auth/')?{access_token:'parent-ai-test',refresh_token:'refresh-test',expires_in:3600,user:{id:'11111111-1111-4111-8111-111111111111'}}:[])}));
 await p.route(base+'/api/generate',route=>{authorization=route.request().headers().authorization;return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(testDraft)});});
 try{
 await p.locator('#cloudUrl').fill('https://test.supabase.co');await p.locator('#cloudKey').fill('public-test');await p.locator('[data-cloud="project"]').click();await p.locator('#cloudEmail').fill('parent@example.test');await p.locator('#cloudPassword').fill('test-password');await p.locator('[data-cloud="login"]').click();await p.locator('#cloudStatus').filter({hasText:'로그인 성공'}).waitFor();
 await book(p);await txtChapter(p);await p.locator('[data-act="generate"]').click();await p.getByRole('heading',{name:'AI 초안 검토'}).waitFor();assert.equal(authorization,'Bearer parent-ai-test');assert.equal(await p.evaluate(()=>JSON.parse(localStorage.getItem('chapter_quest_v4_state')).books[0].chapters[0].questions.length),0);
 await p.locator('[data-act="approve"]').click();await p.locator('#studentBtn').click();await p.locator('[data-act="open"]').first().waitFor();
 }finally{await p.close();}
});
async function studentPage(){
 const p=await page();const calls=[];const uid='33333333-3333-4333-8333-333333333333',uuid='99999999-9999-4999-8999-999999999999';
 await p.addInitScript(()=>localStorage.setItem('cq_v4_cloud_project',JSON.stringify({url:'https://test.supabase.co',anonKey:'public-test'})));
 await p.route('https://test.supabase.co/**',async route=>{
  const req=route.request(),url=req.url();calls.push({url,authorization:req.headers().authorization});let data=[];
  if(url.includes('/auth/'))data={access_token:url.includes('refresh_token')?'new-student-token':'old-student-token',refresh_token:'student-refresh',expires_in:url.includes('refresh_token')?3600:1,user:{id:uid}};
  else if(url.endsWith('cq_v4_my_chapters'))data=[{chapter_uuid:uuid,chapter_title:'Server TXT',questions:[{kind:'inference',text:'Why?'}]}];
  else if(url.endsWith('cq_v4_my_chapter_activities'))data=[{vocabulary:[],writing_prompt:'Write',speaking_prompt:'Speak'}];
  else if(url.endsWith('cq_v4_my_reading'))data=[{material_type:'txt',reading_text:'Original server text'}];
  await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
 });
 await p.goto(base);await p.locator('[data-stage132="server"]').click();await p.locator('#cqChildEmail').fill('student@example.test');await p.locator('#cqChildPassword').fill('test-password');await p.locator('[data-child="login"]').click();await p.locator('[data-child="list"]').click();await p.locator('[data-child="view"]').click();await p.locator('#cqChildWork').waitFor();return {p,calls,uid,uuid};
}
test('student refresh reaches RPCs; manifest and audio restore verify real IndexedDB, then logout clears session',async()=>{
 const {p,calls,uid,uuid}=await studentPage();const errors=[];p.on('pageerror',e=>errors.push(e.message));
 try{
 assert.equal(calls.filter(c=>c.url.includes('grant_type=refresh_token')).length,1);assert.equal(calls.find(c=>c.url.endsWith('cq_v4_my_chapters')).authorization,'Bearer new-student-token');assert.equal(await p.locator('#cqServerPdfViewer').innerText(),'Original server text');
 const manifest=await p.evaluate(async({uid,uuid})=>CQVoiceManifest.create(new Blob(['restored voice'],{type:'audio/webm'}),uid,uuid),{uid,uuid});
 const chooser=p.waitForEvent('filechooser');await p.locator('#cqVoiceManifestImport').setInputFiles({name:'voice.cqvoice.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(manifest))});await (await chooser).setFiles({name:'voice.webm',mimeType:'audio/webm',buffer:Buffer.from('restored voice')});await p.locator('#cqVoiceStatus').filter({hasText:'복구 파일 저장 완료'}).waitFor();
 const saved=await p.evaluate(async({uid,uuid})=>{const item=await CQAudioVault.createVault().load(uid,uuid);return item?await item.blob.text():null},{uid,uuid});assert.equal(saved,'restored voice');
 await p.locator('[data-child="logout"]').click();await p.locator('#cqChildEmail').waitFor();assert.equal(await p.locator('#cqChildWork').count(),0);assert.equal((await p.evaluate(()=>JSON.stringify(localStorage))).includes('student-token'),false);assert.deepEqual(errors,[]);
 }finally{await p.close();}
});
test('voice manifest for a different student is rejected without overwriting stored audio',async()=>{
 const {p,uid,uuid}=await studentPage();try{
 const manifest=await p.evaluate(async({uuid})=>CQVoiceManifest.create(new Blob(['bad'],{type:'audio/webm'}),'44444444-4444-4444-8444-444444444444',uuid),{uuid});
 await p.locator('#cqVoiceManifestImport').setInputFiles({name:'wrong.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(manifest))});await p.locator('#cqVoiceStatus').filter({hasText:'검증 정보 오류'}).waitFor();assert.equal(await p.evaluate(async({uid,uuid})=>!!await CQAudioVault.createVault().load(uid,uuid),{uid,uuid}),false);
 }finally{await p.close();}
});
test('replacing a PDF invalidates approval and old v1 receipts stay unpublished',async()=>{
 const p=await parentPage();try{
 await book(p);await p.locator('#chapterTitle').fill('PDF chapter');await p.locator('[data-act="addChapter"]').click();
 await p.locator('#cqOriginalPDF').setInputFiles({name:'original.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF- original')});await p.locator('[data-act="savePDF"]').click();await p.locator('#notice').filter({hasText:'원본 PDF 저장 완료'}).waitFor();await p.locator('[data-act="manualQuestion"]').click();await p.locator('[data-act="approveManual"]').click();
 await p.locator('#studentBtn').click();await p.locator('[data-act="open"]').first().waitFor();
 await p.locator('#parentBtn').click();await p.locator('[data-act="manageBook"]').click();await p.locator('[data-act="editChapter"]').click();
 await p.locator('#cqOriginalPDF').setInputFiles({name:'replacement.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF- different')});await p.locator('[data-act="savePDF"]').click();await p.locator('#notice').filter({hasText:'원본 PDF 저장 완료'}).waitFor();await p.locator('#studentBtn').click();assert.equal(await p.locator('[data-act="open"]').count(),0);
 await p.evaluate(()=>{const s=JSON.parse(localStorage.getItem('chapter_quest_v4_state'));s.books[0].chapters[0].approvalReceipt={version:1,scope:'local-only',sha256:'a'.repeat(64),approvedAt:new Date().toISOString()};localStorage.setItem('chapter_quest_v4_state',JSON.stringify(s));});await p.reload();assert.equal(await p.locator('[data-act="open"]').count(),0);
 }finally{await p.close();}
});
test('student session expiry removes chapter DOM and switching to parent never retains student auth',async()=>{
 const {p}=await studentPage();p.on('dialog',dialog=>dialog.accept(dialog.type()==='prompt'?'123456':undefined));try{
 await p.route('https://test.supabase.co/auth/v1/token?grant_type=refresh_token',route=>route.fulfill({status:401,contentType:'application/json',body:'{}'}));
 await p.evaluate(()=>{const original=Date.now;Date.now=()=>original()+7200000;});await p.locator('[data-child="list"]').click();await p.locator('#cqChildEmail').waitFor();assert.equal(await p.locator('#cqChildWork').count(),0);
 await p.locator('#parentBtn').click();await p.locator('#cloudPanel').waitFor();await p.locator('#studentBtn').click();await p.locator('#cqChildEmail').waitFor();assert.equal(await p.locator('[data-child="logout"]').count(),0);
 }finally{await p.close();}
});
