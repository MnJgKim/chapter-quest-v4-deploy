/* Optional child account connection: isolated from parent credentials and local student selector. */
(()=>{
 let session=null, childApi=null, chapters=[],busy=false, voiceRecorder=null, voiceStream=null, voiceChunks=[], voiceBlob=null, voiceChapter=null, uploadedAudio=new Set(), childGeneration=0, activeChildUpload=null, activeChildSubmit=null;
 let serverPdfController=null,serverPdfDocument=null,serverPdfObjectUrl=null;
 const sameProject=(a,b)=>!!a&&!!b&&a.url===b.url&&a.anonKey===b.anonKey;
 function studentProject(){
  const current=window.CQProject.read();
  if(session?.project&&!sameProject(session.project,current))throw Error('프로젝트 설정이 변경되었습니다. 기존 계정·답안은 유지하며 서버 요청을 중단합니다. 원래 프로젝트 설정을 확인하세요.');
  return session?.project||current;
 }

 function clearServerPdf(){
   if(serverPdfController){serverPdfController.abort();serverPdfController=null;}
   if(serverPdfObjectUrl){URL.revokeObjectURL(serverPdfObjectUrl);serverPdfObjectUrl=null;}
   const previous=serverPdfDocument;serverPdfDocument=null;
   if(previous)previous.destroy().catch(()=>{});
 }
 async function loadServerPdf(chapterUuid,uid,generation){
   clearServerPdf();
   const target=document.getElementById('cqServerPdfViewer');if(!target)return;
   const controller=new AbortController();serverPdfController=controller;
   const current=()=>!controller.signal.aborted&&session?.uid===uid&&childGeneration===generation&&document.getElementById('cqChildWork')?.dataset.uuid===chapterUuid&&target.isConnected&&sameProject(session?.project,window.CQProject.read());
   try{
     const project=studentProject();
     if(!project?.url||!project?.anonKey)throw Error('Supabase 프로젝트 설정이 없습니다.');
     const transport=window.CQServerPDF.createPdfTransport({url:project.url,anonKey:project.anonKey,getAccessToken:()=>session?.uid===uid?childAccessToken():null});
     let expectedPages=null;const bytes=await transport.getPdf(chapterUuid,{signal:controller.signal,onMetadata:info=>expectedPages=info.page_count});
     if(!current())return;
     if(!window.pdfjsLib)throw Error('PDF 렌더러를 불러오지 못했습니다.');
     const doc=await window.pdfjsLib.getDocument({isEvalSupported:false,data:new Uint8Array(bytes.slice(0))}).promise;
     if(!current()){await doc.destroy();return;}
     if(expectedPages!==null&&doc.numPages!==expectedPages){await doc.destroy();throw Error('승인된 범위와 PDF 페이지 수가 다릅니다. 제출할 수 없습니다.');}serverPdfDocument=doc;
     const blob=new Blob([bytes],{type:'application/pdf'});
     serverPdfObjectUrl=URL.createObjectURL(blob);
     target.innerHTML='<div class="row"><button type="button" data-server-pdf="prev">이전 페이지</button><span data-server-pdf="count">PDF 준비 중</span><button type="button" data-server-pdf="next">다음 페이지</button><button type="button" data-server-pdf="out">축소 −</button><button type="button" data-server-pdf="in">확대 +</button></div><div data-server-pdf="stage" style="overflow:auto;text-align:center;background:#e9edf5;padding:8px"><canvas data-server-pdf="canvas" style="max-width:none;background:white"></canvas></div><p><a data-server-pdf="open" target="_blank" rel="noopener">배정된 챕터 PDF 새 탭에서 열기</a></p>';
     target.querySelector('[data-server-pdf="open"]').href=serverPdfObjectUrl;
     if(!window.pdfjsLib){target.querySelector('[data-server-pdf="stage"]').textContent='PDF 렌더러를 불러오지 못했습니다. 새 탭에서 원본 PDF를 열어주세요.';return;}
     let pageNumber=1,zoom=1,drawVersion=0,task=null;
     const canvas=target.querySelector('[data-server-pdf="canvas"]');
     async function draw(){
       const version=++drawVersion;
       if(task){const old=task;task=null;old.cancel();try{await old.promise}catch(e){if(e?.name!=='RenderingCancelledException')throw e;}}
       if(!current()||version!==drawVersion)return;
       const page=await doc.getPage(pageNumber);if(!current()||version!==drawVersion)return;
       const stage=target.querySelector('[data-server-pdf="stage"]');
       const natural=page.getViewport({scale:1});const fit=Math.min(1.8,Math.max(.3,(stage.clientWidth-20)/natural.width));
       const viewport=page.getViewport({scale:fit*zoom});const ratio=Math.min(2,window.devicePixelRatio||1);
       canvas.width=Math.ceil(viewport.width*ratio);canvas.height=Math.ceil(viewport.height*ratio);
       canvas.style.width=Math.ceil(viewport.width)+'px';canvas.style.height=Math.ceil(viewport.height)+'px';
       const next=page.render({canvasContext:canvas.getContext('2d'),viewport,transform:[ratio,0,0,ratio,0,0]});task=next;
       try{await next.promise}catch(e){if(e?.name!=='RenderingCancelledException')throw e;}finally{if(task===next)task=null;}
       if(current()&&version===drawVersion)target.querySelector('[data-server-pdf="count"]').textContent=pageNumber+' / '+doc.numPages+' 페이지';
     }
     target.addEventListener('click',event=>{
       if(!current())return;
       const action=event.target.closest('[data-server-pdf]')?.dataset.serverPdf;
       if(action==='prev')pageNumber=Math.max(1,pageNumber-1);
       else if(action==='next')pageNumber=Math.min(doc.numPages,pageNumber+1);
       else if(action==='in')zoom=Math.min(3,zoom+.25);
       else if(action==='out')zoom=Math.max(.5,zoom-.25);
       else return;
       draw().catch(e=>{if(current())target.querySelector('[data-server-pdf="count"]').textContent='표시 오류: '+e.message;});
     });
     await draw();
     if(current()){
       const form=document.getElementById('cqChildWork');
       form.dataset.pdfVerified='true';
       const read=form.elements.namedItem('readComplete');read.disabled=false;
       read.parentElement.lastChild.textContent=' 원문 읽기 완료';
       const submit=form.querySelector('[type="submit"]');submit.disabled=false;submit.textContent='최종 제출';submit.title='모든 활동을 마친 뒤 제출하세요.';
       target.insertAdjacentHTML('beforeend','<p class="muted">원본 PDF 연결 완료. 읽기와 모든 활동을 마친 뒤 제출하세요.</p>');
     }
   }catch(error){if(current()){target.textContent='원본 PDF를 불러오지 못했습니다: '+error.message;target.insertAdjacentHTML('beforeend','<p><button type="button" data-child="pdf-retry">답안을 유지하고 PDF 다시 불러오기</button></p>');}}
 }
 const childContext=()=>({uid:session?.uid,generation:childGeneration});
 const assertChildContext=ctx=>{if(!session||session.uid!==ctx.uid||childGeneration!==ctx.generation)throw Error('학생 계정이 변경되어 이전 요청 결과를 폐기했습니다.');studentProject();};
 function cancelChildUpload(){clearServerPdf();if(activeChildUpload){activeChildUpload.abort();activeChildUpload=null;}if(activeChildSubmit){activeChildSubmit.abort();activeChildSubmit=null;}}
 const AUDIO_RECOVERY_KEY='cq_v4_pending_audio_v1';
 const DRAFT_KEY='cq_v4_child_drafts_v1';
 const validDraftId=value=>/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(value||''));
 const draftId=(uid,uuid)=>uid+'/'+uuid;
 function readDraft(uid,uuid){
   if(!validDraftId(uid)||!validDraftId(uuid))return null;
   try {const draft=CQStudentStore.readMap(localStorage,DRAFT_KEY)[draftId(uid,uuid)];
     return draft?.uid===uid&&draft?.uuid===uuid&&Array.isArray(draft.answers)?draft:null;
   }catch{return null;}
 }
 function writeDraft(uid,uuid,form){
   if(!validDraftId(uid)||!validDraftId(uuid))throw Error('학생 또는 챕터 식별자가 올바르지 않습니다.');
   form.dataset.draftDirty='true';
   const answers=[];
   for(let i=0;form.querySelector(`[name="cqAnswer${i}"]`);i++){
     const checked=form.querySelector(`[name="cqAnswer${i}"]:checked`);
     const field=checked||form.querySelector(`textarea[name="cqAnswer${i}"]`);
     answers.push(field?.value??'');
   }
   const result=CQStudentStore.updateMap(localStorage,DRAFT_KEY,all=>{all[draftId(uid,uuid)]={uid,uuid,answers,essay:form.elements.namedItem('essay')?.value||'',
     speaking:form.elements.namedItem('speaking')?.value||'',wordsReviewed:[...form.querySelectorAll('[data-word-done]:checked')].map(x=>Number(x.dataset.wordDone)),
     readComplete:!!form.elements.namedItem('readComplete')?.checked,updatedAt:Date.now()};
   });
   form.dataset.draftDirty='false';return result;
 }
 function restoreDraft(uid,uuid,form){
   const draft=readDraft(uid,uuid);if(!draft)return false;
   for(let i=0;i<draft.answers.length;i++){
     const value=String(draft.answers[i]??'');
     const inputs=[...form.querySelectorAll(`[name="cqAnswer${i}"]`)];
     const radio=inputs.find(x=>x.type==='radio'&&x.value===value);
     if(radio)radio.checked=true;
     else {const field=inputs.find(x=>x.tagName==='TEXTAREA');if(field)field.value=value;}
   }
   form.elements.namedItem('essay').value=draft.essay||'';
   form.elements.namedItem('speaking').value=draft.speaking||'';
   form.elements.namedItem('readComplete').checked=!!draft.readComplete;
   for(const index of Array.isArray(draft.wordsReviewed)?draft.wordsReviewed:[]){const done=form.querySelector('[data-word-done="'+Number(index)+'"]');if(done)done.checked=true;}
   return true;
 }
 function clearDraft(uid,uuid){
   if(!validDraftId(uid)||!validDraftId(uuid))return;
   try {CQStudentStore.updateMap(localStorage,DRAFT_KEY,all=>{delete all[draftId(uid,uuid)];});}catch{}
 }

 const recoveryId=(uid,uuid)=>uid+'/'+uuid;
 const validAudioHash=value=>/^[0-9a-f]{64}$/.test(String(value||''));
 async function audioSha256(blob){
   if(!crypto?.subtle)throw Error('녹음 무결성 검사를 지원하지 않는 환경입니다. HTTPS에서 이용하세요.');
   const bytes=await blob.arrayBuffer();
   return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)))
     .map(x=>x.toString(16).padStart(2,'0')).join('');
 }
 function readRecovery(uid,uuid){
   try {const r=CQStudentStore.readMap(localStorage,AUDIO_RECOVERY_KEY)[recoveryId(uid,uuid)];
     return r&&['webm','mp4','ogg'].includes(r.ext)&&r.uid===uid&&r.uuid===uuid&&validAudioHash(r.sha256)?r:null;
   }catch{return null;}
 }
 function writeRecovery(uid,uuid,ext,phase='uploaded',sha256){
   if(!validAudioHash(sha256))throw Error('녹음 파일 무결성 정보가 없습니다.');
   CQStudentStore.updateMap(localStorage,AUDIO_RECOVERY_KEY,all=>{all[recoveryId(uid,uuid)]={uid,uuid,ext,phase,sha256,createdAt:Date.now()};});
 }
 function clearRecovery(uid,uuid){
   CQStudentStore.updateMap(localStorage,AUDIO_RECOVERY_KEY,all=>{delete all[recoveryId(uid,uuid)];});
 }
 async function verifyExistingAudio(uid,uuid,ext,expectedSha256){
   if(!validAudioHash(expectedSha256))throw Error('기존 녹음 파일의 무결성 정보를 확인할 수 없습니다.');
   const project=studentProject();
   if(!project?.url||!project?.anonKey||!session?.token||session.uid!==uid)throw Error('학생 인증이 필요합니다.');
   const response=await fetch(project.url+'/storage/v1/object/sign/cq-v4-speaking/'+uid+'/'+uuid+'.'+ext,{
     method:'POST',headers:{apikey:project.anonKey,Authorization:'Bearer '+session.token,'Content-Type':'application/json'},
     body:JSON.stringify({expiresIn:30})
   });
   if(!response.ok)return false;
   const body=await response.json();
   if(!body.signedURL)return false;
   // A matching object path is insufficient: a different recording may exist there.
   const signedUrl=new URL(body.signedURL,project.url+'/storage/v1/');
   if(signedUrl.origin!==new URL(project.url).origin)throw Error('녹음 확인 주소가 올바르지 않습니다.');
   const audioResponse=await fetch(signedUrl.href);
   if(!audioResponse.ok)return false;
   const bytes=await audioResponse.arrayBuffer();
   const actual=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)))
     .map(x=>x.toString(16).padStart(2,'0')).join('');
   if(actual!==expectedSha256)throw Error('서버의 녹음 내용이 기존 업로드 기록과 다릅니다. 덮어쓰거나 재사용하지 않습니다.');
   return true;
 }
 const submissionGate=CQSubmissionGate.createSubmissionGate({
   storage:localStorage,
   verifySubmission:async(uid,uuid)=>{
     if(!session||session.uid!==uid||!childApi)throw Error('SESSION_UNAVAILABLE');
     const result=await childApi.submission(uuid);
     if(!session||session.uid!==uid)throw Error('SESSION_CHANGED');
     if(result===null||result===undefined)throw Error('SUBMISSION_UNKNOWN');
     return Array.isArray(result)?result.length>0:!!result;
   },
   isCurrent:(uid,uuid,context)=>!!session&&session.uid===uid&&
      (!context||childGeneration===context.generation)&&
      chapters.some(c=>c.chapter_uuid===uuid)
 });
 const gateMessage=decision=>({submitted:'이미 서버에 제출된 챕터입니다. 녹음을 다시 저장하지 않습니다.',unverified:'서버 제출 상태를 확인할 수 없어 녹음 저장을 보류했습니다. 연결을 확인하고 저장 재시도를 누르세요.',confirmation_not_durable:'제출 확인 정보를 안전하게 저장할 수 없어 녹음 저장을 차단했습니다.',stale:'계정 또는 챕터가 변경되어 이전 녹음 저장을 중단했습니다.',invalid:'학생 또는 챕터 식별자가 올바르지 않습니다.'}[decision.status]||'녹음 저장을 진행할 수 없습니다.');
 const orderedVoice=CQAudioLifecycle.createAudioLifecycle(CQAudioVault.createVault());
 const durableVoice=CQAudioVault.createVault();
 let unsavedVoice=null; // memory-only; intentionally cleared on logout or chapter change
 let voiceSavePending=false;
 let voiceSaveCount=0;
 const beginVoiceSave=()=>{voiceSaveCount++;voiceSavePending=true;};
 const finishVoiceSave=()=>{voiceSaveCount=Math.max(0,voiceSaveCount-1);voiceSavePending=voiceSaveCount>0;};
 const discardUnsavedVoice=()=>{unsavedVoice=null;};
 const hasAtRiskVoice=()=>!!unsavedVoice||voiceSavePending||voiceRecorder?.state==='recording';
 const hasAtRiskDraft=()=>document.getElementById('cqChildWork')?.dataset.draftDirty==='true';
 const confirmLessonDeparture=()=>{if(hasAtRiskDraft()){status('답안이 아직 저장되지 않아 이동을 중단했습니다. 화면을 유지하고 답안 저장 재시도를 누르세요.');return false;}return confirmVoiceDeparture();};
 const confirmVoiceDeparture=()=>!hasAtRiskVoice()||window.confirm('아직 기기에 안전하게 저장되지 않은 녹음이 있습니다. 이동하면 녹음이 사라질 수 있습니다. 계속하시겠습니까?');
 window.addEventListener('beforeunload',event=>{if(!hasAtRiskVoice()&&!hasAtRiskDraft())return;event.preventDefault();event.returnValue='';});
 function invalidateVoiceForNavigation(){
   clearVoicePreview();
   childGeneration++;discardUnsavedVoice();
   if(voiceRecorder?.state==='recording')voiceRecorder.stop();
   voiceBlob=null;voiceChapter=null;
 }
 const backupMimeAllowed=new Set(['audio/webm','audio/mp4','audio/ogg']);
 const backupFileExt=mime=>mime==='audio/mp4'?'mp4':mime==='audio/ogg'?'ogg':'webm';
 async function downloadUnsavedVoice(){
   const item=unsavedVoice;
   if(!item||!session||item.uid!==session.uid||item.generation!==childGeneration||el('cqChildWork')?.dataset.uuid!==item.uuid)throw Error('현재 챕터에 내려받을 임시 녹음이 없습니다.');
   if(!backupMimeAllowed.has(item.blob.type)||!item.blob.size||item.blob.size>10485760)throw Error('녹음 파일 형식 또는 크기를 확인하세요.');
   const manifest=await CQVoiceManifest.create(item.blob,item.uid,item.uuid);
   if(!session||session.uid!==item.uid||childGeneration!==item.generation||el('cqChildWork')?.dataset.uuid!==item.uuid)throw Error('백업 생성 중 학생 또는 챕터가 변경되었습니다.');
   const url=URL.createObjectURL(item.blob);
   const a=document.createElement('a');a.href=url;a.download='chapterquest-audio-backup-'+item.uuid+'.'+backupFileExt(item.blob.type);
   document.body.appendChild(a);a.click();a.remove();
   setTimeout(()=>URL.revokeObjectURL(url),60000);
   const metaUrl=URL.createObjectURL(new Blob([JSON.stringify(manifest,null,2)],{type:'application/json'}));
   const metaLink=document.createElement('a');metaLink.href=metaUrl;metaLink.download='chapterquest-audio-backup-'+item.uuid+'.cqvoice.json';document.body.appendChild(metaLink);metaLink.click();metaLink.remove();setTimeout(()=>URL.revokeObjectURL(metaUrl),60000);
   voiceNotice('녹음과 검증 정보 파일 2개의 다운로드를 요청했습니다. 둘 다 실제 저장됐는지 확인하세요.');
 }
 let voiceImportManifest=null;
 async function restoreVoiceBackup(file){
   if(!file||!session||!el('cqChildWork'))throw Error('학생 로그인과 챕터 선택이 필요합니다.');
   const uid=session.uid,uuid=el('cqChildWork').dataset.uuid,generation=childGeneration;
   if(voiceSavePending||voiceRecorder?.state==='recording')throw Error('녹음 또는 저장 작업이 끝난 뒤 복원하세요.');
   if(!backupMimeAllowed.has(file.type)||!file.size||file.size>10485760)throw Error('지원되는 녹음 형식(webm/mp4/ogg), 10MB 이하 파일만 복원할 수 있습니다.');
   if(!voiceImportManifest)throw Error('검증 정보 파일이 없습니다. .cqvoice.json 파일부터 선택하세요.');
   const manifest=voiceImportManifest;
   await CQVoiceManifest.verify(file,manifest,uid,uuid);
   if(!session||session.uid!==uid||childGeneration!==generation||el('cqChildWork')?.dataset.uuid!==uuid)throw Error('검증 도중 학생 또는 챕터가 변경되었습니다.');
   const item={uid,uuid,generation,blob:file};
   unsavedVoice=item;beginVoiceSave();voiceNotice('복구 파일을 확인하고 안전하게 저장 중입니다...');
   try{
     const result=await submissionGate.save(uid,uuid,file,{generation},(u,c,b)=>orderedVoice.save(u,c,b,()=>!!session&&session.uid===u&&childGeneration===generation&&el('cqChildWork')?.dataset.uuid===c,true));
     if(!session||session.uid!==uid||childGeneration!==generation||el('cqChildWork')?.dataset.uuid!==uuid)return;
     if(result.status!=='written'||result.result?.status!=='saved'){voiceNotice(gateMessage(result)+' 복구 파일은 현재 화면에서만 보관됩니다.');return;}
     if(unsavedVoice===item)discardUnsavedVoice();voiceBlob=file;voiceChapter=uuid;
     voiceNotice('복구 파일 저장 완료 · 서버 미전송. 제출 전에 녹음 내용을 확인하세요.');
   }catch(err){if(session?.uid===uid&&childGeneration===generation)voiceNotice('복구 파일 저장 실패: '+err.message+' · 원본 파일을 기기에 보관하세요.');}
   finally{finishVoiceSave();}
 }
 let voicePreviewUrl=null,voicePreviewBlob=null;
 function clearVoicePreview(){if(voicePreviewUrl)URL.revokeObjectURL(voicePreviewUrl);voicePreviewUrl=null;voicePreviewBlob=null;}
 function previewVoice(){
  const target=document.getElementById('cqVoicePlayback');
  if(!target||!voiceBlob||!session||document.getElementById('cqChildWork')?.dataset.uuid!==voiceChapter)return;
  if(voicePreviewBlob===voiceBlob&&target.querySelector('audio'))return;
  clearVoicePreview();voicePreviewBlob=voiceBlob;voicePreviewUrl=URL.createObjectURL(voiceBlob);
  const audio=document.createElement('audio');audio.controls=true;audio.src=voicePreviewUrl;audio.setAttribute('aria-label','제출 전 녹음 확인');target.replaceChildren(audio);
 }
 const voiceNotice=(message)=>{const n=document.getElementById('cqVoiceStatus');if(n)n.textContent=message;previewVoice();};
 const cleanupQueue=CQAudioCleanupQueue.createCleanupQueue({
   storage:localStorage,
   verifySubmission:async(uid,uuid)=>{
     if(!session||session.uid!==uid||!childApi)return false;
     const result=await childApi.submission(uuid);
     if(!session||session.uid!==uid)return false;
     return !!(Array.isArray(result)?result.length:result);
   },
   removeAudio:(uid,uuid)=>orderedVoice.finalize(uid,uuid),
   isCurrent:(uid,uuid,context)=>!!session&&session.uid===uid&&(!context||childGeneration===context.generation)&&chapters.some(c=>c.chapter_uuid===uuid)
 });
 async function cleanupConfirmedAudio(uid,uuid,context){
   // Direct submission and recovery use ONE cleanup queue. Mark intent before
   // deletion, then let reconcile serialize and deduplicate both callers.
   const current=()=>!!session&&session.uid===uid&&childGeneration===context.generation;
   if(!current())return false;
   try{cleanupQueue.mark(uid,uuid)}
   catch(err){console.warn('Cleanup intent unavailable; preserving audio:',err?.name||'UNKNOWN');return false;}
   if(!current())return false;
   try{
     const outcome=await cleanupQueue.reconcile(uid,uuid,{generation:context.generation,serverConfirmed:true});
     return current()&&outcome.status==='cleaned';
   }catch(err){console.warn('Local audio cleanup pending:',err?.name||'UNKNOWN');return false;}
 }
 async function retryConfirmedCleanup(uid,uuid,generation){
   if(!cleanupQueue.pending(uid,uuid))return;
   try{
     const outcome=await cleanupQueue.reconcile(uid,uuid,{generation});
     if(session?.uid===uid&&childGeneration===generation&&['retry','cleaned_intent_pending'].includes(outcome.status))
       status('제출된 녹음의 기기 저장 파일 정리가 아직 완료되지 않았습니다. 다음에 다시 시도합니다.');
   }catch(err){if(session?.uid===uid&&childGeneration===generation)status('녹음 정리 재확인 실패: '+err.message);}
 }
 async function restoreDurableVoice(uid,uuid,generation){
   try{
     const saved=await durableVoice.load(uid,uuid,()=>!!session&&session.uid===uid&&childGeneration===generation&&document.getElementById('cqChildWork')?.dataset.uuid===uuid);
     if(!session||session.uid!==uid||childGeneration!==generation||document.getElementById('cqChildWork')?.dataset.uuid!==uuid)return;
     if(saved){voiceBlob=saved.blob;voiceChapter=uuid;voiceNotice('이 기기에 저장된 녹음 원본을 복원했습니다 ('+Math.ceil(saved.size/1024)+'KB).');}
   }catch(err){
     if(session?.uid===uid&&childGeneration===generation)voiceNotice('녹음 원본을 불러오지 못했습니다: '+err.message+' · 제출 전 확인하세요.');
   }
 }
 const el=id=>document.getElementById(id);
 const escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 function draw(){
  const root=el('cqChildAccount');if(!root)return;
  root.innerHTML=`<section class="card"><h2>🔐 학생 계정 로그인</h2>
   <p class="muted">학생 본인의 계정으로 로그인하세요. 부모가 승인하고 배정한 챕터를 학습할 수 있습니다. 기기 데모 기록은 별도로 보관됩니다. 작성 중인 답안은 이 기기에 자동 저장되며 같은 계정으로 다시 로그인하면 이어서 학습할 수 있습니다.</p>
   ${session?`<p>학생 계정 로그인됨 · 계정 확인번호 <strong data-child-reference>${escape(session.uid.slice(-8))}</strong></p>${session.resumedExisting?`<div role="status" aria-live="polite" data-session-summary><p>인증: 기존 익명 계정 확인됨</p><p>부모 연결: 기존 연결 확인됨 · 재초대하지 마세요.</p><p>승인·배정: ${session.assignmentCount==null?'조회 전 또는 조회 실패':session.assignmentCount+'개 학습 가능'}</p>${session.assignmentCount===0?'<p>학습 가능한 챕터가 없습니다. 미승인인지 미배정인지는 부모 관리자에서 확인해야 합니다.</p>':''}</div>`:`<div class="row"><input id="cqChildInvite" placeholder="부모 초대코드 (48자리)" autocomplete="off" style="flex:1"><input id="cqChildInviteName" placeholder="학생 이름" style="max-width:130px"><button data-child="claim">연결 요청</button></div>`}<button data-child="list">내 배정 챕터 불러오기</button>${session.resumedExisting?'<button data-child="recheck-existing">같은 계정 세션 다시 확인 · 답안 유지</button>':'<button data-child="logout">로그아웃</button>'}
    <div>${chapters.map(c=>`<div class="book"><b>${escape(c.chapter_title)}</b><button data-child="view" data-uuid="${escape(c.chapter_uuid)}">원문·문제 보기</button></div>`).join('')}</div><div id="cqChildDetail"></div>`:
    `<div class="grid"><label>학생 이메일<input id="cqChildEmail" type="email" autocomplete="username"></label><label>학생 비밀번호<input id="cqChildPassword" type="password" autocomplete="current-password"></label></div><button data-child="inspect-existing">이 기기의 기존 익명 계정 확인 · 읽기 전용</button><p class="muted">기존 저장 세션만 확인합니다. 새 가입·토큰 갱신·계정 전환은 하지 않습니다. 기록이 없거나 만료됐으면 원래 계정을 유지하고 중단합니다.</p><details><summary>기존 계정으로 다시 들어가는 방법</summary><p>기존에 쓰던 브라우저와 프로필에서 확인하세요. 이메일 계정이었던 경우에만 아래 기존 이메일 로그인을 사용하세요. 익명 계정은 이메일 입력이나 새 가입으로 복구되지 않습니다. 저장 세션이 없거나 만료되면 계정을 바꾸지 말고 부모와 기존 계정 확인번호를 대조한 뒤 복구 절차를 요청하세요. 비밀번호·인증 토큰은 공유하지 마세요.</p></details><button data-child="login">학생 계정 로그인</button><button data-child="signup-open">학생 계정 만들기</button><div id="cqChildSignup" hidden><label>비밀번호 확인<input id="cqChildPasswordConfirm" type="password" autocomplete="new-password"></label><p class="muted">학생용 별도 계정을 만들고 부모 초대코드로 연결하세요. 비밀번호는 8자 이상 입력하세요.</p><button data-child="signup">새 학생 계정 생성</button><button data-child="signup-cancel">취소</button></div>`}
   <p id="cqChildStatus" class="status"></p></section>`;
 }
 const status=t=>{if(el('cqChildStatus'))el('cqChildStatus').textContent=t};
 const originalRender=render;
 render=function(){originalRender();if(mode==='student'){el('app')?.insertAdjacentHTML('afterbegin','<div id="cqChildAccount"></div>');draw()}};
 let childRefreshPromise=null;
 async function childAccessToken(){
  if(!session)throw Error('학생 계정으로 다시 로그인하세요.');
  studentProject();
  if(session.resumedExisting){if(Date.now()<session.expiresAt-5000)return session.token;throw Error('기존 세션이 만료되었습니다. 계정을 바꾸거나 자동 갱신하지 않았습니다. 같은 계정 세션 다시 확인을 눌러 유효한 기존 기록을 확인하세요. 자동 갱신은 하지 않습니다.');}
  if(Date.now()<session.expiresAt-60000)return session.token;
  if(childRefreshPromise)return childRefreshPromise;
  const owner=session,generation=childGeneration,project=studentProject();
  const pending=(async()=>{
   if(!owner.refreshToken)throw Error('학생 로그인이 만료되었습니다. 다시 로그인하세요. 임시 답변은 보존됩니다.');
   const response=await fetch(project.url+'/auth/v1/token?grant_type=refresh_token',{method:'POST',headers:{apikey:project.anonKey,'Content-Type':'application/json'},body:JSON.stringify({refresh_token:owner.refreshToken})});
   const data=await response.json();
   if(session!==owner||generation!==childGeneration)throw Error('학생 계정이 변경되었습니다.');
   studentProject();
   if(!response.ok||!data.access_token||!data.refresh_token)throw Error('학생 로그인 갱신에 실패했습니다. 다시 로그인하세요. 임시 답변은 보존됩니다.');
   owner.token=data.access_token;owner.refreshToken=data.refresh_token;owner.expiresAt=Date.now()+(data.expires_in||3600)*1000;
   return owner.token;
  })();childRefreshPromise=pending;
  try{return await pending}finally{if(childRefreshPromise===pending)childRefreshPromise=null}
 }
 function startChildSession(data,project){
  if(!sameProject(project,window.CQProject.read()))throw Error('로그인 중 프로젝트가 변경되어 이전 인증 결과를 적용하지 않았습니다.');
  if(!data.access_token||!data.user?.id)throw Error('인증 정보를 확인할 수 없습니다. 다시 로그인하세요.');
  childGeneration++;childRefreshPromise=null;cancelChildUpload();session={project:Object.freeze({...project}),token:data.access_token,uid:data.user.id,refreshToken:data.refresh_token,expiresAt:Date.now()+(data.expires_in||3600)*1000};
  childApi=CQStudentAPI.createStudentAPI({url:project.url,anonKey:project.anonKey,getAccessToken:childAccessToken});
  chapters=[];draw();status('로그인 성공 · 계정 인증과 실제 학생 권한은 서버 정책으로 확인됩니다.');
 }
 async function login(){
  const project=window.CQProject.read(),generation=childGeneration;
  if(!project?.url||!project?.anonKey)throw Error('부모 관리자에서 Supabase 프로젝트 공개 설정을 먼저 저장해야 합니다.');
  const email=el('cqChildEmail').value.trim(),password=el('cqChildPassword').value;
  if(!email||!password)throw Error('학생 이메일과 비밀번호를 입력하세요.');
  const response=await fetch(project.url+'/auth/v1/token?grant_type=password',{
   method:'POST',headers:{apikey:project.anonKey,'Content-Type':'application/json'},body:JSON.stringify({email,password})});
  if(!response.ok)throw Error('학생 로그인 실패 ('+response.status+')');
  const data=await response.json();if(!data.access_token||!data.user?.id)throw Error('인증 정보가 없습니다.');
  if(generation!==childGeneration||mode!=='student')throw Error('로그인 화면이 변경되어 이전 인증 결과를 적용하지 않았습니다.');
  startChildSession(data,project);
 }
 window.CQStudentNavigation=Object.freeze({leave(){if(!confirmLessonDeparture())return false;invalidateVoiceForNavigation();cancelChildUpload();return true;}});
 document.addEventListener('click',event=>{
  if(mode!=='student')return;
  if(event.target.closest('#studentBtn')&&el('cqChildWork')){event.preventDefault();event.stopImmediatePropagation();return;}
  if(event.target.closest('#parentBtn')&&!CQStudentNavigation.leave()){event.preventDefault();event.stopImmediatePropagation();}
 },true);
 document.addEventListener('click',async e=>{
  const b=e.target.closest('[data-child]');if(!b||mode!=='student')return;
  if(b.dataset.child==='logout'){
    if(!confirmLessonDeparture())return;
    invalidateVoiceForNavigation();cancelChildUpload();uploadedAudio.clear();session=null;childRefreshPromise=null;childApi=null;chapters=[];
    draw();status('로그아웃했습니다. 진행 중인 녹음 업로드는 취소를 요청했습니다.');return;
  }
  if(b.dataset.child==='voice-stop'){if(voiceRecorder?.state==='recording')voiceRecorder.stop();return;}
  if(busy)return;
  if(['list','view','feedback'].includes(b.dataset.child)&&!confirmLessonDeparture())return;
  busy=true;b.disabled=true;
  let viewContext=null;
  try{
   if(b.dataset.child==='draft-retry'){
    const form=el('cqChildWork');if(!session||!form)throw Error('현재 학습 답안을 확인하세요.');
    writeDraft(session.uid,form.dataset.uuid,form);
    const saved=el('cqDraftStatus');if(saved)saved.textContent='이 기기에 답안 자동 저장됨';
    status('현재 답안을 기기에 저장했습니다. 같은 계정으로 다시 진입하면 이어서 학습할 수 있습니다.');return;
   }
   if(b.dataset.child==='recheck-existing'){
    if(!session?.resumedExisting)throw Error('기존 익명 계정 확인 후 사용할 수 있습니다.');
    const owner=childContext(),project=studentProject();
    const result=await CQExistingStudentSession.inspect({project,storage:localStorage});
    assertChildContext(owner);const currentProject=window.CQProject.read();
    if(currentProject?.url!==project?.url||currentProject?.anonKey!==project?.anonKey)throw Error('프로젝트가 변경되어 확인 결과를 적용하지 않았습니다.');
    if(result.status!=='ready')throw Error('기존 세션을 다시 확인하지 못했습니다. 답안·녹음을 유지했습니다. 자동 갱신·가입·계정 변경은 하지 않았습니다.');
    if(result.session.uid!==owner.uid)throw Error('다른 계정의 세션입니다. 전환하지 않고 현재 답안·녹음을 유지했습니다.');
    session.token=result.session.token;session.expiresAt=result.session.expiresAt;
    status('같은 계정의 유효 세션을 확인했습니다. 작성 중인 답안·녹음은 그대로이며 자동 갱신은 하지 않았습니다.');return;
   }
   if(b.dataset.child==='pdf-retry'){
    const form=el('cqChildWork'),uuid=form?.dataset.uuid;
    if(!session||!uuid||!chapters.some(c=>c.chapter_uuid===uuid))throw Error('현재 배정 챕터를 확인하세요.');
    await loadServerPdf(uuid,session.uid,childGeneration);return;
   }
   if(b.dataset.child==='inspect-existing'){
    const generation=childGeneration,project=window.CQProject.read(),result=await CQExistingStudentSession.inspect({project,storage:localStorage});
    const currentProject=window.CQProject.read();
    if(generation!==childGeneration||session||mode!=='student'||currentProject?.url!==project?.url||currentProject?.anonKey!==project?.anonKey)return;
    if(result.status==='ready'){
     childGeneration++;childRefreshPromise=null;session={...result.session,project:Object.freeze({...project}),resumedExisting:true};
     childApi=CQStudentAPI.createStudentAPI({url:project.url,anonKey:project.anonKey,getAccessToken:childAccessToken});chapters=[];draw();
     const owner=childContext(),api=childApi;
     try{const rows=await api.assignedChapters();assertChildContext(owner);if(childApi!==api)return;chapters=rows;session.assignmentCount=rows.length;draw();}catch(err){if(session?.uid===owner.uid&&childGeneration===owner.generation)status('인증·부모 연결은 확인됐지만 배정 조회에 실패했습니다. 내 배정 챕터 불러오기로 재시도하세요.');return;}
     status('기존 익명 계정과 부모 연결을 읽기로 확인했습니다. 계정 확인번호를 부모와 대조한 뒤 내 배정 챕터를 불러오세요. 토큰 갱신·계정 변경은 하지 않았습니다.');
    }else{
     const messages={absent:'이 브라우저에서 지원되는 기존 세션 기록을 찾지 못했습니다. 계정이 삭제됐다는 뜻은 아닙니다.',expired:'기존 세션으로 인증되지 않거나 만료되었습니다. 자동 갱신하지 않았습니다.',unlinked:'이 계정의 기존 부모 연결을 확인하지 못했습니다. 임의로 연결하지 않았습니다.','not-anonymous':'저장된 세션을 기존 익명 학생으로 확인할 수 없습니다. 다른 계정으로 전환하지 않았습니다.',configuration:'프로젝트 공개 설정을 확인하세요.',unreadable:'기존 세션 기록을 안전하게 읽지 못했습니다. 원본은 보존했습니다.',invalid:'기존 세션 형식/유효 기간을 확인하지 못했습니다. 원본은 보존했습니다.',unavailable:'읽기 확인에 실패했습니다. 계정·세션 기록은 변경하지 않았습니다.'};
     status((messages[result.status]||messages.unavailable)+' 가입·로그아웃·저장소 삭제를 하지 말고 지원 절차로 확인하세요.');
    }return;
   }
   if(b.dataset.child==='signup-open'||b.dataset.child==='signup-cancel'){
    el('cqChildSignup').hidden=b.dataset.child==='signup-cancel';el('cqChildPassword').autocomplete=b.dataset.child==='signup-open'?'new-password':'current-password';return;
   }
   if(b.dataset.child==='signup'){
    const project=window.CQProject.read(),generation=childGeneration,email=el('cqChildEmail')?.value.trim(),password=el('cqChildPassword')?.value,confirm=el('cqChildPasswordConfirm')?.value;
    if(!project?.url||!CQOrigin.allows(project.url)||!project.anonKey)throw Error('학생 계정 서버 설정을 확인하세요.');
    if(!email||!el('cqChildEmail').checkValidity())throw Error('학생 계정 이메일을 확인하세요.');
    if(!password||password.length<8||password.length>128||password!==confirm)throw Error('8자 이상 비밀번호와 확인 입력이 일치해야 합니다.');
    const response=await fetch(project.url+'/auth/v1/signup',{method:'POST',headers:{apikey:project.anonKey,'Content-Type':'application/json'},body:JSON.stringify({email,password})});
    const data=await response.json();if(!response.ok)throw Error(data.msg||data.message||data.error_description||'학생 계정 생성에 실패했습니다.');
    if(generation!==childGeneration||mode!=='student'||!sameProject(project,window.CQProject.read()))throw Error('계정 요청 중 화면/프로젝트가 변경되어 결과를 적용하지 않았습니다.');
    if(data.access_token){startChildSession(data,project);status('학생 계정 생성 완료. 부모 초대코드로 연결을 요청하세요.');}
    else status('가입 요청이 처리되었습니다. 이메일 인증이 필요한 경우 인증을 마친 뒤 학생 계정으로 로그인하세요.');
    return;
   }
   if(b.dataset.child==='login')await login();
   else if(session&&['claim','list','view'].includes(b.dataset.child))await childAccessToken();
   if(b.dataset.child==='claim'&&session?.resumedExisting)throw Error('기존 연결을 유지합니다. 재초대하지 않습니다.');
   if(b.dataset.child==='claim'){
     if(!session)throw Error('학생 로그인 후 요청하세요.');
     const code=el('cqChildInvite')?.value.trim(),name=el('cqChildInviteName')?.value.trim();
     if(!/^[0-9a-f]{48}$/.test(code||''))throw Error('초대코드 형식을 확인하세요.');
     if(!name||name.length>80)throw Error('학생 이름을 입력하세요.');
     const project=studentProject();
     const ok=await CQInvitationAPI.claim({url:project?.url,anonKey:project?.anonKey,getAccessToken:childAccessToken},code,name);
     if(!ok)throw Error('초대코드가 만료됐거나 이미 사용됐습니다.');
     draw();status('연결 요청 완료. 부모 승인을 기다리세요.');
   }
   if(b.dataset.child==='voice-start'){
     if(!session||!el('cqChildWork'))throw Error('학습 화면에서 로그인한 후 녹음하세요.');
     if(voiceRecorder?.state==='recording'||voiceSavePending)throw Error('녹음 또는 녹음 저장이 진행 중입니다.');
     if(!navigator.mediaDevices?.getUserMedia||!window.MediaRecorder)throw Error('이 기기에서 녹음을 지원하지 않습니다.');
     const targetChapter=el('cqChildWork').dataset.uuid;
     if(uploadedAudio.has(session.uid+'/'+targetChapter)||readRecovery(session.uid,targetChapter))throw Error('서버에 이전 녹음 기록이 있습니다. 답변 제출을 재시도하세요.');
     // Capture the authenticated context BEFORE the permission prompt: it can resolve after logout.
     const recordingContext=childContext();
     const acquiredStream=await navigator.mediaDevices.getUserMedia({audio:true});
     if(!session||session.uid!==recordingContext.uid||childGeneration!==recordingContext.generation||el('cqChildWork')?.dataset.uuid!==targetChapter){
       acquiredStream.getTracks().forEach(t=>t.stop());
       throw Error('학생 계정 또는 챕터가 변경되어 녹음을 시작하지 않았습니다.');
     }
     discardUnsavedVoice();
     voiceStream=acquiredStream;
     const localChunks=[];voiceChunks=localChunks;voiceBlob=null;voiceChapter=targetChapter;
     const preferred=['audio/webm','audio/mp4','audio/ogg'].find(x=>MediaRecorder.isTypeSupported(x));
     if(!preferred){acquiredStream.getTracks().forEach(t=>t.stop());if(voiceStream===acquiredStream)voiceStream=null;throw Error('지원되는 녹음 형식이 없습니다.');}
     const currentRecorder=new MediaRecorder(acquiredStream,{mimeType:preferred});
     voiceRecorder=currentRecorder;
     currentRecorder.ondataavailable=e=>{if(e.data.size)localChunks.push(e.data)};
     currentRecorder.onstop=async()=>{
       acquiredStream.getTracks().forEach(t=>t.stop());
       if(voiceStream===acquiredStream)voiceStream=null;
       if(voiceRecorder===currentRecorder)voiceRecorder=null;
       if(!session||session.uid!==recordingContext.uid||childGeneration!==recordingContext.generation||el('cqChildWork')?.dataset.uuid!==targetChapter)return;
       const completed=new Blob(localChunks,{type:preferred});
       voiceBlob=null;voiceChapter=null;
       unsavedVoice={uid:recordingContext.uid,uuid:targetChapter,generation:recordingContext.generation,blob:completed};
       beginVoiceSave();
       voiceNotice('녹음 원본을 이 기기에 저장 중입니다...');
       try{
         const writeResult=await submissionGate.save(recordingContext.uid,targetChapter,completed,recordingContext,
           (uid,uuid,blob)=>orderedVoice.save(uid,uuid,blob,()=>!!session&&session.uid===uid&&childGeneration===recordingContext.generation&&el('cqChildWork')?.dataset.uuid===uuid,true));
         if(writeResult.status!=='written'||writeResult.result?.status!=='saved'){
           if(session?.uid===recordingContext.uid&&childGeneration===recordingContext.generation)
             voiceNotice(gateMessage(writeResult));
           return;
         }
         if(!session||session.uid!==recordingContext.uid||childGeneration!==recordingContext.generation)return;
         if(unsavedVoice?.blob===completed)discardUnsavedVoice();
         voiceBlob=completed;voiceChapter=targetChapter;
         voiceNotice('녹음 원본 저장 완료 ('+Math.ceil(completed.size/1024)+'KB) · 서버 미전송');
       }catch(err){
         if(session?.uid===recordingContext.uid&&childGeneration===recordingContext.generation){
           voiceNotice('녹음 저장 실패: '+err.message+' · 이 화면에서 저장 재시도를 누르세요. 화면을 닫으면 미저장 녹음은 사라집니다.');
         }
       }finally{finishVoiceSave();}
     };
     currentRecorder.start();const note=el('cqVoiceStatus');if(note)note.textContent='녹음 중...';
   }
   if(b.dataset.child==='voice-download'){downloadUnsavedVoice();}
   if(b.dataset.child==='voice-import'){const input=el('cqVoiceManifestImport');if(!input)throw Error('녹음 검증 정보 입력을 찾을 수 없습니다.');input.click();}
   if(b.dataset.child==='voice-retry'){
     const item=unsavedVoice;
     if(!item||!session||item.uid!==session.uid||item.generation!==childGeneration||el('cqChildWork')?.dataset.uuid!==item.uuid)throw Error('현재 학생·챕터에 재시도할 녹음이 없습니다.');
     if(voiceSavePending)throw Error('이전 녹음 저장이 완료될 때까지 기다려주세요.');
     beginVoiceSave();
     voiceNotice('녹음 저장을 다시 시도 중입니다...');
     try{
       const writeResult=await submissionGate.save(item.uid,item.uuid,item.blob,{generation:item.generation},
         (uid,uuid,blob)=>orderedVoice.save(uid,uuid,blob,()=>!!session&&session.uid===uid&&childGeneration===item.generation&&el('cqChildWork')?.dataset.uuid===uuid,true));
       if(writeResult.status!=='written'||writeResult.result?.status!=='saved'){
         if(session?.uid===item.uid&&childGeneration===item.generation)voiceNotice(gateMessage(writeResult));
         return;
       }
       if(!session||session.uid!==item.uid||childGeneration!==item.generation||el('cqChildWork')?.dataset.uuid!==item.uuid)return;
       if(unsavedVoice===item)discardUnsavedVoice();
       voiceBlob=item.blob;voiceChapter=item.uuid;
       voiceNotice('녹음 원본 저장 완료 · 서버 미전송');
     }catch(err){
       if(session?.uid===item.uid&&childGeneration===item.generation&&el('cqChildWork')?.dataset.uuid===item.uuid)voiceNotice('저장 재시도 실패: '+err.message+' · 녹음은 이 화면의 메모리에만 남아 있습니다.');
     }finally{finishVoiceSave();}
   }
   if(b.dataset.child==='list'){
     const owner=childContext(),api=childApi;const rows=await api.assignedChapters();assertChildContext(owner);if(childApi!==api)throw Error('학생 계정이 변경되었습니다.');
     if(hasAtRiskDraft()){status('조회 중 답안 저장에 실패해 이동을 중단했습니다. 답안 저장 재시도를 누르세요.');return;}
     invalidateVoiceForNavigation();clearServerPdf();chapters=rows;if(session.resumedExisting)session.assignmentCount=rows.length;draw();status(chapters.length+'개 챕터를 불러왔습니다.');
   }
   if(b.dataset.child==='view'||b.dataset.child==='feedback'){
    const c=chapters.find(x=>x.chapter_uuid===b.dataset.uuid);
    if(!c)throw Error('배정된 챕터가 아닙니다.');
    const viewUid=session.uid,requestGeneration=childGeneration,viewApi=childApi;
    viewContext={uid:viewUid,generation:requestGeneration,api:viewApi};
    const previous=await viewApi.submission(c.chapter_uuid);
    assertChildContext(viewContext);if(childApi!==viewApi)return;
    const submitted=Array.isArray(previous)?previous[0]:previous;
    let activity={};
    if(!submitted){
     const activityRows=await viewApi.chapterActivities(c.chapter_uuid);
     if(!Array.isArray(activityRows)||activityRows.length!==1)throw Error('챕터 학습 활동을 조회할 수 없습니다.');
     activity=activityRows[0];
    }
    // Commit navigation only after all required reads succeed. Failed reads keep
    // the current form, active PDF and durable/in-memory recording intact.
    assertChildContext(viewContext);if(childApi!==viewApi)return;
    if(!el('cqChildDetail'))return;
    if(hasAtRiskDraft()){status('조회 중 답안 저장에 실패해 이동을 중단했습니다. 답안 저장 재시도를 누르세요.');return;}
    invalidateVoiceForNavigation();clearServerPdf();
    const viewGeneration=childGeneration;viewContext={uid:viewUid,generation:viewGeneration,api:viewApi};
    const pending=submitted?null:readRecovery(viewUid,c.chapter_uuid);
    const detail=el('cqChildDetail');if(!detail)return;
    const questionFields=(c.questions||[]).map((q,i)=>{
      const choices=(q.options||[]).map((o,j)=>`<label><input type="radio" name="cqAnswer${i}" value="${j}" required> ${escape(o)}</label>`).join('');
      return `<fieldset><legend>${i+1}. ${escape(q.text||q.question||'질문')}</legend>${choices||`<textarea name="cqAnswer${i}" rows="3" required></textarea>`}</fieldset>`;
    }).join('');
    const vocabulary=Array.isArray(activity.vocabulary)?activity.vocabulary:[];
    const vocabularyHtml=vocabulary.map((v,i)=>`<li class="word-card"><strong>${escape(v.word||'')}</strong><div class="row"><button type="button" data-word-reveal="${i}" aria-expanded="false">뜻 보기</button><button type="button" data-word-speak="${escape(v.word||'')}">단어 듣기</button><label><input type="checkbox" data-word-done="${i}"> 학습 완료</label></div><p data-word-meaning="${i}" hidden>${escape(v.meaning||'')} ${v.example?`<small>${escape(v.example)}</small>`:''}</p></li>`).join('');
    const activityHtml=`<section data-learn-section="words"><h4>핵심 단어</h4><ul>${vocabularyHtml||'<li>등록된 단어가 없습니다.</li>'}</ul></section><section data-learn-section="prompts"><h4>영어 독후감 질문</h4><p>${escape(activity.writing_prompt||'')}</p><h4>말하기 질문</h4><p>${escape(activity.speaking_prompt||'')}</p></section>`;
    const form=`${pending?'<p class="muted">이전에 업로드된 녹음이 있습니다. 최종 제출 시 서버에서 파일을 확인합니다. 임시저장된 답변이 있다면 자동으로 복원됩니다.</p>':''}<form id="cqChildWork" novalidate data-uuid="${escape(c.chapter_uuid)}"><nav class="learn-nav" aria-label="학습 순서"><button type="button" data-learn-jump="read">1 원문</button><button type="button" data-learn-jump="words">2 단어</button><button type="button" data-learn-jump="questions">3 문제</button><button type="button" data-learn-jump="writing">4 글쓰기</button><button type="button" data-learn-jump="speaking">5 말하기</button><button type="button" data-learn-jump="submit">6 제출</button></nav><div id="cqServerPdfViewer" data-learn-section="read" class="card" role="region" aria-label="원본 PDF 읽기">원본 PDF 접근 권한을 확인하는 중입니다...</div><div class="note" role="status">원본 PDF를 읽고 문제·독후감·말하기를 완료하세요. PDF를 불러오지 못하면 제출할 수 없습니다.</div>${activityHtml}<label><input type="checkbox" name="readComplete" required disabled> 원문 PDF 연결 대기</label><section data-learn-section="questions">${questionFields}</section><label data-learn-section="writing">영어 독후감<textarea name="essay" rows="5" required></textarea></label><label data-learn-section="speaking">말하기 대본<textarea name="speaking" rows="3" required></textarea></label><div class="row"><button type="button" data-child="voice-start">● 녹음 시작</button><button type="button" data-child="voice-stop">■ 녹음 종료</button><button type="button" data-child="voice-retry">↻ 녹음 저장 재시도</button><button type="button" data-child="voice-download">↓ 미저장 녹음 백업</button><button type="button" data-child="voice-import">↑ 녹음 백업 복원</button><input id="cqVoiceManifestImport" type="file" accept=".json,.cqvoice.json,application/json" hidden><input id="cqVoiceImport" type="file" accept="audio/webm,audio/mp4,audio/ogg" hidden></div><div id="cqVoicePlayback"></div><p class="muted" id="cqVoiceStatus">말하기 녹음은 필수입니다. 녹음 완료 후 이 기기의 IndexedDB에 원본을 저장합니다. 저장에 실패하면 제출할 수 없으며, 최종 제출 시 서버 업로드를 시도합니다. 업로드가 실패하면 제출되지 않습니다.</p><div class="submission-bar" data-learn-section="submit"><span id="cqDraftStatus" role="status">답안은 입력 즉시 이 기기에 저장됩니다.</span><button type="button" data-child="draft-retry">답안 저장 재시도</button><button type="submit" disabled title="서버 PDF 연결 및 접근 권한 검증 후 활성화">최종 제출 (PDF 연결 대기)</button></div></form>`;
    const feedback=submitted?.feedback_released?`<h4>부모 피드백</h4><p>${escape(submitted.feedback||'')}</p>`:'<p>부모 피드백 검토 중입니다.</p>';
    detail.innerHTML=`<div class="book"><h3>${escape(c.chapter_title)}</h3>${submitted?`<p>제출 완료 · ${escape(submitted.submitted_at||'')}</p>${feedback}<button data-child="feedback" data-uuid="${escape(c.chapter_uuid)}">피드백 새로고침</button>`:form}</div>`;
    if(submitted){clearDraft(viewUid,c.chapter_uuid);clearRecovery(viewUid,c.chapter_uuid)}
    if(submitted)await retryConfirmedCleanup(viewUid,c.chapter_uuid,viewGeneration);
    else if(restoreDraft(viewUid,c.chapter_uuid,el('cqChildWork'))){
      status('이 기기에 임시 저장된 답변을 복원했습니다.');
    }
    if(!submitted){loadServerPdf(c.chapter_uuid,viewUid,viewGeneration);await restoreDurableVoice(viewUid,c.chapter_uuid,viewGeneration);}
   }
  }catch(err){
    // Ignore errors from a view request belonging to a previous login session.
    if(!viewContext||(session&&session.uid===viewContext.uid&&childGeneration===viewContext.generation&&childApi===viewContext.api))status(err.message);
  }finally{busy=false;if(b.isConnected)b.disabled=false}
 });
 // Autosave only the current authenticated child's form; never store credentials.
 function saveCurrentDraft(e){
   const form=e.target.closest?.('#cqChildWork');
   if(!form||!session||mode!=='student')return;
   try{const result=writeDraft(session.uid,form.dataset.uuid,form);const saved=document.getElementById('cqDraftStatus');if(saved)saved.textContent='이 기기에 답안 자동 저장됨'+(result?.recovered?' · 이전 손상 자료는 복구 사본으로 보존됨':'');}
   catch(error){const saved=document.getElementById('cqDraftStatus');if(saved)saved.textContent='답안 저장 실패 · 화면을 닫지 말고 기기 저장 공간을 확인하세요.';status('임시저장 실패: '+error.message)}
 }
 document.addEventListener('click',event=>{
  const form=document.getElementById('cqChildWork');if(!form||!session||mode!=='student')return;
  const jump=event.target.closest('[data-learn-jump]');if(jump){form.querySelector('[data-learn-section="'+jump.dataset.learnJump+'"]')?.scrollIntoView({behavior:'smooth',block:'start'});return;}
  const reveal=event.target.closest('[data-word-reveal]');if(reveal){const target=form.querySelector('[data-word-meaning="'+reveal.dataset.wordReveal+'"]');target.hidden=!target.hidden;reveal.setAttribute('aria-expanded',String(!target.hidden));const done=form.querySelector('[data-word-done="'+reveal.dataset.wordReveal+'"]');if(!target.hidden){done.checked=true;done.dispatchEvent(new Event('change',{bubbles:true}));}return;}
  const speak=event.target.closest('[data-word-speak]');if(speak){if(!window.speechSynthesis){status('이 기기에서 단어 듣기를 지원하지 않습니다.');return;}const utterance=new SpeechSynthesisUtterance(speak.dataset.wordSpeak);utterance.lang='en-US';speechSynthesis.cancel();speechSynthesis.speak(utterance);}
 });
 document.addEventListener('input',saveCurrentDraft);
 document.addEventListener('change',saveCurrentDraft);
 document.addEventListener('submit',async e=>{
   if(e.target.id!=='cqChildWork')return;
   e.preventDefault();
   if(busy||mode!=='student'||!session||!childApi)return;
   const form=e.target,uuid=form.dataset.uuid;
   if(form.dataset.pdfVerified!=='true'){status('원본 PDF 연결이 완료된 뒤 제출하세요.');return;}
   const chapter=chapters.find(c=>c.chapter_uuid===uuid);
   if(!chapter){status('배정되지 않은 챕터입니다.');return;}
   const questions=chapter.questions||[];
   const answers=[];
   for(let i=0;i<questions.length;i++){
     const input=form.querySelector(`[name="cqAnswer${i}"]:checked`)||form.querySelector(`textarea[name="cqAnswer${i}"]`);
     if(!input||!String(input.value).trim()){status((i+1)+'번 문제에 답변해 주세요.');return;}
     answers.push(input.value);
   }
   const essay=form.elements.namedItem('essay')?.value?.trim();
   const speaking=form.elements.namedItem('speaking')?.value?.trim();
   if(!form.elements.namedItem('readComplete')?.checked||!essay||!speaking){status('읽기 완료, 독후감, 말하기 대본을 모두 작성하세요.');return;}
   if(voiceRecorder?.state==='recording'){status('녹음을 종료한 뒤 제출하세요.');return;}
   if(voiceSavePending){status('녹음 원본 저장이 끝난 뒤 제출하세요.');return;}
   if(unsavedVoice?.uid===session.uid&&unsavedVoice?.uuid===uuid){status('녹음 원본 저장이 완료되지 않았습니다. 녹음 저장 재시도를 눌러주세요.');return;}
   if(voiceBlob&&voiceChapter!==uuid){status('현재 챕터와 녹음 파일이 일치하지 않습니다.');return;}
   if(!voiceBlob&&!readRecovery(session.uid,uuid)){status('말하기 녹음을 완료한 뒤 제출하세요.');return;}
   if(!confirm('제출 후에는 답변을 수정할 수 없습니다. 제출할까요?'))return;
   // Persist the exact answers before any network request: an aborted request,
   // logout, or lost response must not discard a completed answer draft.
   try{writeDraft(session.uid,uuid,form)}
   catch(error){status('답변 임시저장 실패로 제출을 중단했습니다: '+error.message);return;}
   try{await childAccessToken()}catch(error){status(error.message);return;}
   const context=childContext();
   const submitController=new AbortController();activeChildSubmit=submitController;
   busy=true;const button=form.querySelector('[type="submit"]');if(button)button.disabled=true;
   try{
     const existing=await childApi.submission(uuid,{signal:submitController.signal});
     assertChildContext(context);
     if(Array.isArray(existing)?existing.length:!!existing){
       try{submissionGate.markConfirmed(context.uid,uuid)}catch(err){console.warn('Submission marker unavailable:',err?.name||'UNKNOWN');}
       // The previous submit may have committed while its response was lost.
       // Only a confirmed server submission permits local recovery cleanup.
       uploadedAudio.delete(session.uid+'/'+uuid);
       clearRecovery(session.uid,uuid);
       clearDraft(session.uid,uuid);
       const audioCleanupOk=await cleanupConfirmedAudio(context.uid,uuid,context);
       assertChildContext(context);
       voiceBlob=null;voiceChapter=null;
       status('서버에 이미 제출된 답변이 확인되었습니다. 중복 제출하지 않았습니다.'+(audioCleanupOk?'':' 이 기기의 녹음 파일 정리는 실패했습니다. 저장 공간을 확인하세요.'));
       const detail=el('cqChildDetail');
       if(detail)detail.innerHTML='<p>제출 완료. 피드백은 부모 검토 후 공개됩니다.</p><button data-child="feedback" data-uuid="'+escape(uuid)+'">피드백 확인</button>';
       return;
     }
     const pending=readRecovery(context.uid,uuid);
     let confirmedAudio=false;
     if(pending){
       // An upload intent is not evidence of a successful upload. Verify on server.
       confirmedAudio=await verifyExistingAudio(context.uid,uuid,pending.ext,pending.sha256);
       assertChildContext(context);
       if(confirmedAudio)writeRecovery(context.uid,uuid,pending.ext,'uploaded',pending.sha256);
       else if(pending.phase!=='uploading')throw Error('이전 녹음 파일을 서버에서 확인하지 못했습니다. 제출을 중단합니다.');
       else if(!voiceBlob)throw Error('이전 녹음 업로드가 완료되지 않았습니다. 녹음 데이터가 남아 있지 않아 자동 복구할 수 없습니다.');
     }
     if(voiceBlob&&!confirmedAudio){
       if(voiceBlob.size>10485760)throw Error('녹음 파일은 10MB 이하여야 합니다.');
       const config=studentProject();
       if(!config?.url||!config?.anonKey)throw Error('Supabase 프로젝트 설정이 없습니다.');
       const ext=voiceBlob.type.includes('mp4')?'mp4':voiceBlob.type.includes('ogg')?'ogg':'webm';
       if(pending&&pending.ext!==ext)throw Error('이전 업로드 시도와 녹음 형식이 다릅니다. 안전을 위해 제출을 중단합니다.');
       const sha256=await audioSha256(voiceBlob);
       assertChildContext(context);
       if(pending&&pending.sha256!==sha256)throw Error('기존 업로드 시도와 새 녹음의 내용이 다릅니다. 안전을 위해 제출을 중단합니다.');
       const path=context.uid+'/'+uuid+'.'+ext;
       // If no durable prior intent exists, a 409 must never adopt an unknown object.
       const hadPriorIntent=!!pending;
       // Write durable intent BEFORE the network call. A lost success response
       // can then be recovered by verifying this exact object on next login.
       writeRecovery(context.uid,uuid,ext,'uploading',sha256);
       const uploadController=new AbortController();activeChildUpload=uploadController;
       const upload=await fetch(config.url+'/storage/v1/object/cq-v4-speaking/'+path,{
         method:'POST',headers:{apikey:config.anonKey,Authorization:'Bearer '+session.token,
           'Content-Type':voiceBlob.type,'x-upsert':'false'},
         body:voiceBlob,signal:uploadController.signal
       });
       assertChildContext(context);
       if(activeChildUpload===uploadController)activeChildUpload=null;
       if(!upload.ok){
         if(upload.status===409){
           if(!hadPriorIntent)throw Error('이전에 기록되지 않은 녹음 파일이 서버에 있습니다. 안전을 위해 재사용하지 않습니다.');
           // Reuse only when this account/chapter has a durable prior intent
           // and the exact server object can be independently verified.
           confirmedAudio=await verifyExistingAudio(context.uid,uuid,ext,sha256);
           assertChildContext(context);
           if(!confirmedAudio)throw Error('기존 녹음 파일을 확인하지 못했습니다. 덮어쓰지 않고 제출을 중단합니다.');
         }else{
           const detail=await upload.json().catch(()=>({}));
           throw Error('녹음 업로드 실패: '+(detail.message||upload.status));
         }
       }else confirmedAudio=true;
       if(confirmedAudio){uploadedAudio.add(context.uid+'/'+uuid);writeRecovery(context.uid,uuid,ext,'uploaded',sha256);}
     }
     if(!confirmedAudio)throw Error('서버에 녹음 파일이 확인되지 않아 제출할 수 없습니다.');
     assertChildContext(context);
     await childApi.submit(uuid,{readComplete:true,answers,essay,speaking,hasAudio:confirmedAudio,wordsReviewed:[...form.querySelectorAll('[data-word-done]:checked')].map(x=>Number(x.dataset.wordDone))},{signal:submitController.signal});
     assertChildContext(context);
     try{submissionGate.markConfirmed(context.uid,uuid)}catch(err){console.warn('Submission marker unavailable:',err?.name||'UNKNOWN');}
     uploadedAudio.delete(session.uid+'/'+uuid);clearRecovery(session.uid,uuid);clearDraft(session.uid,uuid);const audioCleanupOk=await cleanupConfirmedAudio(context.uid,uuid,context);assertChildContext(context);voiceBlob=null;voiceChapter=null;status('제출 완료. 부모 피드백은 공개 후 확인할 수 있습니다.'+(audioCleanupOk?'':' 이 기기의 녹음 파일 정리는 실패했습니다. 저장 공간을 확인하세요.'));
     const detail=el('cqChildDetail');if(detail)detail.innerHTML='<p>제출 완료. 피드백은 부모 검토 후 공개됩니다.</p><button data-child="feedback" data-uuid="'+escape(uuid)+'">피드백 확인</button>';
   }catch(err){
     if(session?.uid===context.uid&&childGeneration===context.generation){
       status('제출 실패: '+err.message+(readRecovery(context.uid,uuid)?' · 서버에 업로드된 녹음 기록이 보존되었습니다. 다시 로그인해 제출할 수 있습니다.':''));
     }
   }finally{if(activeChildSubmit===submitController)activeChildSubmit=null;if(session?.uid===context.uid&&childGeneration===context.generation){activeChildUpload=null;busy=false;if(button?.isConnected)button.disabled=false}}
 });
 // Never retain a child token in localStorage; a page reload requires login again.
 const initialRender=render;render=function(){initialRender()};
})();
