/* Parent-only local preparation. No network request, upload, approval or assignment. */
(()=>{
 let pending=null,busy=false;
 const element=id=>document.getElementById(id);
 const notice=text=>{const target=element('cqRangeStatus');if(target)target.textContent=text;};
 const hash=async file=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await file.arrayBuffer()))).map(n=>n.toString(16).padStart(2,'0')).join('');
 const fence=(c,key)=>{if(mode!=='parent'||!parentUnlocked||chapter()!==c||pdfContext()!==key)throw Error('부모 화면 또는 챕터가 변경되어 작업을 중단했습니다.');};
 function invalidate(){pending=null;const ready=element('cqRangeConfirmed'),button=element('cqRangePrepare');if(ready){ready.checked=false;ready.disabled=true;}if(button)button.disabled=true;}
 document.addEventListener('input',event=>{if(['cqRangeStart','cqRangeEnd','cqRangeTitle'].includes(event.target.id)){invalidate();notice('범위를 변경했습니다. 다시 미리 보고 확인하세요.');}});
 document.addEventListener('change',event=>{if(event.target.id==='cqRangeConfirmed'&&element('cqRangePrepare'))element('cqRangePrepare').disabled=!pending||!event.target.checked;});
 document.addEventListener('click',async event=>{
  const button=event.target.closest('[data-pdf-range]');if(!button||busy)return;
  if(mode!=='parent'||!parentUnlocked){notice('부모 관리자 화면에서 준비하세요.');return;}
  const c=chapter(),b=book(),key=pdfContext(),action=button.dataset.pdfRange;
  if(!c?.pdfStored||c.readerType==='txt'){notice('PDF 원본을 먼저 등록하거나 기존 서버 PDF를 불러오세요. TXT 원본은 그대로 보존됩니다.');return;}
  busy=true;document.querySelectorAll('[data-pdf-range]').forEach(item=>item.disabled=true);let doc=null;
  try{
   const original=await pdfGet(key);fence(c,key);if(!original)throw Error('이 기기에 PDF 원본이 없습니다. 기존 서버 원본을 먼저 불러오세요.');
   if(action==='pick-start'||action==='pick-end'){
    const viewer=element('cqParentPdfViewer'),page=Number(viewer?.dataset.currentPage);
    if(!viewer||viewer.hidden||viewer.dataset.sourceKey!==key||!Number.isSafeInteger(page)||page<1)throw Error('원본 미리보기를 열고 페이지 표시가 끝난 뒤 선택하세요.');
    const input=element(action==='pick-start'?'cqRangeStart':'cqRangeEnd');input.value=String(page);input.dispatchEvent(new Event('input',{bubbles:true}));notice('원본 파일 '+page+'쪽을 '+(action==='pick-start'?'시작':'끝')+'으로 선택했습니다. 범위 미리보기로 확인하세요.');
   }else if(action==='inspect'){
    invalidate();notice('원본 PDF의 페이지와 목차를 확인하는 중…');
    doc=await pdfjsLib.getDocument({data:new Uint8Array(await original.arrayBuffer()),isEvalSupported:false}).promise;
    const metadata=await doc.getMetadata().catch(()=>null),outline=await doc.getOutline();fence(c,key);
    const items=[];
    async function visit(nodes){for(const node of nodes||[]){if(items.length>=100)return;let page=null;try{const dest=typeof node.dest==='string'?await doc.getDestination(node.dest):node.dest;if(Array.isArray(dest)){page=(typeof dest[0]==='number'?dest[0]:await doc.getPageIndex(dest[0]))+1;}}catch{}items.push({title:String(node.title||'').slice(0,300),page});await visit(node.items);}}
    await visit(outline);fence(c,key);
    const info={pageCount:doc.numPages,title:String(metadata?.info?.Title||'').slice(0,500),outline:items};
    c.pdfInspection=info;if(!save())throw Error('PDF 구성 정보를 기기에 저장하지 못했습니다.');
    element('cqPdfStructure').textContent='파일 '+info.pageCount+'쪽 · PDF 내부 제목: '+(info.title||'없음')+'\n'+(items.length?items.map(x=>x.title+(x.page?' · 파일 '+x.page+'쪽':'')).join('\n'):'PDF 목차 정보가 없습니다. Chapter 1 범위를 자동으로 추정하지 않습니다.');
    for(const id of ['cqRangeStart','cqRangeEnd'])element(id).max=String(info.pageCount);
    notice('파일의 첫 페이지가 1쪽입니다. 목차와 원문을 보고 시작·끝 쪽을 선택하세요.');
   }else if(action==='preview'){
    invalidate();const start=element('cqRangeStart').value,end=element('cqRangeEnd').value,title=element('cqRangeTitle').value.trim();if(!title||title.length>150)throw Error('학습 제목을 1~150자로 입력하세요.');
    notice('원본을 보존하고 선택 범위만 미리 만드는 중…');
    const sourceHash=await hash(original),result=await CQPdfRange.extract(new Uint8Array(await original.arrayBuffer()),start,end,{title});fence(c,key);
    const file=new File([result.bytes],title+'.pdf',{type:'application/pdf'});
    doc=await pdfjsLib.getDocument({data:result.bytes.slice(0),isEvalSupported:false}).promise;let text='';
    for(let n=1;n<=doc.numPages;n++){const content=await(await doc.getPage(n)).getTextContent();text+=content.items.map(x=>x.str).join(' ')+'\n';if(text.length>500000)throw Error('선택 범위의 텍스트가 너무 깁니다. 범위를 줄이세요.');}
    fence(c,key);const target=element('cqRangePreview');target.hidden=false;const originalViewer=element('cqParentPdfViewer');if(originalViewer)originalViewer.hidden=true;
    if(!await showChapterPDF('cqRangePreview',file))throw Error('선택 범위의 화면 표시를 확인하지 못했습니다. 다시 미리 보세요.');fence(c,key);
    pending={c,b,key,sourceHash,file,text,title,start:result.start,end:result.end,total:result.total};
    element('cqRangeConfirmed').disabled=false;
    notice('원본 파일 '+result.start+'–'+result.end+'쪽 ('+result.count+'쪽)만 미리 봅니다. 범위가 맞는지 확인한 뒤 이 기기에 등록하세요.');
   }else if(action==='prepare'){
    if(!pending||pending.c!==c||pending.key!==key||!element('cqRangeConfirmed').checked)throw Error('선택 범위를 다시 미리 보고 확인란을 체크하세요.');
    const item=pending;
    if(Number(element('cqRangeStart').value)!==item.start||Number(element('cqRangeEnd').value)!==item.end||element('cqRangeTitle').value.trim()!==item.title)throw Error('선택 범위가 바뀌었습니다. 다시 미리 보세요.');
    if(await hash(original)!==item.sourceHash)throw Error('원본 파일이 변경되었습니다. 다시 미리 보세요.');fence(c,key);
    const lessonTitle=item.title+' · PDF '+item.start+'–'+item.end+'쪽';
    const existing=b.chapters.find(x=>x.title===lessonTitle&&x.pdfRange?.sourceKey===key&&x.pdfRange?.sourceSHA256===item.sourceHash&&x.pdfRange?.start===item.start&&x.pdfRange?.end===item.end);
    if(existing){const existingKey=pdfKey(b.id,existing.id);if(!await pdfGet(existingKey))await pdfPut(existingKey,item.file);fence(c,key);selectedChapter=existing.id;if(!save()){selectedChapter=c.id;throw Error('기존 범위 자료를 선택한 상태를 저장하지 못했습니다.');}pending=null;render();setStatus('이미 준비한 같은 범위를 재사용했습니다. 기존 문제·승인·원본은 보존했습니다.');return;}
    const prepared={id:uid(),title:lessonTitle,source:item.text,questions:[],vocabulary:[],writingPrompt:'',speakingPrompt:'',pdfStored:true,pdfName:item.file.name,readerType:'pdf',pdfRange:{version:1,start:item.start,end:item.end,total:item.total,sourceKey:key,sourceSHA256:item.sourceHash,sourceName:original.name||c.title,sourceServerPdfUuid:c.serverPdfUuid||null,sourceProject:c.serverPdfOrigin||null}};
    const derivedKey=pdfKey(b.id,prepared.id);await pdfPut(derivedKey,item.file);const check=await pdfGet(derivedKey);if(!check||check.size!==item.file.size)throw Error('범위 PDF를 기기에 저장하지 못했습니다.');fence(c,key);
    b.chapters.push(prepared);selectedChapter=prepared.id;draft=null;if(!save()){b.chapters.pop();selectedChapter=c.id;throw Error('학습 자료 저장 실패. 기존 원본과 TXT는 보존했습니다.');}
    pending=null;render();setStatus('선택 범위만 이 기기에 등록했습니다. 원본은 재업로드하지 않았습니다. 문제 검토·승인 후 범위 PDF만 서버에 등록·배정하세요.'+(item.text.trim().length<250?' 스캔 PDF라면 해당 범위의 AI용 텍스트를 별도로 준비하세요.':''));
   }
  }catch(error){notice('범위 준비 실패: '+error.message);}
  finally{if(doc)await doc.destroy();busy=false;document.querySelectorAll('[data-pdf-range]').forEach(item=>item.disabled=item.dataset.pdfRange==='prepare'&&(!pending||!element('cqRangeConfirmed')?.checked));}
 });
})();
