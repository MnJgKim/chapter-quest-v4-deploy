/* Chapter Quest V4 data migration + automatic weekly planner. Pure functions for testing. */
(function(root){'use strict';
function migrateV3(backup,current){
 if(backup?.format!=='chapter-quest-full-backup-v1'||!Array.isArray(backup.books)||!backup.chapters||typeof backup.chapters!=='object')throw Error('V3 전체 백업 형식이 아닙니다.');
 const s=structuredClone(current),existing=new Set(s.books.map(b=>b.id));let importedBooks=0,importedRecords=0;
 for(const b of backup.books){if(!b?.id||!Array.isArray(b.chapters))continue;
 if(!existing.has(b.id)){
 const chapters=b.chapters.map(c=>({id:c.id,title:c.title||'Chapter',source:b.type==='txt'?String(b.text||'').slice(c.start,c.end):'',questions:(c.questions||[]).map(q=>({kind:q.kind||'inference',text:q.text||q.q||'',options:q.options||q.opts||[],correct:q.correct??q.a??0,sample:q.sample||q.answer||''})),vocabulary:(c.aiVocabulary||[]).map(v=>({word:v.word||'',meaning:v.meaning||v.meaningKo||'',example:v.example||''})),writingPrompt:c.aiWritingPrompt||'',speakingPrompt:(c.aiSpeakingPrompts||[]).join('\n'),legacySource:{type:b.type,start:c.start,end:c.end,pdfRequiresReupload:b.type==='pdf'}}));
 s.books.push({id:b.id,title:b.title||'Untitled',students:['서우'],chapters});existing.add(b.id);importedBooks++;
 }
 }
 for(const [k,r] of Object.entries(backup.chapters)){let parts;try{parts=JSON.parse(k)}catch{continue}if(!Array.isArray(parts)||parts.length!==3)continue;const [student,bid,cid]=parts;if(!s.books.some(b=>b.id===bid&&b.chapters.some(c=>c.id===cid)))continue;const nk=[student,bid,cid].join('::');if(s.records[nk])continue;s.records[nk]={answers:r.answers||{},writing:r.writing||'',read:!!r.read,submitted:!!r.submitted,feedback:r.feedback||'',submittedAt:r.at||'',speaking:''};importedRecords++;
 }
 return {state:s,importedBooks,importedRecords,skippedAudio:(backup.audio||[]).length};
}
function planWeek(state,student,monday){
 const books=state.books.filter(b=>b.students.includes(student)),date=String(monday);
 const manual=state.weekly?.[date]?.[student]||{};
 const active=state.focus?.[student]||books[0]?.id;
 const b=books.find(x=>x.id===active);
 if(!b)return {월:manual['월']||null,목:manual['목']||null};
 const done=new Set(Object.keys(state.records).filter(k=>k.startsWith(student+'::'+b.id+'::')&&state.records[k].submitted).map(k=>k.split('::').slice(-1)[0]));
 const remaining=b.chapters.filter(c=>!done.has(c.id));
 const mondayChoice=manual['월']||(remaining[0]?{bookId:b.id,chapterId:remaining[0].id}:null);
 // Do not schedule Monday's chapter again on Thursday, even after Monday submission.
 const thursdayChoice=manual['목']||(remaining.find(c=>c.id!==mondayChoice?.chapterId)?{bookId:b.id,chapterId:remaining.find(c=>c.id!==mondayChoice?.chapterId).id}:null);
 return {월:mondayChoice,목:thursdayChoice};
}
root.CQCore={migrateV3,planWeek};if(typeof module==="object"&&module.exports)module.exports=root.CQCore;
})(typeof module==='object'&&module.exports?module.exports:window);

