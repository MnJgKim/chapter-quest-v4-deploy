/* Optional parent-only cloud sync UI. No automatic overwrites. */
(() => {
 let session=null, project=null, busy=false, auto=false, baseline=undefined, aligned=false, syncTimer=null, syncing=false, dirty=false, revision=0, refreshPromise=null, sessionGeneration=0;
 const escapeHtml=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const readProject=()=>{try{return window.CQProject.read()}catch{return null}};
 project=readProject();
 const status=t=>{const el=document.getElementById('cloudStatus');if(el)el.textContent=t};
 // Stage131: parent cloud actions use the stage130 storage contract.
 // This does not replace the local student workflow or enforce server-side RLS.
 const parentStore=()=>{
   if(!session?.uid||!project)throw Error('부모 클라우드 로그인이 필요합니다.');
   const owner=cloudIdentity();
   const guard=()=>{if(!owner||cloudIdentity()!==owner)throw Error('계정이 변경되었습니다.');};
   return CQStorage130.createStorage({mode:'cloud',identity:{role:'parent',userId:session.uid},cloud:{
     pull:async()=>{guard();const value=await CQCloud.pull();guard();return value;},
     pushIfUnchanged:async(snapshot,expectedRevision)=>{guard();const value=await CQCloud.pushIfUnchanged(snapshot,expectedRevision);guard();return value;}
   }});
 };

 const auth=async(path,body)=>{
   const response=await fetch(project.url+'/auth/v1/'+path,{method:'POST',headers:{apikey:project.anonKey,'Content-Type':'application/json'},body:JSON.stringify(body)});
   const data=await response.json();if(!response.ok)throw Error(data.msg||data.error_description||data.message||'인증 오류');return data;
 };
 async function refreshIfNeeded(){
   if(!session)return;
   if(Date.now()<session.expiresAt-60000)return;
   if(refreshPromise)return refreshPromise;
   const generation=sessionGeneration;
   refreshPromise=(async()=>{
     if(!session?.refreshToken)throw Error('로그인 시간이 만료되었습니다. 다시 로그인하세요.');
     const result=await auth('token?grant_type=refresh_token',{refresh_token:session.refreshToken});
     if(generation!==sessionGeneration||!session)throw Error('로그인 상태가 변경되었습니다.');
     if(!result.access_token||!result.refresh_token)throw Error('로그인 갱신에 실패했습니다.');
     session.token=result.access_token;session.refreshToken=result.refresh_token;
     session.expiresAt=Date.now()+(result.expires_in||3600)*1000;
     CQCloud.updateToken(session.token);
   })();
   try{await refreshPromise}finally{refreshPromise=null}
 }
 const panel=()=>`<section class="card" id="cloudPanel"><h2>☁️ 부모 계정 로그인 · 백업</h2><p class="note" id="stage131Mode">기기에서 준비한 학습 자료를 부모 계정에 백업할 수 있습니다. 다른 기기의 학생에게 자료를 보내려면 PDF 등록과 승인 자료 서버 게시를 진행하세요.</p><p class="muted">Supabase 로그인 후 명시적으로 저장·복원합니다. 자동 동기화는 로그인 후 선택적으로 활성화할 수 있습니다. 다른 기기와의 실시간 병합은 지원하지 않습니다.</p>
 <div class="grid"><label>프로젝트 URL<input class="wide" id="cloudUrl" placeholder="https://xxxx.supabase.co" value="${escapeHtml(project?.url||'')}"></label><label>공개 키 (anon/publishable)<input class="wide" id="cloudKey" value="${escapeHtml(project?.anonKey||'')}"></label></div>
 <div class="row"><button data-cloud="project">프로젝트 설정 저장</button><span class="muted">service_role 비밀키는 절대 입력하지 마세요.</span></div>
 <div class="grid"><label>부모 이메일<input class="wide" id="cloudEmail" type="email" autocomplete="email"></label><label>비밀번호<input class="wide" id="cloudPassword" type="password" autocomplete="current-password"></label></div>
 <div class="row"><button data-cloud="login">로그인</button><button data-cloud="logout">로그아웃</button><button data-cloud="push" ${session?'':'disabled'}>현재 기록 클라우드에 저장</button><button data-cloud="pull" ${session?'':'disabled'}>클라우드 기록 복원</button></div>
 <label><input type="checkbox" id="cloudAuto" ${auto?'checked':''} ${session?'':'disabled'}> 이 탭에서 변경 사항 자동 동기화</label><p class="note">클라우드 복원 시 기존 로컬 기록을 먼저 JSON으로 자동 백업합니다. 다른 기기의 기록과 자동 병합하지 않습니다.</p><p id="cloudStatus" class="status">${session?'로그인됨':'로그인 필요'}</p></section>`;
 let submissions=[]; let feedbackBusy=false; let pendingChildren=[]; let issuedInvite="";
 const parentStatus=t=>{const e=document.getElementById('cqParentFeedbackStatus');if(e)e.textContent=t};
 const invitationPanel=()=>!parentUnlocked||!session?'':`<section class="card"><h2>🔗 학생 계정 초대·승인·연결 해제 (시험 기능)</h2><p class="muted">부모 Supabase 로그인 후 일회용 코드를 발급하세요. 코드는 15분 유효하며 학생이 요청한 뒤 부모가 승인해야 합니다. 연결 해제 후 다시 연결하려면 새 초대코드를 발급하고 학생이 다시 요청해야 합니다.</p><button data-parent-invite="issue">초대코드 발급</button><p id="cqInviteCode" style="overflow-wrap:anywhere">${issuedInvite?escapeHtml(issuedInvite):'발급된 코드 없음'}</p><button data-parent-invite="refresh">연결 요청 불러오기</button><div>${pendingChildren.map(c=>`<div class="book"><b>${escapeHtml(c.student_name)}</b> <small>계정 확인번호 ${escapeHtml(c.child_user_id.slice(-8))}</small> · ${c.active?'승인됨':'비활성 · 승인 대기'} ${c.active?`<button data-parent-invite="revoke" data-uid="${escapeHtml(c.child_user_id)}">연결 해제</button>`:`<button data-parent-invite="approve" data-uid="${escapeHtml(c.child_user_id)}">승인·재활성화</button>`}</div>`).join('')}</div><p id="cqInviteStatus" class="status"></p></section>`;
 const inviteStatus=t=>{const n=document.getElementById('cqInviteStatus');if(n)n.textContent=t};
 const inviteCfg=()=>({url:project?.url,anonKey:project?.anonKey,getAccessToken:async()=>{await refreshIfNeeded();return session?.token}});
 const publicationChildrenPanel=()=>`<section class="card"><h2>📤 서버 게시 대상 학생</h2><p class="muted">게시할 학생과 서버에서 검증된 PDF 챕터를 각각 선택하세요. 로컬 챕터와 서버 PDF는 자동으로 동일하다고 간주하지 않습니다.</p><label>서버 PDF 챕터<select id="cqPublishVerifiedPdf"><option value="">검증된 서버 PDF 챕터 선택 (필수)</option>${pdfServerChapters.filter(x=>x.ready).map(x=>`<option value="${escapeHtml(x.uuid)}" ${chapter()?.serverPdfUuid===x.uuid?'selected':''}>${escapeHtml(x.title)} · ${escapeHtml(x.uuid)}</option>`).join('')}</select></label>${pendingChildren.filter(c=>c.active).map(c=>`<label><input type="checkbox" data-publish-child="${escapeHtml(c.child_user_id)}"> ${escapeHtml(c.student_name||'연결된 학생')} <small>계정 확인번호 ${escapeHtml(c.child_user_id.slice(-8))}</small></label>`).join('')||'<p>활성 연결 학생 목록을 먼저 불러오세요.</p>'}</section>`;
 let pdfServerChapters=[],pdfServerStudents=[],pdfServerAssignments=[];
 const pdfParentStatus=message=>{const el=document.getElementById('cqPdfParentStatus');if(el)el.textContent=message};
 const pdfParentPanel=()=>`<section class="card" id="cqPdfParentPanel"><h2>📄 서버 원본 PDF 등록 · 학생 배정</h2><p class="note">현재 챕터의 원본을 서버에 등록하면 게시할 PDF에 연결됩니다. 원본은 비공개 저장소에 보관되며 AI용 텍스트와 별도로 관리됩니다.</p><button data-pdf-parent="refresh" ${session?'':'disabled'}>서버 챕터·학생 목록 새로고침</button><div class="row"><label>챕터 제목 <input id="cqPdfChapterTitle" placeholder="예: Chapter 1" maxlength="200"></label><input type="file" id="cqPdfServerFile" accept="application/pdf,.pdf,text/plain,.txt"><button data-pdf-parent="create" ${session?'':'disabled'}>PDF/TXT 등록·검증</button><button data-pdf-parent="from-local" ${session&&chapter()?.pdfStored?'':'disabled'}>현재 챕터 원본을 서버에 등록</button></div><p class="muted">PDF 최대 50MB · TXT 최대 1MB. TXT는 화면에 표시한 원문을 PDF로 변환해 등록하며 기기의 원본 TXT는 보존합니다.</p>${session&&pdfServerStudents.length===0?'<p class="note">학생 연결 목록을 새로고침해 확인하세요. 이미 연결된 계정은 재초대하지 않아도 됩니다.</p>':''}${pdfServerChapters.map((c,i)=>`<div class="book"><b>${escapeHtml(c.title)}</b> · ${c.ready?'PDF 검증 완료':'검증 대기'} · 배정 ${pdfServerAssignments.filter(a=>a.chapter_uuid===c.uuid).length}명<div class="row">${c.ready?`<button data-pdf-parent="use-existing" data-index="${i}">기존 PDF로 학습 준비</button>`:''}${!c.ready?`<button data-pdf-parent="verify" data-index="${i}" ${session?'':'disabled'}>PDF 검증 다시 확인</button>`:''}</div></div>`).join('')}<p id="cqPdfParentStatus" class="status">서버 연동 전에는 실행되지 않습니다.</p></section>`;
 async function pdfParentCall(action,args){
   if(mode!=='parent'||!parentUnlocked||!session||!project)throw Error('부모 계정으로 로그인해야 합니다.');
   const owner=cloudIdentity();await refreshIfNeeded();
   if(cloudIdentity()!==owner)throw Error('부모 계정이 변경되었습니다.');
   const url=String(project.url||'');
   if(!(globalThis.CQOrigin?.allows(url)??/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url)))throw Error('프로젝트 URL이 올바르지 않습니다.');
   const res=await fetch(url+'/functions/v1/cq-v4-pdf-parent',{method:'POST',headers:{apikey:project.anonKey,Authorization:'Bearer '+session.token,'Content-Type':'application/json'},body:JSON.stringify({action,...args})});
   const data=await res.json().catch(()=>({}));
   if(cloudIdentity()!==owner)throw Error('부모 계정이 변경되었습니다. 이전 결과를 폐기합니다.');
   if(!res.ok)throw Error(data.error||data.message||'서버 오류 '+res.status);
   return data;
 }
 async function refreshPdfParentLists(){
   const [chapters,students,assignments]=await Promise.all([pdfParentCall('list_chapters',{}),pdfParentCall('list_students',{}),pdfParentCall('list_assignments',{})]);
   if(!Array.isArray(chapters.chapters)||!Array.isArray(students.students)||!Array.isArray(assignments.assignments))throw Error('서버 목록 응답이 올바르지 않습니다.');
   pdfServerChapters=chapters.chapters.filter(c=>/^[0-9a-f-]{36}$/i.test(String(c.chapter_uuid||''))).map(c=>({title:String(c.title||''),uuid:String(c.chapter_uuid||''),ready:c.pdf_ready===true}));
   pdfServerStudents=students.students.map(s=>({student_user_id:String(s.student_user_id||'')})).filter(s=>/^[0-9a-f-]{36}$/i.test(s.student_user_id));
   pdfServerAssignments=assignments.assignments.filter(a=>/^[0-9a-f-]{36}$/i.test(a.chapter_uuid||'')&&/^[0-9a-f-]{36}$/i.test(a.student_user_id||''));
   render();pdfParentStatus('서버 목록을 다시 불러왔습니다. 승인된 학생과 PDF 목록을 확인했습니다.');
 }
 let pdfParentBusy=false;
 document.addEventListener('click',async event=>{
   const button=event.target.closest('[data-pdf-parent]');if(!button||pdfParentBusy)return;
   pdfParentBusy=true;button.disabled=true;
   try{
     const action=button.dataset.pdfParent;
     if(action==='refresh'){
       await refreshPdfParentLists();
     }else if(action==='create'||action==='from-local'){
       const localChapter=action==='from-local'?chapter():null,localContext=pdfContext(),owner=cloudIdentity();
       const title=localChapter?((book()?.title||'도서')+' · '+localChapter.title).slice(0,200):document.getElementById('cqPdfChapterTitle')?.value.trim();
       let file=localChapter?await pdfGet(localContext):document.getElementById('cqPdfServerFile')?.files?.[0];
       if(cloudIdentity()!==owner||(localChapter&&(chapter()!==localChapter||pdfContext()!==localContext)))throw Error('계정 또는 챕터가 변경되었습니다.');
       if(file&&(file.name?.toLowerCase().endsWith('.txt')||localChapter?.readerType==='txt')){pdfParentStatus('TXT 원문을 PDF로 변환 중…');file=await CQTextPDF.convert(file);}
       if(cloudIdentity()!==owner)throw Error('부모 계정이 변경되었습니다.');
       if(!title||!file)throw Error('챕터 제목과 PDF 파일을 선택하세요.');
       if(file.type!=='application/pdf'||file.size<5||file.size>50*1024*1024)throw Error('50MB 이하 PDF 파일만 등록할 수 있습니다.');
       const head=new Uint8Array(await file.slice(0,5).arrayBuffer());
       if(String.fromCharCode(...head)!=='%PDF-')throw Error('PDF 파일 형식이 올바르지 않습니다.');
       pdfParentStatus('서버에 챕터 생성 중…');
       const created=await pdfParentCall('create_chapter',{title});
       if(cloudIdentity()!==owner)throw Error('부모 계정이 변경되었습니다.');
       if(!created.chapter_uuid)throw Error('챕터 ID를 받지 못했습니다.');
       pdfServerChapters.push({title,uuid:created.chapter_uuid,ready:false});
       const signed=await pdfParentCall('upload_url',{chapter_uuid:created.chapter_uuid});
       if(!signed.path||!signed.token||signed.bucket!=='cq-v4-originals')throw Error('업로드 권한 응답이 올바르지 않습니다.');
       pdfParentStatus('PDF 업로드 중…');
       const uploadUrl=project.url+'/storage/v1/object/upload/sign/'+encodeURIComponent(signed.bucket)+'/'+signed.path.split('/').map(encodeURIComponent).join('/')+'?token='+encodeURIComponent(signed.token);
       const uploaded=await fetch(uploadUrl,{method:'PUT',headers:{'Content-Type':'application/pdf'},body:file});
       if(!uploaded.ok)throw Error('PDF 업로드 실패: '+uploaded.status);
       pdfParentStatus('서버에서 PDF 파일 확인 중…');
       const verified=await pdfParentCall('finalize_upload',{chapter_uuid:created.chapter_uuid});
       if(!verified.pdf_ready)throw Error('서버 PDF 검증이 완료되지 않았습니다.');
       if(cloudIdentity()!==owner)throw Error('부모 계정이 변경되었습니다.');
       if(localChapter&&chapter()===localChapter&&pdfContext()===localContext){localChapter.serverPdfUuid=created.chapter_uuid;localChapter.serverPdfOrigin=project.url;localChapter.serverPdfOwner=session.uid;save();}
       const uploadedChapter=pdfServerChapters.find(c=>c.uuid===created.chapter_uuid);if(uploadedChapter)uploadedChapter.ready=true;
       render();pdfParentStatus('PDF 업로드 및 서버 검증 완료. 서버 목록을 새로고침해 배정하세요.');
     }else if(action==='use-existing'){
       const serverChapter=pdfServerChapters[Number(button.dataset.index)],owner=cloudIdentity(),targetBook=book();
       if(!serverChapter?.ready)throw Error('검증된 서버 원본을 선택하세요.');
       const title=targetBook?.title||prompt('이 원본이 포함된 책 제목을 입력하세요.','기존 서버 원본');if(!title?.trim())return;
       pdfParentStatus('소유한 서버 원본을 읽는 중…');
       const transport=CQServerPDF.createPdfTransport({url:project.url,anonKey:project.anonKey,role:'parent',getAccessToken:async()=>{await refreshIfNeeded();if(cloudIdentity()!==owner)throw Error('부모 계정이 변경되었습니다.');return session.token;}});
       const bytes=await transport.getPdf(serverChapter.uuid);
       if(cloudIdentity()!==owner||book()!==targetBook)throw Error('계정 또는 선택한 도서가 변경되었습니다.');
       let source='',doc=null;
       try{if(window.pdfjsLib){doc=await pdfjsLib.getDocument({data:new Uint8Array(bytes.slice(0)),isEvalSupported:false}).promise;for(let n=1;n<=doc.numPages;n++){const text=await(await doc.getPage(n)).getTextContent();source+=text.items.map(x=>x.str).join(' ')+'\n';if(source.length>500000)throw Error('교재가 너무 깁니다. 챕터별 원문을 준비하세요.');}}}finally{if(doc)await doc.destroy();}
       if(cloudIdentity()!==owner||book()!==targetBook)throw Error('계정 또는 선택한 도서가 변경되었습니다.');
       const existing=state.books.flatMap(b=>(b.chapters||[]).map(c=>({book:b,chapter:c}))).find(x=>x.chapter.serverOriginalCopy===true&&x.chapter.serverPdfUuid===serverChapter.uuid&&x.chapter.serverPdfOrigin===project.url&&x.chapter.serverPdfOwner===session.uid);
       const preparedBook=existing?.book||targetBook||{id:uid(),title:title.trim(),students:[state.who],chapters:[]};
       const prepared=existing?.chapter||{id:uid(),title:serverChapter.title,source,questions:[],vocabulary:[],writingPrompt:'',speakingPrompt:'',pdfStored:true,pdfName:serverChapter.title+'.pdf',readerType:'pdf',serverPdfUuid:serverChapter.uuid,serverPdfOrigin:project.url,serverPdfOwner:session.uid,serverOriginalCopy:true};
       const key=pdfKey(preparedBook.id,prepared.id);await pdfPut(key,new File([bytes],prepared.pdfName,{type:'application/pdf'}));const saved=await pdfGet(key);
       if(!saved||saved.size!==bytes.byteLength)throw Error('원본을 이 기기에 보관하지 못했습니다.');
       if(cloudIdentity()!==owner||book()!==targetBook)throw Error('계정 또는 선택한 도서가 변경되었습니다.');
       if(!existing){if(!targetBook)state.books.push(preparedBook);preparedBook.chapters.push(prepared);}else{prepared.pdfStored=true;if(!prepared.source?.trim())prepared.source=source;}selectedBook=preparedBook.id;selectedChapter=prepared.id;view='manage';draft=null;save();render();
       pdfParentStatus('기존 서버 원본을 보존한 채 이 기기에 준비했습니다. 문제 검토·승인·배정은 별도입니다.');
       if(source.trim().length<250)setStatus('원문 PDF는 준비됐습니다. 스캔 PDF이거나 텍스트가 부족하면 AI용 텍스트를 별도로 입력하세요.');
     }else if(action==='verify'){
       const i=Number(button.dataset.index),chapter=pdfServerChapters[i];
       if(!chapter||chapter.ready)throw Error('검증 대기 중인 챕터를 선택하세요.');
       pdfParentStatus('서버에서 기존 PDF 파일을 다시 확인 중…');
       const verified=await pdfParentCall('finalize_upload',{chapter_uuid:chapter.uuid});
       if(!verified.pdf_ready)throw Error('PDF 검증이 완료되지 않았습니다.');
       await refreshPdfParentLists();
       pdfParentStatus('PDF 검증 완료. 학생 배정이 가능합니다.');
     }else if(action==='assign'||action==='unassign'){
       const i=Number(button.dataset.index),chapter=pdfServerChapters[i];
       const student=document.querySelector(`[data-pdf-student="${i}"]`)?.value;
       if(!chapter||!student)throw Error('챕터와 승인된 학생을 선택하세요.');
       await pdfParentCall(action,{chapter_uuid:chapter.uuid,student_user_id:student});
       try{await refreshPdfParentLists();pdfParentStatus(action==='assign'?'학생 배정 완료. 서버 목록을 갱신했습니다.':'학생 배정 취소 완료. 서버 목록을 갱신했습니다.')}catch(refreshError){pdfParentStatus('서버 배정 요청은 처리됐지만 목록 갱신에 실패했습니다: '+refreshError.message)}
     }
   }catch(error){
     const message=error instanceof Error?error.message:String(error);
     // The server may already have created the chapter; recover its ID through the server list.
     if(['create','from-local'].includes(button.dataset.pdfParent)){
       try{await refreshPdfParentLists()}catch(_ignored){}
     }
     pdfParentStatus('오류: '+message+' · 챕터가 생성된 경우 목록에서 PDF 검증을 다시 확인할 수 있습니다.');
   }finally{pdfParentBusy=false;button.disabled=false}
 });
 function localLessonContext(uuid){const value=state.books.flatMap(b=>b.chapters||[]).map(c=>c.serverPublishedContext).find(x=>x?.chapter_uuid===uuid&&x.owner===session?.uid&&x.project===project?.url);return value||null;}
 function rememberPublication(c,uuid,context){if(!context)return;c.serverPdfUuid=uuid;c.serverPublishedContext={...structuredClone(context),chapter_uuid:uuid,owner:session.uid,project:project.url};save();}

 async function enrichSubmissions(rows){
  const owner=cloudIdentity(),contexts=new Map();
  for(const uuid of new Set(rows.map(r=>r.chapter_uuid))){
   try{const result=await parentRpc('cq_v4_parent_lesson',{p_chapter_uuid:uuid});contexts.set(uuid,Array.isArray(result)?result[0]:null);}
   catch(error){if(cloudIdentity()!==owner)throw error;contexts.set(uuid,localLessonContext(uuid));}
  }
  if(cloudIdentity()!==owner)throw Error('부모 계정이 변경되었습니다.');
  return rows.map(row=>({...row,lessonContext:contexts.get(row.chapter_uuid)||localLessonContext(row.chapter_uuid)}));
 }
 function resultDetails(row){
  const context=row.lessonContext,questions=Array.isArray(context?.questions)?context.questions:[],answers=Array.isArray(row.answers?.answers)?row.answers.answers:[];
  const display=(q,value)=>value===undefined||value===null||value===''?'미응답':q.kind==='mc'&&Array.isArray(q.options)?q.options[Number(value)]??'미응답':String(value??'미응답');
  const questionsHtml=questions.map((q,i)=>q?`<li><b>${escapeHtml(q.text||'문제')}</b><p>학생 답변: ${escapeHtml(display(q,answers[i]))}</p><details><summary>기준 답안</summary><p>${escapeHtml(display(q,context.answer_key?.[i]))}</p></details></li>`:'').join('');
  return `<div class="submitted-lesson">${questionsHtml?'<ol>'+questionsHtml+'</ol>':'<p class="muted">문제·기준 답안을 불러오지 못했습니다. 부모 기기의 학습 자료를 확인하세요.</p>'}<h4>영어 독후감</h4><p style="white-space:pre-wrap">${escapeHtml(row.answers?.essay||'')}</p><h4>말하기 대본</h4><p style="white-space:pre-wrap">${escapeHtml(row.answers?.speaking||'')}</p><p>단어 복습 체크: ${Array.isArray(row.answers?.wordsReviewed)?row.answers.wordsReviewed.length:0}개</p></div>`;
 }
 const feedbackPanel=()=>`<section class="card" id="cqParentFeedback"><h2>학생 제출·피드백 관리 (서버)</h2><p class="muted">로그인한 부모 계정의 제출만 조회합니다. 기존 로컬 제출 기록과는 별개입니다.</p><button data-parent-feedback="list" ${session?'':'disabled'}>제출 기록 불러오기</button><div>${submissions.map((r,i)=>`<div class="book"><h3>${escapeHtml(r.student_name||r.child_user_id)} · ${escapeHtml(r.chapter_title||r.chapter_uuid)}</h3><p>제출: ${escapeHtml(r.submitted_at||'')}</p>${resultDetails(r)}<details><summary>제출 원본 보기</summary><pre style="white-space:pre-wrap;overflow-wrap:anywhere">${escapeHtml(JSON.stringify(r.answers??{},null,2))}</pre></details><label>부모 피드백<textarea data-parent-feedback-text="${i}" rows="3">${escapeHtml(r.feedback||'')}</textarea></label><label><input type="checkbox" data-parent-feedback-release="${i}" ${r.feedback_released?'checked':''}> 학생에게 공개</label><button data-parent-feedback="save" data-index="${i}">피드백 저장</button><button data-parent-feedback="audio" data-index="${i}">녹음 재생</button><div data-audio-player="${i}"></div></div>`).join('')}</div><p id="cqParentFeedbackStatus" class="status"></p></section>`;
 async function parentRpc(name,args={}){
   if(mode!=='parent'||!parentUnlocked||!session||!project)throw Error('부모 관리자 로그인이 필요합니다.');
   const owner=cloudIdentity();await refreshIfNeeded();
   if(cloudIdentity()!==owner)throw Error('부모 계정이 변경되었습니다.');
   const response=await fetch(project.url+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:project.anonKey,Authorization:'Bearer '+session.token,'Content-Type':'application/json'},body:JSON.stringify(args)});
   if(!response.ok){const body=await response.json().catch(()=>({}));throw Error(body.message||'서버 요청 실패: '+response.status)}
   const data=await response.json();if(cloudIdentity()!==owner)throw Error('부모 계정이 변경되었습니다. 이전 결과를 폐기합니다.');return data;
 }
 // Stage95: authenticated parent UI -> immutable approval snapshot -> approved publication.
 // The stage94 candidate RPCs must be separately reviewed and installed in a TEST project.
 const publishStatus=t=>{const n=document.getElementById('cqPublicationStatus');if(n)n.textContent=t};
 let publicationBusy=false;
 function publicationPayload(c){
   if(!c||!Array.isArray(c.questions)||!c.questions.length)throw Error('승인된 문제가 없습니다.');
   const questions=[],answerKey=[];
   for(const q of c.questions){
     const kind=String(q.kind||''),text=String(q.text||'').trim();
     if(!['mc','inference','critical','short','comprehension'].includes(kind)||!text)throw Error('지원되지 않는 문제 형식입니다.');
     if(kind==='mc'){
       if(!Array.isArray(q.options)||q.options.length<2||q.options.length>6||q.options.some(x=>typeof x!=='string'||!x.trim())||!Number.isInteger(q.correct)||q.correct<0||q.correct>=q.options.length)throw Error('객관식 정답 또는 선택지가 올바르지 않습니다.');
       questions.push({kind,text,options:q.options.map(x=>x.trim())});answerKey.push(q.correct);
     }else{
       const sample=String(q.sample||q.answer||'').trim();
       if(!sample)throw Error('서술형 모범 답안이 누락되었습니다.');
       questions.push({kind,text});answerKey.push(sample);
     }
   }
   return {questions,answerKey};
 }
 document.addEventListener('change',async e=>{
   if(e.target?.id==='cqVoiceManifestImport'){const f=e.target.files?.[0];e.target.value='';voiceImportManifest=null;const expectedUid=session?.uid,expectedUuid=el('cqChildWork')?.dataset.uuid,expectedGeneration=childGeneration;try{if(!f)throw Error('검증 정보 파일을 선택하지 않았습니다.');if(f.size>4096)throw Error('검증 정보 파일 크기가 올바르지 않습니다.');const parsed=JSON.parse(await f.text());if(!session||session.uid!==expectedUid||childGeneration!==expectedGeneration||el('cqChildWork')?.dataset.uuid!==expectedUuid)throw Error('파일을 읽는 동안 학생 또는 챕터가 변경되었습니다.');if(!parsed||parsed.format!=='chapterquest-voice-backup'||parsed.version!==1||parsed.uid!==expectedUid||parsed.chapterUuid!==expectedUuid)throw Error('현재 학생·챕터의 검증 정보가 아닙니다.');voiceImportManifest=parsed;voiceNotice('검증 정보 선택 완료. 이어서 녹음 파일을 선택하세요.');el('cqVoiceImport')?.click();}catch(err){voiceImportManifest=null;voiceNotice('검증 정보 오류: '+err.message)}return;}
   if(e.target?.id!=='cqVoiceImport')return;
   const file=e.target.files?.[0];e.target.value='';
   if(!file){voiceImportManifest=null;voiceNotice('녹음 파일을 선택하지 않았습니다. 복원하려면 검증 정보 파일부터 다시 선택하세요.');return;}
   try{await restoreVoiceBackup(file)}catch(err){voiceNotice('복구 실패: '+err.message)}finally{voiceImportManifest=null;}
 });
 document.addEventListener('click',async e=>{
   const button=e.target.closest('[data-parent-publish]');if(!button)return;
   if(publicationBusy)return;
   if(mode!=='parent'||!parentUnlocked||!session||!project){publishStatus('부모 Supabase 로그인 후 게시할 수 있습니다.');return;}
   const currentBook=selectedBook,currentChapter=selectedChapter,c=chapter(),owner=cloudIdentity();
   if(!c||c.id!==button.dataset.c){publishStatus('현재 챕터를 다시 선택하세요.');return;}
   publicationBusy=true;button.disabled=true;
   let pendingApprovalId=null,pendingTargetChildren=[],publicationSnapshot=null,publicationPdf=null;
   try{
     const eligible=await cqPublicationEligibility(c);
     if(!eligible.ok)throw Error(eligible.reason);
     const linked=pendingChildren.filter(x=>x.active===true&&typeof x.child_user_id==='string').map(x=>x.child_user_id);
     if(!linked.length)throw Error('활성 학생 연결이 없습니다. 위의 연결 요청 불러오기를 먼저 실행하세요.');
     const selected=linked.filter(uid=>document.querySelector('[data-publish-child="'+uid+'"]')?.checked);
     if(!selected.length)throw Error('게시할 학생을 한 명 이상 선택하세요.');
     // The publication RPC requires an explicit, verified server PDF binding.
     // Never infer the server UUID from the local book/chapter identifier.
     const serverPdfUuid=document.getElementById('cqPublishVerifiedPdf')?.value||'';
     if(!/^[0-9a-f-]{36}$/i.test(serverPdfUuid)||!pdfServerChapters.some(x=>x.uuid===serverPdfUuid&&x.ready))
       throw Error('검증된 서버 PDF 챕터를 선택하고 서버 PDF 목록을 새로고침하세요.');
     pendingTargetChildren=[...selected];
     const {questions,answerKey}=publicationPayload(c);publicationSnapshot={questions,answer_key:answerKey,vocabulary:structuredClone(c.vocabulary||[])};publicationPdf=serverPdfUuid;
     if(cloudIdentity()!==owner||selectedBook!==currentBook||selectedChapter!==currentChapter||chapter()!==c)throw Error('계정 또는 챕터가 변경되었습니다.');
     if(!await isApprovalCurrent(c))throw Error('게시 중 학습 자료가 변경되었습니다.');
     // Stage98: stable per-account/per-content request key, persisted before network I/O.
     const requestKey=CQPublicationKey.resolve({storage:localStorage,origin:project.url,uid:session.uid,bookId:currentBook,chapterId:currentChapter,pdfUuid:serverPdfUuid,hash:c.approvalReceipt.sha256});
     if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestKey))throw Error('서버 승인 요청 키가 손상되었습니다. 임의로 재발급하지 않습니다.');
     const approvalId=await parentRpc('cq_v4_register_approval_once',{
       p_request_key:requestKey,p_book_id:currentBook,p_chapter_id:currentChapter,p_title:c.title,p_source:c.source,
       p_questions:questions,p_answer_key:answerKey,
       p_vocabulary:(c.vocabulary||[]).map(v=>({word:String(v.word||v.english||''),meaning:String(v.meaning||v.korean||''),example:String(v.example||'')})),
       p_writing_prompt:String(c.writingPrompt||''),p_speaking_prompt:String(c.speakingPrompt||'')
     });
     if(cloudIdentity()!==owner||selectedBook!==currentBook||selectedChapter!==currentChapter||chapter()!==c||!await isApprovalCurrent(c))throw Error('승인 기록 등록 후 계정 또는 자료가 변경되어 게시를 중단했습니다.');
     if(typeof approvalId!=='string'||!/^[0-9a-f-]{36}$/i.test(approvalId))throw Error('서버 승인 기록 식별자가 올바르지 않습니다.');
     pendingApprovalId=approvalId;
     await parentRpc('cq_v4_bind_verified_pdf',{p_approval_id:approvalId,p_chapter_uuid:serverPdfUuid});
     if(cloudIdentity()!==owner||selectedBook!==currentBook||selectedChapter!==currentChapter||chapter()!==c||!await isApprovalCurrent(c))
       throw Error('PDF 연결 후 계정 또는 학습 자료가 변경되어 게시를 중단했습니다.');
     const chapterId=await parentRpc('cq_v4_publish_approved',{p_approval_id:approvalId,p_children:selected});
     if(cloudIdentity()!==owner)return;
     rememberPublication(c,serverPdfUuid,publicationSnapshot);publishStatus('✓ 서버 게시 요청 성공 · 학생 '+selected.length+'명 · 챕터 '+String(chapterId)+'. 실제 학생 조회는 별도 확인이 필요합니다.');
   }catch(error){
     if(cloudIdentity()!==owner)return;
     if(pendingApprovalId&&pendingTargetChildren.length){
       try{
         // Read-only server check: a lost publish response must not cause a duplicate write.
         const result=await parentRpc('cq_v4_publication_status',{
           p_approval_id:pendingApprovalId,p_children:pendingTargetChildren
         });
         if(cloudIdentity()!==owner||selectedBook!==currentBook||selectedChapter!==currentChapter||chapter()!==c)return;
         if(result?.content_matches===true&&result?.all_assigned===true){rememberPublication(c,publicationPdf,publicationSnapshot);
           publishStatus('✓ 서버 게시 확인 완료 · 응답 유실 후 복구 · 학생 '+pendingTargetChildren.length+'명 · 중복 게시 없음.');
         }else if(result?.content_matches===true&&Array.isArray(result?.missing_children)){
           publishStatus('⚠ 게시 상태 확인 · 배정되지 않은 학생 '+result.missing_children.length+'명 · 자동 재게시하지 않았습니다. 다시 확인하세요.');
         }else{
           publishStatus('⚠ 게시 결과 미확인: '+error.message+' · 서버 자료 불일치 또는 미게시 · 자동 재게시하지 않았습니다.');
         }
       }catch(checkError){
         if(cloudIdentity()===owner)publishStatus('⚠ 게시 결과 확인 실패: '+checkError.message+' · 중복 게시를 피하기 위해 자동 재시도하지 않습니다.');
       }
     }else publishStatus('⚠ 게시 실패: '+error.message+' · 로컬 학습 자료는 유지됩니다.');
   }
   finally{publicationBusy=false;if(button.isConnected)button.disabled=false;}
 });
 const originalRender=render;
 render=function(){originalRender();if(mode==='parent'){const app=document.getElementById('app');if(app)app.insertAdjacentHTML('afterbegin',panel()+invitationPanel()+pdfParentPanel()+publicationChildrenPanel()+feedbackPanel())}};
 document.addEventListener('click',async e=>{
  const b=e.target.closest('[data-parent-invite]');if(!b)return;
  if(mode!=='parent'||!parentUnlocked||!session||!project){inviteStatus('부모 Supabase 로그인이 필요합니다.');return;}
  const inviteGeneration=sessionGeneration;
  const inviteUid=session.uid;
  const stillSameParent=()=>sessionGeneration===inviteGeneration && session?.uid===inviteUid && mode==='parent' && parentUnlocked;
  b.disabled=true;
  try{
   if(b.dataset.parentInvite==='issue'){
     issuedInvite=await CQInvitationAPI.issue(inviteCfg());
     if(!stillSameParent()){issuedInvite='';return;}
     render();inviteStatus('15분 유효한 초대코드가 발급됐습니다. 학생에게만 전달하세요.');
   }else if(b.dataset.parentInvite==='refresh'){
     await refreshIfNeeded();
     const result=await parentRpc('cq_v4_list_child_access',{});
     if(!stillSameParent())return;
     if(!Array.isArray(result))throw Error('연결 요청 응답 형식 오류');
     pendingChildren=result;render();inviteStatus('연결 요청 '+pendingChildren.length+'건');
   }else if(b.dataset.parentInvite==='revoke'){
     if(!pendingChildren.some(c=>c.child_user_id===b.dataset.uid&&c.active))throw Error('활성 연결 학생이 아닙니다.');
     if(!confirm('이 학생의 서버 학습 접근을 차단할까요? 기존 학습 기록은 보존됩니다.'))return;
     const ok=await CQInvitationAPI.revoke(inviteCfg(),b.dataset.uid);
     if(!stillSameParent())return;
     if(!ok)throw Error('연결 해제되지 않았습니다. 목록을 다시 불러오세요.');
     pendingChildren=pendingChildren.filter(c=>c.child_user_id!==b.dataset.uid);
     render();inviteStatus('학생 연결이 해제되었습니다. 기존 학습 기록은 유지됩니다. 다시 연결하려면 새 초대코드가 필요합니다.');
   }else if(b.dataset.parentInvite==='approve'){
     if(!pendingChildren.some(c=>c.child_user_id===b.dataset.uid&&!c.active))throw Error('승인 대기 중인 학생이 아닙니다.');
     if(!confirm('선택한 학생 계정을 승인할까요?'))return;
     const ok=await CQInvitationAPI.approve(inviteCfg(),b.dataset.uid);
     if(!stillSameParent())return;
     if(!ok)throw Error('승인되지 않았습니다. 요청을 새로 불러오세요.');
     await refreshIfNeeded();
     const refreshedChildren=await parentRpc('cq_v4_list_child_access',{});
     if(!stillSameParent())return;
     if(!Array.isArray(refreshedChildren))throw Error('연결 요청 응답 형식 오류');
     pendingChildren=refreshedChildren;
     render();inviteStatus('학생 계정 승인 완료');
   }
  }catch(err){if(stillSameParent())inviteStatus('오류: '+err.message)}finally{if(b.isConnected)b.disabled=false}
 });
 document.addEventListener('click',async e=>{
   const button=e.target.closest('[data-parent-feedback]');if(!button)return;
   if(mode!=='parent'||!parentUnlocked||!session){parentStatus('부모 인증이 필요합니다.');return}
   if(feedbackBusy)return;
   feedbackBusy=true;button.disabled=true;
   try{
     if(button.dataset.parentFeedback==='list'){
       const rows=await parentRpc('cq_v4_parent_submissions');
       submissions=await enrichSubmissions(Array.isArray(rows)?rows:[]);render();parentStatus('제출 '+submissions.length+'건을 불러왔습니다.');
     }else if(button.dataset.parentFeedback==='audio'){
       const i=Number(button.dataset.index),r=submissions[i];if(!r)throw Error('제출 기록을 다시 불러오세요.');
       const uuid=String(r.chapter_uuid||''),uid=String(r.child_user_id||'');
       if(!/^[0-9a-f-]{36}$/i.test(uuid)||!/^[0-9a-f-]{36}$/i.test(uid))throw Error('녹음 경로 정보가 올바르지 않습니다.');
       const signed=await pdfParentCall('audio_download_url',{chapter_uuid:uuid,student_user_id:uid});
       if(!signed?.signed_url||!signed?.expires_at)throw Error('녹음 파일이 없거나 접근 권한이 없습니다.');
       const link=new URL(signed.signed_url,project.url),expires=Date.parse(signed.expires_at);
       if(link.origin!==new URL(project.url).origin||!['webm','mp4','ogg'].some(ext=>link.pathname==='/storage/v1/object/sign/cq-v4-speaking/'+uid+'/'+uuid+'.'+ext)||!link.searchParams.has('token')||!Number.isFinite(expires)||expires<=Date.now()+5000||expires>Date.now()+10*60*1000)throw Error('녹음 재생 주소가 올바르지 않습니다.');
       const player=document.querySelector(`[data-audio-player="${i}"]`);
       if(player){player.replaceChildren();const audio=document.createElement('audio');audio.controls=true;audio.src=link.href;player.appendChild(audio);}
       parentStatus('녹음 재생 링크를 생성했습니다. 2분 후 만료됩니다.');
     }else if(button.dataset.parentFeedback==='save'){
       const i=Number(button.dataset.index),r=submissions[i];if(!r)throw Error('제출 기록을 다시 불러오세요.');
       const text=document.querySelector(`[data-parent-feedback-text="${i}"]`)?.value||'';
       const released=!!document.querySelector(`[data-parent-feedback-release="${i}"]`)?.checked;
       if(released&&!text.trim())throw Error('피드백을 작성한 뒤 공개하세요.');
       await parentRpc('cq_v4_release_feedback',{p_child_user_id:r.child_user_id,p_chapter_uuid:r.chapter_uuid,p_feedback:text,p_release:released});
       r.feedback=text;r.feedback_released=released;
       const rows=await parentRpc('cq_v4_parent_submissions');
       submissions=await enrichSubmissions(Array.isArray(rows)?rows:[]);render();parentStatus('서버에서 피드백 저장 상태를 다시 확인했습니다.');
     }
   }catch(error){parentStatus('오류: '+error.message)}finally{feedbackBusy=false;button.disabled=false}
 });
 document.addEventListener('click',async e=>{
  const b=e.target.closest('[data-cloud]');if(!b||busy)return;
  if(mode!=='parent'||!parentUnlocked){status('부모 관리자 잠금 해제 후 이용하세요.');return;}const action=b.dataset.cloud;busy=true;b.disabled=true;
  try{
   if(action==='project'){
    const url=document.getElementById('cloudUrl').value.trim().replace(/\/$/,'');
    const anonKey=document.getElementById('cloudKey').value.trim();
    if(!(globalThis.CQOrigin?.allows(url)??/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url))||!anonKey)throw Error('Supabase URL과 공개 키를 확인하세요.');
    sessionGeneration++;project={url,anonKey};auto=false;dirty=false;clearTimeout(syncTimer);baseline=undefined;aligned=false;localStorage.setItem('cq_v4_cloud_project',JSON.stringify(project));session=null;issuedInvite="";pendingChildren=[];submissions=[];pdfServerChapters=[];pdfServerStudents=[];pdfServerAssignments=[];CQCloud.reset();render();status('프로젝트 설정 저장 완료');
   }else if(action==='login'){
    if(!project)throw Error('먼저 프로젝트 설정을 저장하세요.');
    const email=document.getElementById('cloudEmail').value.trim(),password=document.getElementById('cloudPassword').value;
    if(!email||!password)throw Error('이메일과 비밀번호를 입력하세요.');
    auto=false;dirty=false;clearTimeout(syncTimer);sessionGeneration++;session=null;issuedInvite="";pendingChildren=[];submissions=[];pdfServerChapters=[];pdfServerStudents=[];pdfServerAssignments=[];CQCloud.reset();
    const loginGeneration=sessionGeneration;const data=await auth('token?grant_type=password',{email,password});
    if(loginGeneration!==sessionGeneration)throw Error('프로젝트 설정이 변경되어 로그인을 취소했습니다.');
    if(!data.access_token||!data.user?.id)throw Error('로그인 정보를 확인하지 못했습니다.');
    const roleResponse=await fetch(project.url+'/rest/v1/rpc/cq_is_admin',{method:'POST',headers:{apikey:project.anonKey,Authorization:'Bearer '+data.access_token,'Content-Type':'application/json'},body:'{}'});
    const isParent=roleResponse.ok?await roleResponse.json():false;
    if(loginGeneration!==sessionGeneration)throw Error('로그인 상태가 변경되었습니다.');
    if(isParent!==true)throw Error('부모 관리자로 등록된 계정이 아닙니다. 학생 화면에서 학생 계정으로 로그인하세요.');
    sessionGeneration++;session={token:data.access_token,uid:data.user.id,refreshToken:data.refresh_token,expiresAt:Date.now()+(data.expires_in||3600)*1000};baseline=undefined;auto=false;aligned=false;CQCloud.configure({url:project.url,anonKey:project.anonKey,token:session.token,uid:session.uid});CQCloud.setBeforeRequest(refreshIfNeeded);
    const loginSession=session;const existing=await parentStore().loadParentSnapshot();if(session!==loginSession)throw Error('로그인 상태가 변경되었습니다.');baseline=existing?.updated_at??null;render();status(existing?'로그인 성공 · 클라우드 기록이 있습니다. 복원 또는 수동 저장 후 자동 동기화를 켜세요.':'로그인 성공 · 클라우드 기록이 없습니다. 자동 동기화를 켤 수 있습니다.');
   }else if(action==='logout'){sessionGeneration++;session=null;issuedInvite="";pendingChildren=[];submissions=[];pdfServerChapters=[];pdfServerStudents=[];pdfServerAssignments=[];auto=false;dirty=false;baseline=undefined;aligned=false;clearTimeout(syncTimer);CQCloud.reset();render();status('로그아웃 완료');}
   else if(action==='push'){
    if(!session)throw Error('로그인이 필요합니다.');
    if(!confirm('현재 이 기기의 기록을 클라우드에 저장할까요? 다른 기기의 변경 사항이 감지되면 덮어쓰지 않습니다.'))return;
    if(syncing)throw Error('자동 저장이 끝난 뒤 다시 시도하세요.');
    auto=false;clearTimeout(syncTimer);const owner=cloudIdentity();const result=await parentStore().saveParentSnapshot(structuredClone(state),baseline);if(cloudIdentity()!==owner)throw Error('로그인 계정이 변경되었습니다. 저장 결과를 적용하지 않습니다.');if(result.conflict){auto=false;throw Error('다른 기기에서 기록이 변경되었습니다. 로컬 기록은 보존됩니다.')}baseline=result.snapshot.updated_at;aligned=true;status('클라우드 저장 완료');
   }else if(action==='pull'){
    if(!session)throw Error('로그인이 필요합니다.');
    const owner=cloudIdentity();const snapshot=await parentStore().loadParentSnapshot();if(cloudIdentity()!==owner)throw Error('로그인 계정이 변경되었습니다. 복원을 취소합니다.');if(!snapshot?.payload?.books)throw Error('클라우드에 저장된 기록이 없습니다.');
    if(!confirm('클라우드 기록으로 이 기기의 데이터를 교체할까요? 기존 데이터는 먼저 JSON 백업됩니다.'))return;
    if(cloudIdentity()!==owner)throw Error('로그인 계정이 변경되었습니다. 복원을 취소합니다.');
    download('chapter-quest-before-cloud-restore-'+new Date().toISOString().slice(0,10)+'.json',JSON.stringify({format:'chapter-quest-v4',state,...(recoveryRaw?{recoveryRaw}:{})},null,2));
    const restored=structuredClone(snapshot.payload);
    if(!Array.isArray(restored.books)||!Array.isArray(restored.students)||!restored.records||typeof restored.records!=='object'||Array.isArray(restored.records)||!restored.weekly||typeof restored.weekly!=='object')throw Error('클라우드 기록의 구조가 올바르지 않습니다. 기존 기록을 유지합니다.');
    auto=false;dirty=false;clearTimeout(syncTimer);restored.code='';
    if(cloudIdentity()!==owner)throw Error('로그인 계정이 변경되었습니다. 복원을 취소합니다.');
    state=restored;baseline=snapshot.updated_at;aligned=true;save();selectedBook='';selectedChapter='';view='home';render();status('클라우드 복원 완료 · 기존 기록 백업 파일을 보관하세요.');
   }
  }catch(err){status('오류: '+err.message)}finally{busy=false;b.disabled=false}
 });

 // Capture account identity before async writes; never apply a late response to a new login.
 const cloudIdentity=()=>session&&project?project.url+'|'+session.uid+'|'+sessionGeneration:null;
 window.CQParentAI=Object.freeze({identity:cloudIdentity,authorization:async()=>{
   if(mode!=='parent'||!parentUnlocked||!session||!project)throw Error('문제 생성 전에 부모 Supabase 계정으로 로그인하세요.');
   const owner=cloudIdentity();await refreshIfNeeded();
   if(cloudIdentity()!==owner||!session?.token)throw Error('로그인 상태가 변경되었습니다. 다시 시도하세요.');
   return {Authorization:'Bearer '+session.token};
 }});
 const originalSave=save;
 async function flushSync(){
   if(syncing||!auto||!session||baseline===undefined||!dirty)return;
   syncing=true;
   const owner=cloudIdentity();
   try{
     while(dirty&&auto&&session&&cloudIdentity()===owner){
       dirty=false;
       const sendingRevision=revision;
       const snapshot=structuredClone(state);
       const result=await parentStore().saveParentSnapshot(snapshot,baseline);
       if(cloudIdentity()!==owner){dirty=true;return;}
       if(result.conflict){
         auto=false;dirty=true;render();
         status('⚠ 다른 기기 변경 감지: 동기화 중지. 이 기기의 기록은 유지됩니다.');
         return;
       }
       baseline=result.snapshot.updated_at;
       if(revision!==sendingRevision)dirty=true;
     }
     if(auto&&cloudIdentity()===owner)status('✓ 클라우드 자동 저장 완료');
   }catch(e){
     if(cloudIdentity()!==owner)return;
     auto=false;dirty=true;render();
     status('⚠ 동기화 중지: '+e.message+' · 이 기기의 기록은 유지됩니다.');
   }finally{syncing=false}
 }
 function scheduleSync(){
   if(!auto||!session||baseline===undefined)return;
   dirty=true;revision++;
   clearTimeout(syncTimer);
   syncTimer=setTimeout(flushSync,1400);
 }
 save=function(){const saved=originalSave();if(saved)scheduleSync();return saved;};
 document.addEventListener('change',e=>{
   if(e.target.id!=='cloudAuto')return;
   if(e.target.checked){
     if(!session||baseline===undefined){e.target.checked=false;status('먼저 로그인하세요.');return}
     if(baseline!==null&&!aligned){e.target.checked=false;status('클라우드 기록을 먼저 복원하거나 수동 저장하세요.');return}
     auto=true;scheduleSync();status('자동 동기화 활성화');
   }else{auto=false;clearTimeout(syncTimer);status('자동 동기화 해제')}
 });
 render();
})();