'use strict';
const KEY='chapter_quest_v4_state',STUDENTS=['서우','서진','시우'];
const $=s=>document.querySelector(s), E=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','"':'&quot;',"'":'&#39;'}[c]));
const uid=()=>crypto.randomUUID?crypto.randomUUID():Date.now()+'-'+Math.random();
const CQAudio={
 db(){return new Promise((resolve,reject)=>{const r=indexedDB.open('chapter-quest-v4-media',1);r.onupgradeneeded=()=>{if(!r.result.objectStoreNames.contains('audio'))r.result.createObjectStore('audio')};r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)})},
 async op(mode,k,blob){const db=await this.db();return new Promise((resolve,reject)=>{const tx=db.transaction('audio',mode),store=tx.objectStore('audio'),req=mode==='readonly'?store.get(k):store.put(blob,k);let result;req.onsuccess=()=>{result=req.result};tx.oncomplete=()=>{db.close();resolve(result)};tx.onerror=()=>{db.close();reject(tx.error)};tx.onabort=()=>{db.close();reject(tx.error||Error('녹음 저장 취소'))}})},
 get(k){return this.op('readonly',k)},put(k,b){return this.op('readwrite',k,b)}
};
let audioObjectUrl=null;
async function loadAudio(){const el=$('#audioPreview');if(!el)return;const expected=key();try{const b=await CQAudio.get(expected);if(!el.isConnected||key()!==expected)return;if(!b){el.textContent='저장된 녹음이 없습니다.';return}if(audioObjectUrl)URL.revokeObjectURL(audioObjectUrl);audioObjectUrl=URL.createObjectURL(b);el.innerHTML='<audio controls src="'+audioObjectUrl+'"></audio><p class="muted">이 기기에 저장된 녹음입니다.</p>'}catch(e){el.textContent='녹음 불러오기 실패: '+e.message}}
let parentUnlocked=false;
const PARENT_PIN_KEY='cq_v4_parent_pin_hash';
async function pinDigest(pin){const bytes=new TextEncoder().encode('CQ-V4-parent-local-v1:'+pin);return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(x=>x.toString(16).padStart(2,'0')).join('')}
async function requestParentAccess(){
 if(parentUnlocked)return true;
 if(!crypto.subtle){alert('관리자 잠금을 지원하지 않는 환경입니다. HTTPS 환경에서 사용하세요.');return false}
 const existing=localStorage.getItem(PARENT_PIN_KEY);
 if(!existing){
   const pin=prompt('부모 관리자용 숫자 PIN 6~12자리를 새로 설정하세요. 이 PIN은 기기 내 화면 잠금용이며 서버 인증을 대체하지 않습니다.');
   if(pin===null)return false;
   if(!/^\d{6,12}$/.test(pin)){alert('숫자 6~12자리로 설정하세요.');return false}
   const repeat=prompt('부모 PIN을 다시 입력하세요.');
   if(repeat!==pin){alert('PIN이 일치하지 않습니다.');return false}
   localStorage.setItem(PARENT_PIN_KEY,await pinDigest(pin));
 }else{
   const pin=prompt('부모 관리자 PIN을 입력하세요.');
   if(pin===null)return false;
   if(await pinDigest(pin)!==existing){alert('PIN이 일치하지 않습니다.');return false}
 }
 parentUnlocked=true;return true;
}
let state,mode='student',view='home',tab='read',selectedBook='',selectedChapter='',draft=null,recording=null,recordChunks=[],audioBlob=null;
// PDF originals are stored separately from AI extraction text in IndexedDB.
const CQPDFDB='cq_v4_pdf_originals_v1';
let activePdfUrl=null, activePdfDocument=null, pdfRenderGeneration=0;
function pdfKey(bookId,chapterId){return JSON.stringify([String(bookId),String(chapterId)])}
function pdfContext(){return pdfKey(selectedBook,selectedChapter)}
function pdfStore(){return new Promise((resolve,reject)=>{const req=indexedDB.open(CQPDFDB,1);req.onupgradeneeded=()=>req.result.createObjectStore('pdf');req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error)})}
async function pdfPut(id,file){const db=await pdfStore();try{await new Promise((resolve,reject)=>{const tx=db.transaction('pdf','readwrite');tx.objectStore('pdf').put(file,id);tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);tx.onabort=()=>reject(tx.error)})}finally{db.close()}}
async function pdfGet(id){const db=await pdfStore();try{return await new Promise((resolve,reject)=>{const tx=db.transaction('pdf','readonly');const req=tx.objectStore('pdf').get(id);req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error)})}finally{db.close()}}
async function originalText(file){
 if(!file?.size||file.size>10*1024*1024)throw Error('TXT 파일은 10MB 이하로 등록하세요.');
 const text=new TextDecoder('utf-8',{fatal:true}).decode(await file.arrayBuffer());
 if(!text.trim()||text.includes('\u0000'))throw Error('내용이 있는 UTF-8 TXT 파일을 선택하세요.');
 return text;
}
async function showChapterPDF(targetId='cqPdfViewer',previewFile=null){
 const target=document.getElementById(targetId);if(!target)return;
 const c=chapter(),expectedContext=pdfContext(),generation=++pdfRenderGeneration;
 const current=()=>target.isConnected&&pdfContext()===expectedContext&&pdfRenderGeneration===generation;
 if(!c?.pdfStored){target.textContent='원본 PDF를 아직 등록하지 않았습니다. 부모 관리자에서 PDF를 등록해 주세요.';return}
 try{
  if(activePdfDocument){const previous=activePdfDocument;activePdfDocument=null;await previous.destroy();}
  const file=previewFile||await pdfGet(expectedContext);if(!current())return;
  if(!file){target.textContent='이 기기에서 PDF 파일을 찾지 못했습니다. 부모 관리자에서 다시 등록해 주세요.';return}
  if(c.readerType==='txt'&&!previewFile){
   const text=await originalText(file);if(!current())return;
   target.innerHTML='<pre class="source" data-original-text style="white-space:pre-wrap;overflow-wrap:anywhere"></pre>';
   target.querySelector('[data-original-text]').textContent=text;
   return true;
  }
  const header=new Uint8Array(await file.slice(0,5).arrayBuffer());if(!current())return;
  if(!file.size||file.size>50*1024*1024||String.fromCharCode(...header)!=='%PDF-')throw Error('저장된 PDF가 유효하지 않습니다. 다시 등록해 주세요.');
  if(activePdfUrl)URL.revokeObjectURL(activePdfUrl);
  const url=URL.createObjectURL(file);activePdfUrl=url;
  // The native PDF link remains available even if the optional PDF.js library fails.
  target.innerHTML='<div class="row" style="margin-bottom:10px"><button type="button" data-pdf="prev">이전 페이지</button><span data-pdf="count" aria-live="polite">불러오는 중</span><button type="button" data-pdf="next">다음 페이지</button><label>파일 쪽<input type="number" data-pdf="page-number" min="1" step="1" style="width:90px"></label><button type="button" data-pdf="jump">쪽 이동</button><button type="button" data-pdf="out">축소 −</button><button type="button" data-pdf="in">확대 +</button></div><div data-pdf="stage" style="overflow:auto;text-align:center;background:#e9edf5;padding:8px;border-radius:8px"><canvas data-pdf="canvas" style="max-width:none;background:white;box-shadow:0 1px 8px #0002"></canvas></div><p class="muted">화면이 작으면 PDF를 좌우로 스크롤할 수 있습니다. <a data-pdf="open" target="_blank" rel="noopener">원본 PDF 별도 탭에서 열기</a></p>';
  target.querySelector('[data-pdf="open"]').href=url;
  if(!window.pdfjsLib){target.querySelector('[data-pdf="stage"]').innerHTML='<p>PDF 페이지 렌더러를 불러오지 못했습니다. 위 링크로 원본 PDF를 열어주세요.</p>';return}
  const doc=await window.pdfjsLib.getDocument({isEvalSupported:false,data:await file.arrayBuffer()}).promise;if(!current()){await doc.destroy();return;}activePdfDocument=doc;
  let pageNum=1,zoom=1,drawToken=0,previousRender=null;target.dataset.sourceKey=expectedContext;target.dataset.pageCount=String(doc.numPages);target.dataset.currentPage='';target.querySelector('[data-pdf="page-number"]').max=String(doc.numPages);
  const canvas=target.querySelector('[data-pdf="canvas"]'),ctx=canvas.getContext('2d');
  async function draw(){target.dataset.currentPage='';const token=++drawToken;const n=pageNum,z=zoom;const page=await doc.getPage(n);if(!current()||token!==drawToken)return;
   const base=page.getViewport({scale:1});const stage=target.querySelector('[data-pdf="stage"]');
   const fit=Math.min(1.8,Math.max(.3,(stage.clientWidth-20)/base.width));const viewport=page.getViewport({scale:fit*z});
   // PDF.js does not allow two render tasks to paint the same canvas at once.
   // Cancel and await the old task BEFORE resizing/reusing the canvas.
   if(previousRender){const oldTask=previousRender;previousRender=null;oldTask.cancel();try{await oldTask.promise}catch(e){if(e?.name!=='RenderingCancelledException')throw e}}
   if(!current()||token!==drawToken)return;
   const pixelRatio=Math.min(2,window.devicePixelRatio||1);canvas.width=Math.ceil(viewport.width*pixelRatio);canvas.height=Math.ceil(viewport.height*pixelRatio);
   canvas.style.width=Math.ceil(viewport.width)+'px';canvas.style.height=Math.ceil(viewport.height)+'px';
   const renderTask=page.render({canvasContext:ctx,viewport,transform:[pixelRatio,0,0,pixelRatio,0,0]});previousRender=renderTask;
   try{await renderTask.promise}catch(e){if(e?.name!=='RenderingCancelledException')throw e}
   finally{if(previousRender===renderTask)previousRender=null}
   if(current()&&token===drawToken){target.querySelector('[data-pdf="count"]').textContent=n+' / '+doc.numPages+' 페이지';target.dataset.currentPage=String(n);target.querySelector('[data-pdf="page-number"]').value=String(n);}
  }
  target.addEventListener('click',e=>{const action=e.target.closest('[data-pdf]')?.dataset.pdf;if(!current()||!action)return;
   if(action==='prev')pageNum=Math.max(1,pageNum-1);
   else if(action==='next')pageNum=Math.min(doc.numPages,pageNum+1);
   else if(action==='jump'){const value=Number(target.querySelector('[data-pdf="page-number"]').value);if(!Number.isSafeInteger(value)||value<1||value>doc.numPages){target.querySelector('[data-pdf="count"]').textContent='1~'+doc.numPages+'쪽을 입력하세요.';return;}pageNum=value;}
   else if(action==='in')zoom=Math.min(3,Math.round((zoom+.25)*100)/100);
   else if(action==='out')zoom=Math.max(.5,Math.round((zoom-.25)*100)/100);
   else return;
   draw().catch(err=>{if(current())target.querySelector('[data-pdf="count"]').textContent='PDF 표시 오류: '+err.message});
  });
  await draw();return true;
 }catch(e){if(current())target.textContent='PDF를 여는 중 오류: '+e.message;return false;}
}
let storageRecoveryNotice='',storageWriteBlocked=false,recoveryRaw=null;
function initState(){
 const raw=localStorage.getItem(KEY);let parsed=null,invalid=false;
 try{parsed=raw?JSON.parse(raw):null}catch{invalid=true}
 const result=CQState.normalize(parsed,STUDENTS);state=result.state;
 if(raw&&(invalid||result.repaired)){recoveryRaw=raw;
  try{localStorage.setItem(KEY+':recovery:'+Date.now(),raw);storageRecoveryNotice='기존 저장 자료의 복구 사본을 보존하고 화면 형식을 복구했습니다.';}
  catch{storageWriteBlocked=true;storageRecoveryNotice='저장 형식을 확인해야 합니다. 전체 백업으로 기존 자료를 먼저 보관하세요.';}
 }
}
function save(){
 if(storageWriteBlocked){alert('원본 저장 자료를 덮어쓰지 않았습니다. 전체 백업으로 복구 자료를 보관한 뒤 백업을 복원하세요.');return false;}
 try{localStorage.setItem(KEY,JSON.stringify({...state,code:''}));$('#notice').textContent='✓ 이 브라우저에 저장됨';return true;}
 catch(e){$('#notice').textContent='⚠ 저장 실패: '+e.message;alert('저장 실패: '+e.message);return false;}
}
function book(){return state.books.find(b=>b.id===selectedBook)}
function chapter(){return book()?.chapters.find(c=>c.id===selectedChapter)}
function key(){return [state.who,selectedBook,selectedChapter].join('::')}
function rec(){const k=key();return state.records[k]??(state.records[k]={answers:{},writing:'',read:false,submitted:false,feedback:'',submittedAt:'',speaking:''})}
// Approval is local audit evidence, not server authorization. Legacy chapters remain unapproved.
function approvalPayload(c){return {source:c.source||'',...(c.pdfRange?{pdfRange:c.pdfRange}:{}),...(c.parentReview?{parentReview:c.parentReview}:{}),questions:c.questions||[],vocabulary:c.vocabulary||[],writingPrompt:c.writingPrompt||'',speakingPrompt:c.speakingPrompt||''};}
async function approvalDigest(c){const bytes=new TextEncoder().encode(JSON.stringify(approvalPayload(c)));const hash=await crypto.subtle.digest('SHA-256',bytes);return Array.from(new Uint8Array(hash),b=>b.toString(16).padStart(2,'0')).join('');}
function invalidateApproval(c){if(c&&c.approvalReceipt){delete c.approvalReceipt;}}
async function isApprovalCurrent(c){if(!c?.approvalReceipt||c.approvalReceipt.version!==1||!/^[a-f0-9]{64}$/.test(c.approvalReceipt.sha256))return false;return (await approvalDigest(c))===c.approvalReceipt.sha256;}
// Stage89: preview eligibility is local-only; never a server publish authorization.
async function cqPublicationEligibility(c){
 if(!c)return {ok:false,reason:'챕터를 선택하세요.'};
 if(c.serverOriginalCopy&&!c.pdfRange)return {ok:false,reason:'기존 서버 원본의 학습 범위가 미정입니다. 페이지를 선택·미리보기·확인한 범위 자료에서 승인·배정하세요.'};
 if(!chapterReady(c))return {ok:false,reason:'원문과 유효한 문제를 먼저 준비하세요.'};
 const r=c.approvalReceipt;
 if(!r||r.version!==1||r.scope!=='local-only'||typeof r.approvedAt!=='string'||!Number.isFinite(Date.parse(r.approvedAt))||!/^[a-f0-9]{64}$/.test(String(r.sha256||'')))return {ok:false,reason:'유효한 부모 승인 기록이 없습니다.'};
 if(!await isApprovalCurrent(c))return {ok:false,reason:'승인 이후 자료가 변경되었습니다. 다시 승인하세요.'};
 return {ok:true,reason:'로컬 승인 검증 통과 · 서버 게시 준비만 가능'};
}
function chapterReady(c){return Boolean(c && c.pdfStored && Array.isArray(c.questions) && c.questions.length>0 && c.questions.every(q=>String(q.text||'').trim() && (q.kind!=='mc' || (Array.isArray(q.options) && q.options.length>=2))))}
function weekKey(d=new Date()){const x=new Date(d);x.setHours(12,0,0,0);x.setDate(x.getDate()-(x.getDay()+6)%7);return x.getFullYear()+'-'+String(x.getMonth()+1).padStart(2,'0')+'-'+String(x.getDate()).padStart(2,'0')}
function dateText(){const d=new Date(),day=d.getDay();return `${d.toLocaleDateString('ko-KR',{month:'long',day:'numeric',weekday:'long'})} · ${day===1||day===4?'학습일':'월·목 학습 권장'}`}
function setStatus(s){$('#notice').textContent=s}
function choose(bid,cid){audioBlob=null;selectedBook=bid;selectedChapter=cid;view='learn';tab='read';render()}
function changeStudent(name){if(!state.students.some(s=>s.name===name))return;state.who=name;audioBlob=null;save();view='home';render()}
function render(){pdfRenderGeneration++;if(activePdfDocument){const previous=activePdfDocument;activePdfDocument=null;previous.destroy().catch(()=>{});}if(storageRecoveryNotice){const notice=$('#notice');if(notice)notice.textContent=storageRecoveryNotice;}if(activePdfUrl){URL.revokeObjectURL(activePdfUrl);activePdfUrl=null;}let s=$('#student');s.innerHTML=state.students.map(x=>`<option value="${E(x.name)}" ${state.who===x.name?'selected':''}>${E(x.name)}${x.active?'':' (대기)'}</option>`).join('');$('#dayLabel').textContent=dateText();$('#studentBtn').className=mode==='student'?'active':'';$('#parentBtn').className=mode==='parent'?'active':'';$('#app').innerHTML=mode==='parent'?parentUI():studentUI();if(mode==='student'&&view==='learn'&&tab==='speak')loadAudio();if(mode==='student'&&view==='learn'&&tab==='read')showChapterPDF()}
function studentUI(){if(view==='learn'&&chapter())return learningUI();let active=state.students.find(s=>s.name===state.who)?.active;let books=state.books.filter(b=>b.students.includes(state.who));let assigned=CQCore.planWeek(state,state.who,weekKey());if(!state.weekly[weekKey()]?.[state.who]?.월&&!state.weekly[weekKey()]?.[state.who]?.목&&(assigned.월||assigned.목)){state.weekly[weekKey()]??={};state.weekly[weekKey()][state.who]=assigned;save()}return `<section class="card"><h2>${E(state.who)}의 영어원서 학습</h2><p class="muted">매주 월요일·목요일 · 하루 한 챕터 · 주 2챕터</p><p class="muted">로컬 학습 모드: 같은 브라우저의 저장 데이터에는 부모용 정답이 포함될 수 있습니다. 정답 보안은 서버 계정 모드에서 별도 검증이 필요합니다.</p>${active?'':'<p class="note">현재 학습 대기 상태입니다. 부모 관리자가 시작할 수 있습니다.</p>'}<div class="grid">${['월','목'].map(d=>{let a=assigned[d];let b=state.books.find(x=>x.id===a?.bookId),c=b?.chapters.find(x=>x.id===a?.chapterId);return `<div class="book"><b>${d}요일 학습</b><p>${c?E(b.title)+' · '+E(c.title):'아직 지정된 챕터 없음'}</p>${c?(chapterReady(c)?`<button class="primary" data-act="open" data-b="${E(b.id)}" data-c="${E(c.id)}">학습 시작</button>`:'<span class="chip">학습 자료 준비 중</span>'):''}</div>`}).join('')}</div></section><section class="card"><h2>📖 내 도서관</h2>${books.length?books.map(b=>`<div class="book"><b>${E(b.title)}</b><p class="muted">${b.chapters.length}개 챕터</p>${b.chapters.map(c=>{let r=state.records[[state.who,b.id,c.id].join('::')];return chapterReady(c)?`<button style="margin:4px" data-act="open" data-b="${E(b.id)}" data-c="${E(c.id)}">${E(c.title)} ${r?.submitted?'✓':''}</button>`:`<span class="chip" style="margin:4px">${E(c.title)} · 준비 중</span>`}).join('')||'<p class="muted">부모가 챕터를 등록하면 표시됩니다.</p>'}</div>`).join(''):'<p class="note">부모 관리자가 책과 챕터를 등록하면 이곳에 표시됩니다.</p>'}</section>`}
// Student-facing projection: removes answer keys and model responses from rendered chapter data.
// This is UI data minimization, NOT a security boundary while full state lives in localStorage.
function studentChapter(c){
 if(!c)return null;
 // Strict allowlist: never pass raw question/option/vocabulary objects to student renderers.
 // This minimizes accidental leakage through DOM attributes; localStorage is NOT protected.
 const plain=v=>typeof v==='string'?v:'';
 return {
  id:plain(c.id),title:plain(c.title),
  questions:Array.isArray(c.questions)?c.questions.map(q=>({
   kind:plain(q?.kind),text:plain(q?.text),
   options:Array.isArray(q?.options)?q.options.map(plain):[]
  })):[],
  vocabulary:Array.isArray(c.vocabulary)?c.vocabulary.map(v=>({
   word:plain(v?.word),english:plain(v?.english),meaning:plain(v?.meaning),
   korean:plain(v?.korean),example:plain(v?.example),definition:plain(v?.definition)
  })):[],
  writingPrompt:plain(c.writingPrompt),speakingPrompt:plain(c.speakingPrompt)
 };
}
function learningUI(){const b=book(),c=studentChapter(chapter()),r=rec();return `<section class="card"><button data-act="home">← 내 도서관</button><h2>${E(b.title)} · ${E(c.title)}</h2><p class="muted">${E(state.who)} · ${r.submitted?'제출 완료 (답변 잠금)':'학습 중'} · 입력 즉시 저장</p><div class="tabs">${[['read','📖 원문'],['questions','✏️ 문제'],['words','🧩 단어'],['write','📝 독후감'],['speak','🎤 말하기'],['feedback','⭐ 피드백']].map(([k,v])=>`<button data-act="tab" data-tab="${k}" class="${tab===k?'active':''}">${v}</button>`).join('')}</div></section><section class="card">${tabUI(b,c,r)}</section>`}
function tabUI(b,c,r){if(tab==='read')return `<h2>원본 파일 읽기</h2><p class="muted">PDF는 원본 페이지 그대로, TXT는 업로드한 원문 그대로 표시합니다.</p><div id="cqPdfViewer" aria-live="polite">PDF 불러오는 중...</div><label><input type="checkbox" data-field="read" ${r.submitted?'disabled':''} ${r.read?'checked':''}> 읽기 완료</label>`;
if(tab==='questions')return `<h2>내용 이해 · 추론 문제</h2>${c.questions.length?c.questions.map((q,i)=>`<div class="question"><b>${i+1}. ${E(q.text)}</b>${q.kind==='mc'&&q.options?.length?q.options.map((o,j)=>`<label class="option"><input type="radio" name="q${i}" data-q="${i}" ${r.submitted?'disabled':''} value="${j}" ${String(r.answers[i])===String(j)?'checked':''}>${'ABCD'[j]||j}. ${E(o)}</label>`).join(''):`<textarea data-q="${i}" ${r.submitted?'disabled':''} placeholder="Write your answer in English.">${E(r.answers[i]??'')}</textarea>`}</div>`).join(''):'<p>부모가 문제를 승인하면 표시됩니다.</p>'}<div class="row"><button class="primary" data-act="submit" ${r.submitted?'disabled':''}>${r.submitted?'제출 완료':'학습 제출'}</button><span class="muted">읽기 완료·모든 문제·독후감·말하기 대본을 작성해야 제출할 수 있습니다. 제출 후 수정 불가</span></div>`;
if(tab==='words')return `<h2>핵심 단어 ${c.vocabulary.length}개</h2><div class="grid">${c.vocabulary.map((v,i)=>`<div class="book"><b>${i+1}. ${E(v.word||v.english||'')}</b><p>${E(v.meaning||v.korean||'')}</p><small>${E(v.example||v.definition||'')}</small><p><button data-act="speakword" data-word="${E(v.word||v.english||'')}">🔊 듣기</button></p></div>`).join('')}</div>`;
if(tab==='write')return `<h2>영어 독후감</h2><p>${E(c.writingPrompt||'What happened in this chapter? What did you think?')}</p><textarea style="min-height:220px" data-field="writing" ${r.submitted?'disabled':''} placeholder="Write your reading journal in English.">${E(r.writing)}</textarea><p class="muted">입력 즉시 저장됩니다.</p>`;
if(tab==='speak')return `<h2>말하기 · 녹음</h2><p>${E(c.speakingPrompt||'Summarize the chapter in your own words.')}</p><textarea data-field="speaking" ${r.submitted?'disabled':''} placeholder="말하기 대본 (제출 필수)">${E(r.speaking)}</textarea><div class="row"><button data-act="record" ${r.submitted?'disabled':''}>● 녹음 시작</button><button data-act="stop">■ 녹음 종료</button><button data-act="downloadAudio">녹음 다운로드</button></div><p class="note">녹음은 이 기기에 자동 저장됩니다. 다른 기기에서는 동기화되지 않으므로 필요한 녹음은 파일로 백업하세요.</p><p id="cqMicHelp" class="note" role="status">녹음은 HTTPS 보안 주소에서 사용하는 것을 권장합니다. 내 파일에서 직접 연 HTML(content://)은 마이크 접근이 거부될 수 있습니다. 말하기 대본은 녹음과 별개로 저장됩니다.</p><div id="audioPreview"></div>`;
return `<h2>제출 · 부모 피드백</h2><p>상태: ${r.submitted?'제출 완료':'작성 중'}</p><p>제출일: ${E(r.submittedAt||'-')}</p><p class="note">${r.submitted&&r.feedbackReleased?E(r.feedback||'아직 작성된 피드백이 없습니다.'):r.submitted?'부모가 피드백을 검토 중이에요.':'전체 활동을 제출하면 부모 피드백을 확인할 수 있어요.'}</p><button class="primary" data-act="submit" ${r.submitted?'disabled':''}>${r.submitted?'제출 완료':'학습 제출'}</button>`}
function parentUI(){return `<section class="card"><div class="row between"><h2>👨‍👩‍👧 부모 관리자</h2><div class="row"><button data-act="importV3">V3 백업 가져오기</button><input type="file" id="v3Input" accept=".json" hidden><button data-act="backup">전체 백업</button><button data-act="restore">백업 복원</button><input type="file" id="restoreInput" accept=".json" hidden></div></div><p class="muted">학생 활성화, 책별 배정, 챕터 등록, AI 문제 승인, 월·목 학습 배정을 한 화면에서 관리합니다. 부모 PIN은 이 기기의 화면 잠금용입니다. 서버 게시와 학생 계정 관리는 부모 계정 로그인 후 사용합니다. 이 기기의 원본과 초안은 별도로 백업하세요.</p><h3>기기 데모 학생 설정</h3><div class="row">${state.students.map(x=>`<label class="chip"><input type="checkbox" data-active="${E(x.name)}" ${x.active?'checked':''}> ${E(x.name)} 학습 사용</label>`).join('')}</div></section><section class="card"><h2>📚 책 관리</h2><p class="note">책과 AI 초안은 이 기기에 먼저 저장됩니다. 학생 계정에서 학습하려면 원본 서버 등록과 승인 자료 게시를 완료하세요.</p><p class="muted">학생별 현재 학습 책을 선택하면 다음 미완료 챕터가 월·목 자동 배정됩니다.</p><div class="row"><label>집중 학습 책 <select id="focusBook"><option value="">첫 배정 책</option>${state.books.filter(b=>b.students.includes(state.who)).map(b=>`<option value="${E(b.id)}" ${state.focus?.[state.who]===b.id?'selected':''}>${E(b.title)}</option>`).join('')}</select></label></div><div class="row"><input id="bookTitle" placeholder="책 제목 (예: Magic Tree House #1)" style="flex:1"><button class="primary" data-act="addBook">+ 책 등록</button></div><div class="grid">${state.books.map(b=>`<div class="book"><b>${E(b.title)}</b><p>${b.chapters.length}개 챕터</p><div>${state.students.map(s=>`<label><input type="checkbox" data-bookstudent="${E(b.id)}" data-name="${E(s.name)}" ${b.students.includes(s.name)?'checked':''}> ${E(s.name)}에게 배정</label>`).join('')}</div><button data-act="manageBook" data-b="${E(b.id)}">챕터 관리</button></div>`).join('')}</div></section>${view==='manage'&&book()?manageUI():''}<section class="card"><h2>📅 이번 주 월·목 학습 배정</h2><label>배정 대상 학생 <select id="assignStudent">${state.students.map(x=>`<option value="${E(x.name)}" ${state.who===x.name?'selected':''}>${E(x.name)}</option>`).join('')}</select></label><p class="muted">이번 주 ${weekKey()} 시작 · 서진이가 함께 학습하는 주에는 같은 책·챕터를 두 학생에게 배정할 수 있습니다.</p>${['월','목'].map(d=>{const a=state.weekly[weekKey()]?.[state.who]?.[d];return `<div class="book"><b>${d}요일</b><div class="row"><select id="week-${d}"><option value="">선택 안 함</option>${state.books.flatMap(b=>b.chapters.map(c=>`<option value="${E(b.id+'|'+c.id)}" ${a?.bookId===b.id&&a?.chapterId===c.id?'selected':''}>${E(b.title)} · ${E(c.title)}</option>`)).join('')}</select><button data-act="assign" data-day="${d}">배정 저장</button></div></div>`}).join('')}</section><section class="card"><h2>📊 학생별 학습 기록</h2>${state.students.map(s=>`<div class="book"><b>${E(s.name)}</b>${state.books.flatMap(b=>b.chapters.map(c=>{let r=state.records[[s.name,b.id,c.id].join('::')];return r?`<div class="question"><b>${E(b.title)} · ${E(c.title)}</b> · ${r.submitted?'제출 완료':'작성 중'}<p>문제 답변 ${Object.keys(r.answers||{}).length}개 · 독후감 ${r.writing?.length||0}자</p><details><summary>답변 확인 · 피드백</summary>${c.questions.map((q,i)=>`<p><b>${i+1}. ${E(q.text)}</b><br>${E(q.kind==='mc'?q.options?.[r.answers[i]]??'미응답':r.answers[i]??'미응답')}</p>`).join('')}<p><b>독후감</b><br>${E(r.writing)}</p><textarea data-feedback="${E([s.name,b.id,c.id].join('::'))}" placeholder="부모 피드백">${E(r.feedback||'')}</textarea><label><input type="checkbox" data-release="${E([s.name,b.id,c.id].join('::'))}" ${r.feedbackReleased?'checked':''} ${r.submitted?'':'disabled'}> 피드백 학생에게 공개</label></details></div>`:''})).join('')||'<p class="muted">기록 없음</p>'}</div>`).join('')}</section>`}
function manageUI(){let b=book();return `<section class="card"><div class="row between"><h2>${E(b.title)} · 챕터 관리</h2><button data-act="closeManage">닫기</button></div><div class="row"><input id="chapterTitle" placeholder="예: Chapter 1" style="flex:1"><button class="primary" data-act="addChapter">+ 챕터 추가</button></div>${b.chapters.map(c=>`<div class="book"><div class="row between"><b>${E(c.title)}</b><button data-act="editChapter" data-c="${E(c.id)}">편집 / AI 문제 생성</button></div><p class="muted">승인된 문제 ${c.questions.length}개 · 단어 ${c.vocabulary.length}개 · PDF ${c.pdfStored?'등록됨':'미등록'} · AI용 텍스트 ${c.source?.length||0}자</p></div>`).join('')}${selectedChapter&&chapter()?editorUI(chapter()):''}</section>`}
function editorUI(c){if(!draft&&c.reviewDraft)draft=structuredClone(c.reviewDraft);return `<div class="card" style="background:#f8faff"><h3>${E(c.title)} · 학습 자료 편집</h3>${c.sourcePreviewOnly?'<p class="note">기존 서버 원본의 텍스트는 최대 10쪽의 참고 미리보기입니다. Chapter 1 원문으로 확정하지 않습니다. 학습 범위를 선택·미리보기·확인한 자료에서 문제를 준비하세요.</p>':''}<label>AI 문제 생성용 텍스트 (PDF 읽기 화면과 별개 · 붙여넣기)<textarea id="sourceText" style="min-height:180px">${E(c.source||'')}</textarea></label><div class="row"><input type="file" id="cqOriginalPDF" accept="application/pdf,.pdf,text/plain,.txt"><button data-act="savePDF">원본 PDF/TXT 등록</button></div><p class="muted">학생 읽기용 원본 PDF/TXT: ${c.pdfStored?'이 기기에 등록됨':'미등록'} · PDF 파일은 이 기기의 IndexedDB에 별도 저장됩니다. 기기 저장공간 정리 시 삭제될 수 있습니다. 다른 기기에서는 다시 등록해야 합니다. 일반 JSON 백업에는 원본 PDF/TXT 파일이 포함되지 않습니다.</p><div class="row"><button data-act="previewOriginal" ${c.pdfStored?'':'disabled'}>원본 미리보기</button><button data-act="extractSource">PDF/TXT에서 AI 텍스트 가져오기</button><button data-act="saveSource">AI용 텍스트 저장</button></div><div id="cqParentPdfViewer" hidden aria-label="부모 원본 미리보기"></div>${c.pdfRange?`<p class="note">확인한 학습 범위: ${E(c.pdfRange.sourceName)} · 원본 파일 ${c.pdfRange.start}–${c.pdfRange.end}쪽. 전체 원본은 별도로 보존됩니다.</p>`:''}${c.pdfStored&&c.readerType!=='txt'&&!c.pdfRange?`<section class="card" aria-label="PDF 페이지 범위 준비"><h4>기존 PDF에서 학습 범위 준비</h4><button type="button" data-pdf-range="inspect">페이지 수·목차 확인</button><pre id="cqPdfStructure" style="white-space:pre-wrap">${E(c.pdfInspection?'파일 '+c.pdfInspection.pageCount+'쪽 · '+(c.pdfInspection.title||'PDF 내부 제목 없음'):'원본 구성은 아직 확인하지 않았습니다.')}</pre><p>PDF 파일의 첫 페이지를 1쪽으로 셉니다. 책에 인쇄된 쪽 번호와 다를 수 있습니다. 위의 원본 미리보기에서 페이지를 넘기거나 쪽 이동 후 직접 선택하세요.</p><div class="row"><button type="button" data-pdf-range="pick-start">현재 원본 쪽을 시작으로 선택</button><button type="button" data-pdf-range="pick-end">현재 원본 쪽을 끝으로 선택</button></div><div class="row"><label>학습 제목<input id="cqRangeTitle" value="Chapter 1" maxlength="150"></label><label>시작 쪽<input id="cqRangeStart" type="number" min="1" step="1" placeholder="직접 선택"></label><label>끝 쪽<input id="cqRangeEnd" type="number" min="1" step="1" placeholder="직접 선택"></label><button type="button" data-pdf-range="preview">선택 범위 미리보기</button></div><div id="cqRangePreview" hidden></div><label><input id="cqRangeConfirmed" type="checkbox" disabled> 미리 본 범위가 이번 학습 범위임을 확인했습니다.</label><button id="cqRangePrepare" type="button" data-pdf-range="prepare" disabled>선택 범위만 이 기기에 등록</button><p id="cqRangeStatus" class="status" role="status"></p><p class="muted">기존 PDF/TXT는 보존합니다. 서버 원본을 다시 올리지 않고 선택 쪽의 파생 PDF만 별도 등록합니다. 문제 승인·학생 배정은 별도입니다.</p></section>`:''}<p class="muted">문제 생성용 텍스트를 위 입력란에 붙여넣으세요. 원본 파일이 등록되어야 학생이 챕터를 시작할 수 있습니다. TXT를 등록하면 AI용 텍스트도 함께 준비됩니다.</p><p class="muted">문제 생성은 부모 Supabase 로그인 후 사용할 수 있습니다.</p><input id="accessCode" type="hidden" value=""><div class="row"><button class="primary" data-act="generate">✨ AI 문제 초안 생성</button><button data-act="manualQuestion">+ 문제 직접 추가</button><button data-act="importDraft">AI 초안 JSON 가져오기</button><input id="cqDraftImport" type="file" accept="application/json,.json" hidden></div><p class="mutedline">AI 생성은 HTTPS 배포된 서버의 /api/generate가 필요합니다. 로컬 HTML 파일에서는 동작하지 않을 수 있습니다.</p>${draft&&draft.chapterId===c.id?draftUI():''}<h3>로컬 문제 (${c.questions.length})</h3><button data-act="reviewSaved" ${c.questions.length?'':'disabled'}>저장된 문제·정답·근거 수정</button><button data-act="approveManual" ${c.questions.length?'':'disabled'}>✓ 현재 문제 부모 승인</button><p class="muted">${c.approvalReceipt?'로컬 승인 기록 있음 · 수정 시 승인 무효화':'승인 기록 없음 · 서버 게시 불가'}</p>${c.questions.map((q,i)=>`<p>${i+1}. ${E(q.text)}</p>`).join('')||'<p>아직 승인된 문제가 없습니다.</p>'}<label>독후감 질문<textarea id="writingPrompt">${E(c.writingPrompt||'')}</textarea></label><label>말하기 질문<textarea id="speakingPrompt">${E(c.speakingPrompt||'')}</textarea></label><button data-act="savePrompts">학습 활동 저장</button><button data-act="checkPublication" data-c="${E(c.id)}">게시 가능 여부 확인</button><button data-parent-publish="publish" data-c="${E(c.id)}">승인 자료 게시 · 학생 배정</button></div><p class="note" id="cqPublicationStatus" role="status">부모 계정 로그인 후 검증된 원본 PDF와 게시 대상 학생을 선택하세요.</p>`}
function draftUI(){
 const evidence=(kind,i)=>{const item=draft.parentReview?.[kind]?.[i];if(!item)return '';return `<fieldset><legend>부모 전용 본문 근거</legend><label>PDF 파일 쪽<input data-evidence-${kind==='questions'?'q':'v'}="${i}" data-evidence-field="filePages" value="${E(item.filePages)}"></label><label>인쇄 쪽 (없으면 표시 없음)<input data-evidence-${kind==='questions'?'q':'v'}="${i}" data-evidence-field="printedPages" value="${E(item.printedPages)}"></label><label>근거·검토 메모<textarea data-evidence-${kind==='questions'?'q':'v'}="${i}" data-evidence-field="note">${E(item.note)}</textarea></label></fieldset>`};
 return `<div class="card" id="cqParentDraftReview"><h3>문제 초안 검토 · 부모 전용</h3><p>정답·근거를 수정한 뒤 승인하세요. 서버 게시와 학생 배정은 별도입니다.</p>${draft.questions.map((q,i)=>`<div class="question"><label>문제 ${i+1}<textarea data-draftq="${i}">${E(q.text)}</textarea></label><small>${E(q.kind)}</small>${q.kind==='mc'?`${q.options.map((o,j)=>`<label>선택지 ${j+1}<input data-review-q="${i}" data-review-option="${j}" value="${E(o)}"></label>`).join('')}<label>부모용 정답<select data-review-q="${i}" data-review-field="correct">${q.options.map((o,j)=>`<option value="${j}" ${j===q.correct?'selected':''}>${j+1}번</option>`).join('')}</select></label>`:`<label>부모용 모범 답안<textarea data-review-q="${i}" data-review-field="sample">${E(q.sample||'')}</textarea></label>`}${evidence('questions',i)}</div>`).join('')}<h4>핵심 단어</h4>${draft.vocabulary.map((v,i)=>`<fieldset><legend>단어 ${i+1}</legend>${['word','meaning','example'].map((field,j)=>`<label>${['영어 단어','한국어 뜻','학습 예문'][j]}<input data-review-v="${i}" data-review-field="${field}" value="${E(v[field]||'')}"></label>`).join('')}${evidence('vocabulary',i)}</fieldset>`).join('')}<label>영어 글쓰기<textarea data-draftactivity="writingPrompt">${E(draft.writingPrompt)}</textarea></label><label>말하기 녹음<textarea data-draftactivity="speakingPrompt">${E(draft.speakingPrompt)}</textarea></label>${draft.parentReview?`<label><input type="checkbox" id="cqEvidenceConfirmed"> 실제 본문과 문제·정답·단어·활동의 근거를 확인했습니다.</label>`:'<button data-act="addEvidence">부모 전용 본문 근거 추가</button><p class="muted">본문 근거 자료가 없는 초안입니다. 원문을 직접 대조하세요.</p>'}<p id="cqDraftReviewStatus" role="status">아직 승인되지 않은 검토 초안입니다.</p><button class="primary" data-act="approve">부모 승인 저장 · 서버 게시 별도</button><button data-act="cancelDraft">초안 취소</button></div>`;
}
function persistReviewDraft(){const c=chapter();if(!c||!draft||draft.chapterId!==c.id)return;invalidateApproval(c);c.reviewDraft=structuredClone(draft);const check=$('#cqEvidenceConfirmed');if(check)check.checked=false;if(!save())setStatus('초안 저장 실패. 화면을 닫지 말고 백업하세요.');const status=$('#cqDraftReviewStatus');if(status)status.textContent='변경됨 · 본문 근거를 다시 확인한 뒤 승인하세요.';}
async function extractFile(file){if(!file)return;try{let text='';if(file.name.toLowerCase().endsWith('.pdf')){if(!window.pdfjsLib)throw Error('PDF 읽기 라이브러리를 불러오지 못했습니다. TXT로 변환해 등록하세요.');const pdf=await pdfjsLib.getDocument({isEvalSupported:false,data:await file.arrayBuffer()}).promise;for(let i=1;i<=pdf.numPages;i++){let pg=await pdf.getPage(i),tc=await pg.getTextContent();text+=tc.items.map(x=>x.str).join(' ')+'\n'}}else{text=await file.text()}$('#sourceText').value=text;setStatus('AI 문제용 텍스트 '+text.length+'자 추출. 텍스트 저장을 눌러주세요.')}catch(e){alert(e.message)}}
function download(name,content,type='application/json'){const blob=content instanceof Blob?content:new Blob([content],{type});const u=URL.createObjectURL(blob),a=document.createElement('a');a.href=u;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(u),10000)}

// Stage65: validate AI output before a parent can publish it.
function cqValidateAIDraft(d){
 if(!d||!Array.isArray(d.questions)||!d.questions.length||d.questions.length>30)return '문제는 1~30개여야 합니다.';
 if(!Array.isArray(d.vocabulary)||d.vocabulary.length>100)return '단어 목록 형식이 잘못되었습니다.';
 for(const [i,q] of d.questions.entries()){
  if(!q||typeof q.text!=='string'||!q.text.trim()||q.text.length>2000)return `${i+1}번 문제 내용을 확인하세요.`;
  if(!['mc','inference','critical','short','comprehension'].includes(q.kind))return `${i+1}번 문제 종류를 확인하세요.`;
  if(q.kind!=='mc'&&(typeof q.sample!=='string'||!q.sample.trim()||q.sample.length>2000))return `${i+1}번 모범 답안을 확인하세요.`;
  if(q.kind==='mc'){
   if(!Array.isArray(q.options)||q.options.length<2||q.options.length>6||q.options.some(o=>typeof o!=='string'||!o.trim()||o.length>500))return `${i+1}번 선택지를 확인하세요.`;
   if(!Number.isInteger(q.correct)||q.correct<0||q.correct>=q.options.length)return `${i+1}번 정답 번호를 확인하세요.`;
  }
 }
 for(const v of d.vocabulary){if(!v||typeof v.word!=='string'||!v.word.trim()||v.word.length>100||typeof v.meaning!=='string'||!v.meaning.trim()||v.meaning.length>500||(v.example!==undefined&&(typeof v.example!=='string'||v.example.length>1000)))return '단어와 뜻을 확인하세요.';}
 if(d.parentReview!==undefined){
  const r=d.parentReview;
  if(!r||typeof r!=='object'||Array.isArray(r))return '부모 근거 자료 형식이 잘못되었습니다.';
  for(const [key,count] of [['questions',d.questions.length],['vocabulary',d.vocabulary.length]]){
   if(!Array.isArray(r[key])||r[key].length!==count)return '문제·단어별 근거 개수를 확인하세요.';
   for(const e of r[key])if(!e||typeof e.filePages!=='string'||!e.filePages.trim()||e.filePages.length>100||typeof e.printedPages!=='string'||e.printedPages.length>100||typeof e.note!=='string'||!e.note.trim()||e.note.length>2000)return '본문 근거의 PDF 쪽·인쇄 쪽·메모를 확인하세요.';
  }
 }
 for(const field of ['writingPrompt','speakingPrompt'])if(typeof d[field]!=='string'||!d[field].trim()||d[field].length>2000)return '독후감·말하기 질문을 확인하세요.';
 return '';
}
async function handleClick(e){const btn=e.target.closest('[data-act]');if(!btn)return;const a=btn.dataset.act,bid=btn.dataset.b,cid=btn.dataset.c;
const studentActions=new Set(['home','open','tab','submit','speakword','record','stop','downloadAudio']);
if(!studentActions.has(a)&&(!parentUnlocked||mode!=='parent')){alert('부모 관리자 인증이 필요합니다.');return}

if(a==='home'){view='home';render()}
if(a==='open'){
 const targetBook=state.books.find(b=>b.id===bid&&b.students.includes(state.who));
 const targetChapter=targetBook?.chapters.find(c=>c.id===cid&&chapterReady(c));
 if(!targetChapter)return alert('이 학생에게 공개된 학습 챕터가 아닙니다.');
 if(!state.students.find(x=>x.name===state.who)?.active)return alert('현재 학습 대기 상태입니다. 부모 관리자에서 학생을 활성화해 주세요.');
 // A JSON backup can retain pdfStored=true even when the binary PDF is absent.
 // Verify the actual IndexedDB file before opening the learning session.
 try{
  const stored=await pdfGet(pdfKey(bid,cid));
  if(!stored||!stored.size){alert('이 기기에 원본 PDF가 없습니다. 부모 관리자에서 해당 챕터의 PDF를 다시 등록해 주세요.');return}
  if(targetChapter.readerType==='txt')await originalText(stored);
  else {
  const signature=new Uint8Array(await stored.slice(0,5).arrayBuffer());
  if(String.fromCharCode(...signature)!=='%PDF-')throw Error('PDF 파일 형식이 손상되었습니다.');
  }
 }catch(err){alert('원본 PDF 확인 실패: '+err.message);return}
 choose(bid,cid)
}
if(a==='tab'){tab=btn.dataset.tab;render()}
if(a==='submit'){if(mode!=='student')return;let r=rec();if(r.submitted)return alert('이미 제출한 학습입니다.');const c=chapter();if(!chapterReady(c))return alert('원본 PDF와 학습 문제가 모두 준비된 챕터만 제출할 수 있습니다.');try{const f=await pdfGet(pdfContext());if(!f?.size)throw Error('원본 PDF가 저장되어 있지 않습니다.');}catch(err){return alert('제출 전 PDF 확인 실패: '+err.message)}if(!r.read)return alert('원문 읽기를 완료한 뒤 읽기 완료에 체크해 주세요.');const missing=(c.questions||[]).findIndex((q,i)=>r.answers?.[i]===undefined||String(r.answers[i]).trim()==='');if(missing>=0)return alert((missing+1)+'번 문제에 답변한 뒤 제출해 주세요.');if(!String(r.writing||'').trim())return alert('영어 독후감을 작성한 뒤 제출해 주세요.');if(!String(r.speaking||'').trim())return alert('말하기 대본을 작성한 뒤 제출해 주세요.');r.submitted=true;r.submittedAt=new Date().toLocaleString('ko-KR');save();render();alert('학습 답변이 제출되었습니다.')}
if(a==='speakword'){speechSynthesis.speak(new SpeechSynthesisUtterance(btn.dataset.word))}
if(a==='addBook'){let title=$('#bookTitle').value.trim();if(!title)return alert('책 제목을 입력하세요.');let b={id:uid(),title,students:['서우'],chapters:[]};state.books.push(b);selectedBook=b.id;view='manage';save();render()}
if(a==='manageBook'){selectedBook=bid;selectedChapter='';draft=null;view='manage';render()}
if(a==='closeManage'){view='home';selectedChapter='';render()}
if(a==='addChapter'){let title=$('#chapterTitle').value.trim();if(!title)return alert('챕터 이름을 입력하세요.');let c={id:uid(),title,source:'',questions:[],vocabulary:[],writingPrompt:'',speakingPrompt:''};book().chapters.push(c);selectedChapter=c.id;save();render()}
if(a==='editChapter'){selectedChapter=cid;draft=null;render()}
if(a==='savePDF'){
 const c=chapter(),file=$('#cqOriginalPDF')?.files?.[0];
 if(!file)return alert('PDF 또는 TXT 파일을 선택하세요.');
 const isText=file.name.toLowerCase().endsWith('.txt'),expectedContext=pdfContext(),addButton=$('[data-act="addChapter"]');btn.disabled=true;if(addButton)addButton.disabled=true;
 try{
  let text='';
  if(isText)text=await originalText(file);
  else {
   if(file.type!=='application/pdf'&&!file.name.toLowerCase().endsWith('.pdf'))throw Error('PDF 또는 UTF-8 TXT 파일만 등록할 수 있습니다.');
   if(!file.size||file.size>50*1024*1024)throw Error('PDF는 50MB 이하로 등록하세요.');
   const header=new Uint8Array(await file.slice(0,5).arrayBuffer());
   if(String.fromCharCode(...header)!=='%PDF-')throw Error('PDF 형식이 올바르지 않습니다.');
  }
  if(pdfContext()!==expectedContext||chapter()!==c||mode!=='parent'||!parentUnlocked)throw Error('저장 중 챕터가 변경되었습니다.');
  await pdfPut(expectedContext,file);
  const verified=await pdfGet(expectedContext);
  if(pdfContext()!==expectedContext||chapter()!==c)throw Error('저장 중 챕터가 변경되었습니다.');
  if(!verified||verified.size!==file.size)throw Error('원본 파일 저장 확인 실패');
  invalidateApproval(c);c.pdfStored=true;c.pdfName=file.name;c.readerType=isText?'txt':'pdf';delete c.serverPdfUuid;delete c.serverPdfOrigin;delete c.serverPdfOwner;delete c.serverOriginalCopy;delete c.serverRangeVerified;delete c.pdfInspection;delete c.pdfRange;
  if(isText)c.source=text;
  save();render();setStatus(isText?'원본 TXT 저장 완료 · AI 문제용 텍스트도 준비됐습니다.':'원본 PDF 저장 완료 · 학생 읽기 화면에 표시됩니다.');
 }catch(err){alert('원본 파일 저장 실패: '+err.message)}finally{if(btn.isConnected)btn.disabled=false;if(addButton?.isConnected)addButton.disabled=false;}return;
}
if(a==='previewOriginal'){
 const target=$('#cqParentPdfViewer');if(!target)return;target.hidden=false;if($('#cqRangePreview'))$('#cqRangePreview').hidden=true;btn.disabled=true;
 try{await showChapterPDF('cqParentPdfViewer')}finally{if(btn.isConnected)btn.disabled=false}return;
}
if(a==='extractSource'){
 const currentChapter=chapter(),context=pdfContext();btn.disabled=true;let doc=null;
 try{const file=await pdfGet(context);if(!file)throw Error('원본 파일을 먼저 등록하세요.');let text='';
  if(currentChapter.readerType==='txt')text=await originalText(file);
  else{if(!window.pdfjsLib)throw Error('PDF 읽기 도구를 불러오지 못했습니다.');doc=await pdfjsLib.getDocument({data:new Uint8Array(await file.arrayBuffer()),isEvalSupported:false}).promise;for(let page=1;page<=doc.numPages;page++){const data=await(await doc.getPage(page)).getTextContent();text+=data.items.map(x=>x.str).join(' ')+'\n';if(text.length>500000)throw Error('원문이 너무 깁니다. 챕터별 PDF로 나눠 주세요.');}}
  if(chapter()!==currentChapter||pdfContext()!==context||mode!=='parent'||!parentUnlocked)throw Error('챕터 또는 계정이 변경되었습니다.');
  if(text.trim().length<250)throw Error('텍스트가 부족합니다. 스캔 PDF라면 원문 텍스트를 별도로 붙여 넣어 주세요.');
  $('#sourceText').value=text;setStatus('원문 텍스트 '+text.length+'자 추출 완료. 검토 후 AI용 텍스트를 저장하세요.');
 }catch(error){alert('텍스트 추출 실패: '+error.message)}finally{if(doc)await doc.destroy();if(btn.isConnected)btn.disabled=false;}return;
}
if(a==='saveSource'){let c=chapter();if(c.source!==$('#sourceText').value){invalidateApproval(c);c.source=$('#sourceText').value;}if(save())setStatus('AI 문제 생성용 텍스트 저장 완료')}
if(a==='savePrompts'){let c=chapter(),w=$('#writingPrompt').value,sp=$('#speakingPrompt').value;if(c.writingPrompt!==w||c.speakingPrompt!==sp)invalidateApproval(c);c.writingPrompt=w;c.speakingPrompt=sp;if(save())setStatus('학습 활동 저장 완료')}
if(a==='importDraft'){$('#cqDraftImport').click();return;}
if(a==='generate'){let c=chapter();if(c.serverOriginalCopy&&!c.pdfRange)return alert('기존 서버 원본의 학습 범위를 먼저 선택하고 미리보기로 확인하세요.');let source=$('#sourceText').value.trim();const expectedBook=book(),expectedChapter=c,expectedParent=window.CQParentAI?.identity?.();if(source.length<250||source.length>45000)return alert('원문은 250~45,000자로 챕터별로 나눠 주세요.');if(c.source!==source){invalidateApproval(c);c.source=source;}state.code=$('#accessCode').value.trim();draft=null;btn.disabled=true;let sourceSaved=false;setStatus('AI 문제를 생성하는 중입니다...');try{sourceSaved=save();if(!sourceSaved)throw Error('원문을 이 기기에 저장하지 못해 문제 생성을 중단했습니다. 원본을 백업하고 저장 공간을 확인하세요.');const authHeaders=await window.CQParentAI.authorization();const response=await fetch('/api/generate',{method:'POST',signal:AbortSignal.timeout(90000),headers:{'Content-Type':'application/json',...authHeaders},body:JSON.stringify({title:book().title,chapter:c.title,source})});const data=await response.json();if(chapter()!==expectedChapter||book()!==expectedBook||mode!=='parent'||!parentUnlocked||window.CQParentAI?.identity?.()!==expectedParent||$('#sourceText')?.value.trim()!==source)throw Error('생성 중 계정 또는 자료가 변경되었습니다. 현재 자료에서 다시 생성하세요.');if(!response.ok)throw Error(data.error||'AI 서버 오류 '+response.status);if(!Array.isArray(data.questions)||!Array.isArray(data.vocabulary))throw Error('AI 응답 형식이 올바르지 않습니다.');draft={chapterId:c.id,questions:data.questions.map(q=>({kind:q.kind||'inference',text:q.text||q.q||'',options:q.options||q.opts||[],correct:Number(q.correct??q.a??0),sample:q.sample||q.answer||''})),vocabulary:data.vocabulary.map(v=>Array.isArray(v)?{word:v[0],meaning:v[1],example:v[2]||''}:v),writingPrompt:data.writingPrompt||data.writing?.prompt||'',speakingPrompt:(Array.isArray(data.speakingPrompts)?data.speakingPrompts.join('\n'):data.speakingPrompt||data.speaking?.prompt||'')};const issue=cqValidateAIDraft(draft);if(issue){draft=null;throw Error('AI 응답 검증 실패: '+issue)}persistReviewDraft();render();setStatus('AI 초안 생성 완료. 검토 후 승인하세요.')}catch(e){alert('AI 생성 실패: '+(e.name==='TimeoutError'?'응답 시간이 초과됐습니다. 저장한 원문은 유지됩니다. 잠시 후 다시 시도하거나 JSON 초안 가져오기를 사용하세요.':e.message));setStatus(sourceSaved?'AI 생성 실패 · 저장한 원문은 유지됩니다.':'AI 생성 중단 · 원문 저장 실패. 화면을 닫지 말고 백업하세요.')}finally{btn.disabled=false}}
if(a==='approve'){
 if(!draft)return;const current=draft,c=chapter(),expectedBook=book();if(!c||draft.chapterId!==c.id)return alert('AI 초안과 현재 챕터가 다릅니다. 다시 생성해 주세요.');
 const reviewed=structuredClone(draft),issue=cqValidateAIDraft(reviewed);if(issue)return alert(issue);
 if(reviewed.parentReview&&!$('#cqEvidenceConfirmed')?.checked)return alert('실제 본문과 정답·근거 확인란을 체크하세요.');
 const values={questions:reviewed.questions,vocabulary:reviewed.vocabulary,writingPrompt:reviewed.writingPrompt,speakingPrompt:reviewed.speakingPrompt};
 const candidate={...c,...values};if(reviewed.parentReview)candidate.parentReview=reviewed.parentReview;else delete candidate.parentReview;
 const hash=await approvalDigest(candidate);
 if(draft!==current||chapter()!==c||book()!==expectedBook||mode!=='parent'||!parentUnlocked||JSON.stringify(draft)!==JSON.stringify(reviewed)||(reviewed.parentReview&&!$('#cqEvidenceConfirmed')?.checked))return alert('승인 중 계정 또는 초안이 변경되었습니다. 다시 검토하세요.');
 const previous=structuredClone(c);Object.assign(c,values);if(reviewed.parentReview)c.parentReview=reviewed.parentReview;else delete c.parentReview;
 delete c.reviewDraft;c.approvalReceipt={version:1,sha256:hash,approvedAt:new Date().toISOString(),scope:'local-only'};
 if(!save()){for(const k of Object.keys(c))delete c[k];Object.assign(c,previous);return alert('승인 저장 실패. 기존 자료와 초안을 보존했습니다.');}
 draft=null;render();alert('이 기기에서 부모 승인이 완료되었습니다. 학생 계정에 보내려면 승인 자료 게시를 사용하세요.');
}
if(a==='addEvidence'&&draft){draft.parentReview={questions:draft.questions.map(()=>({filePages:'',printedPages:'',note:''})),vocabulary:draft.vocabulary.map(()=>({filePages:'',printedPages:'',note:''}))};persistReviewDraft();render();}
if(a==='reviewSaved'){const c=chapter();invalidateApproval(c);draft={chapterId:c.id,questions:structuredClone(c.questions),vocabulary:structuredClone(c.vocabulary||[]),writingPrompt:c.writingPrompt||'',speakingPrompt:c.speakingPrompt||'',...(c.parentReview?{parentReview:structuredClone(c.parentReview)}:{})};persistReviewDraft();render();}

if(a==='checkPublication'){
 const c=chapter(),currentBook=selectedBook,currentChapter=selectedChapter;
 if(!c||c.id!==cid)return alert('현재 챕터를 다시 선택하세요.');
 btn.disabled=true;
 try{
  const result=await cqPublicationEligibility(c);
  // A pending hash operation must never update a different chapter or a locked parent screen.
  if(mode!=='parent'||!parentUnlocked||selectedBook!==currentBook||selectedChapter!==currentChapter||chapter()!==c)return;
  const target=$('#cqPublicationStatus');
  if(target)target.textContent=(result.ok?'✓ ':'⚠ ')+result.reason+(result.ok?' · 실제 서버에 게시하지 않았습니다.':'');
 }catch(error){
  if(mode==='parent'&&parentUnlocked&&selectedBook===currentBook&&selectedChapter===currentChapter){const target=$('#cqPublicationStatus');if(target)target.textContent='⚠ 게시 검증 실패: '+error.message;}
 }finally{if(btn.isConnected)btn.disabled=false;}
}
if(a==='cancelDraft'){if(chapter())delete chapter().reviewDraft;draft=null;save();render()}
if(a==='approveManual'){
 if(chapter()?.reviewDraft||chapter()?.parentReview)return alert('문제·정답·근거 수정 화면에서 검토 초안을 확인하고 승인하세요.');
 if(mode!=='parent'||!parentUnlocked)return alert('부모 관리자 잠금 해제 후 승인할 수 있습니다.');
 const c=chapter(),expectedBook=selectedBook,expectedChapter=selectedChapter;
 if(!c||!chapterReady(c))return alert('원본 PDF와 유효한 문제를 먼저 등록하세요.');
 if(!confirm('현재 챕터의 문제 '+c.questions.length+'개를 검토하고 승인하시겠습니까?'))return;
 const hash=await approvalDigest(c);
 if(mode!=='parent'||!parentUnlocked||selectedBook!==expectedBook||selectedChapter!==expectedChapter||chapter()!==c||hash!==await approvalDigest(c))return alert('승인 도중 자료가 변경되어 중단했습니다.');
 c.approvalReceipt={version:1,sha256:hash,approvedAt:new Date().toISOString(),scope:'local-only'};
 save();render();alert('현재 문제의 부모 승인이 완료됐습니다. 서버 게시 및 다른 기기 동기화는 별도입니다.');
}
if(a==='manualQuestion'){let text=prompt('문제 내용을 입력하세요.');if(!text?.trim())return;let sample=prompt('부모 검토용 모범 답안을 입력하세요. 학생에게는 공개되지 않습니다.');if(!sample?.trim())return;let c=chapter();invalidateApproval(c);c.questions.push({kind:'inference',text:text.trim(),sample:sample.trim()});save();render()}
if(a==='assign'){let d=btn.dataset.day,v=$('#week-'+d).value;state.weekly[weekKey()]??={};state.weekly[weekKey()][state.who]??={};if(v){let [bookId,chapterId]=v.split('|');state.weekly[weekKey()][state.who][d]={bookId,chapterId}}else delete state.weekly[weekKey()][state.who][d];save();render()}
if(a==='backup')download('chapter-quest-backup-'+new Date().toISOString().slice(0,10)+'.json',JSON.stringify({format:'chapter-quest-v4',state:{...state,code:''}},null,2));
if(a==='restore')$('#restoreInput').click();
if(a==='importV3')$('#v3Input').click();
if(a==='record'){if(rec().submitted)return alert('제출한 학습은 녹음을 수정할 수 없습니다.');if(!navigator.mediaDevices?.getUserMedia)return alert('이 브라우저는 녹음을 지원하지 않습니다.');try{let stream=await navigator.mediaDevices.getUserMedia({audio:true});recordChunks=[];const targetKey=key(),recorder=new MediaRecorder(stream),chunks=[];recording=recorder;recorder.ondataavailable=e=>{if(e.data.size)chunks.push(e.data)};recorder.onstop=async()=>{const blob=new Blob(chunks,{type:recorder.mimeType||'audio/webm'});stream.getTracks().forEach(t=>t.stop());try{await CQAudio.put(targetKey,blob);if(key()===targetKey){audioBlob=blob;setStatus('녹음이 이 기기에 저장되었습니다.');await loadAudio()}}catch(e){if(key()===targetKey)setStatus('녹음 자동 저장 실패: '+e.message)}if(recording===recorder)recording=null};recorder.start();setStatus('녹음 중...')}catch(e){const denied=e?.name==='NotAllowedError'||e?.name==='PermissionDeniedError'||/permission denied|not allowed/i.test(String(e?.message||''));const hint=denied?'마이크 접근이 거부되었습니다. 내 파일에서 연 content:// 주소라면 HTTPS로 배포된 앱에서 다시 시도하세요. HTTPS에서도 거부되면 Chrome 사이트 설정의 마이크 권한을 확인하세요.':'마이크 오류: '+(e?.message||String(e));setStatus(hint);const help=$('#cqMicHelp');if(help)help.textContent=hint;alert(hint)}}
if(a==='stop'){if(recording?.state==='recording')recording.stop()}
if(a==='downloadAudio'){let b=audioBlob||await CQAudio.get(key());if(!b)return alert('저장된 녹음이 없습니다.');download('chapter-quest-'+state.who+'-'+chapter().title+'.webm',b,'audio/webm')}
}
document.addEventListener('click',handleClick);
document.addEventListener('input',e=>{let t=e.target;if((t.matches('[data-draftq],[data-review-q],[data-review-v],[data-draftactivity],[data-evidence-q],[data-evidence-v]')||t.matches('[data-feedback]'))&&(!parentUnlocked||mode!=='parent'))return;if(t.matches('[data-q]')&&!rec().submitted){rec().answers[t.dataset.q]=t.value;save()}if((t.dataset.field==='writing'||t.dataset.field==='speaking')&&!rec().submitted){rec()[t.dataset.field]=t.value;save()}if(t.matches('[data-draftq]')&&draft){draft.questions[Number(t.dataset.draftq)].text=t.value;persistReviewDraft()}if(draft){
 if(t.matches('[data-review-q]')){const q=draft.questions[Number(t.dataset.reviewQ)];if(t.dataset.reviewOption!==undefined)q.options[Number(t.dataset.reviewOption)]=t.value;else q[t.dataset.reviewField]=t.dataset.reviewField==='correct'?Number(t.value):t.value;persistReviewDraft();}
 if(t.matches('[data-review-v]')){draft.vocabulary[Number(t.dataset.reviewV)][t.dataset.reviewField]=t.value;persistReviewDraft();}
 if(t.matches('[data-draftactivity]')){draft[t.dataset.draftactivity]=t.value;persistReviewDraft();}
 if(t.matches('[data-evidence-q],[data-evidence-v]')){const key=t.dataset.evidenceQ!==undefined?'questions':'vocabulary',i=Number(t.dataset.evidenceQ??t.dataset.evidenceV);draft.parentReview[key][i][t.dataset.evidenceField]=t.value;persistReviewDraft();}
 }if(t.matches('[data-feedback]')){state.records[t.dataset.feedback].feedback=t.value;state.records[t.dataset.feedback].feedbackReleased=false;save()}});
document.addEventListener('change',async e=>{let t=e.target;if(t.id==='cqDraftImport'){const file=t.files?.[0];t.value='';if(!file)return;if(mode!=='parent'||!parentUnlocked)return;const target=chapter();try{if(file.size>200000)throw Error('초안은 200KB 이하 JSON 파일이어야 합니다.');const value=JSON.parse(await file.text());if(chapter()!==target||mode!=='parent'||!parentUnlocked)throw Error('현재 챕터가 변경되었습니다.');const issue=cqValidateAIDraft(value);if(issue)throw Error(issue);draft={...value,chapterId:target.id};persistReviewDraft();render();setStatus('초안을 가져왔습니다. 원문과 정답을 검토한 뒤 승인하세요.');}catch(err){alert('초안 가져오기 실패: '+err.message)}return;}
if((t.id==='assignStudent'||t.id==='focusBook'||t.dataset.active||t.dataset.bookstudent||t.id==='v3Input'||t.id==='restoreInput')&&(!parentUnlocked||mode!=='parent')){alert('부모 관리자 인증이 필요합니다.');render();return}
if(t.id==='student'||t.id==='assignStudent'){changeStudent(t.value)}if(t.id==='focusBook'){state.focus??={};state.focus[state.who]=t.value;save();render()}if(t.dataset.release){const r=state.records[t.dataset.release];if(r&&r.submitted&&parentUnlocked&&mode==='parent'){if(t.checked&&!String(r.feedback||'').trim()){alert('피드백을 작성한 뒤 공개해 주세요.');render();return}r.feedbackReleased=t.checked;save();render()}}if(t.dataset.field==='read'&&!rec().submitted){rec().read=t.checked;save()}if(t.dataset.active){let s=state.students.find(x=>x.name===t.dataset.active);s.active=t.checked;save();render()}if(t.dataset.bookstudent){let b=state.books.find(x=>x.id===t.dataset.bookstudent),n=t.dataset.name;b.students=t.checked?[...new Set([...b.students,n])]:b.students.filter(x=>x!==n);save()}if(t.id==='textFile')await extractFile(t.files[0]);if(t.id==='v3Input'){let f=t.files[0];if(!f)return;try{let old=JSON.parse(await f.text()),result=CQCore.migrateV3(old,state);if(!confirm(`V3 책 ${result.importedBooks}권, 학습 기록 ${result.importedRecords}개를 가져올까요?\n기존 V4 기록은 유지됩니다. 녹음 ${result.skippedAudio}개는 가져오지 않습니다.`))return;state=result.state;save();render();alert('V3 학습 데이터 가져오기 완료')}catch(err){alert('V3 이전 실패: '+err.message)}}if(t.id==='restoreInput'){let f=t.files[0];if(!f)return;try{let v=JSON.parse(await f.text());if(v.format!=='chapter-quest-v4'||!v.state?.books)throw Error('이 버전의 백업 파일이 아닙니다.');if(!confirm('현재 V4 데이터를 백업 파일로 교체할까요?'))return;const checked=CQState.normalize(v.state,STUDENTS);state=checked.state;storageWriteBlocked=false;save();view='home';render()}catch(err){alert('복원 실패: '+err.message)}}});
$('#studentBtn').onclick=()=>{mode='student';parentUnlocked=false;view='home';render()};
$('#parentBtn').onclick=async()=>{if(!await requestParentAccess())return;mode='parent';view='home';render()};
initState();render();
