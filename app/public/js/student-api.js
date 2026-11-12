/* Chapter Quest V4: student-only RPC transport. Requires a child Supabase Auth session.
   Server RLS/RPC is the security boundary, not this JavaScript. */
(function(root){
  function createStudentAPI({url,anonKey,getAccessToken,fetchImpl=fetch}){
    if(!(globalThis.CQOrigin?.allows(url||'')??/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url||''))) throw Error('Invalid Supabase URL');
    if(!anonKey||typeof getAccessToken!=='function')throw Error('Missing public key or token provider');
    async function rpc(name,args={},options={}){
      const signal=options.signal;
      if(signal?.aborted)throw new DOMException('학생 요청이 취소되었습니다.','AbortError');
      const token=await getAccessToken();
      if(signal?.aborted)throw new DOMException('학생 요청이 취소되었습니다.','AbortError');
      if(!token)throw Error('Student login required');
      const response=await fetchImpl(url+'/rest/v1/rpc/'+name,{
        method:'POST',headers:{apikey:anonKey,Authorization:'Bearer '+token,'Content-Type':'application/json'},
        body:JSON.stringify(args),signal
      });
      if(!response.ok){const detail=await response.json().catch(()=>({}));throw Error('Student request failed ('+response.status+'): '+(detail.message||'Access denied'))}
      return response.json();
    }
    async function assignedChapters(){
      const rows=await rpc('cq_v4_my_chapters');
      if(!Array.isArray(rows))throw Error('배정 챕터 목록 형식을 확인해 주세요.');
      return rows.map(row=>{
        if(!row||!/^[0-9a-f-]{36}$/i.test(row.chapter_uuid||'')||!Array.isArray(row.questions)||row.questions.length<1||row.questions.length>30)throw Error('배정된 학습 자료 형식을 확인해 주세요.');
        const questions=row.questions.map(q=>{
          if(!q||!['mc','inference','critical','short','comprehension'].includes(q.kind)||typeof q.text!=='string'||!q.text.trim())throw Error('문제 자료를 확인해 주세요.');
          if(q.kind==='mc'){
            if(!Array.isArray(q.options)||q.options.length<2||q.options.length>6||q.options.some(o=>typeof o!=='string'||!o.trim()))throw Error('객관식 선택지 자료를 확인해 주세요.');
            return {kind:q.kind,text:q.text,options:[...q.options]};
          }
          return {kind:q.kind,text:q.text};
        });
        return {chapter_uuid:row.chapter_uuid,chapter_title:String(row.chapter_title||'학습 챕터'),questions};
      });
    }
    async function submit(chapterUuid,answers,options={}){
      const rows=await rpc('cq_v4_submit_answers',{p_chapter_uuid:chapterUuid,p_answers:answers},options);
      if(!Array.isArray(rows)||rows.length!==1||!rows[0]||rows[0].chapter_uuid!==chapterUuid||typeof rows[0].submitted_at!=='string'||!Number.isFinite(Date.parse(rows[0].submitted_at)))throw Error('제출 확인 응답이 올바르지 않습니다. 답안·녹음을 보존했습니다. 다시 시도하면 서버 제출 여부를 먼저 확인합니다.');
      return [{chapter_uuid:rows[0].chapter_uuid,submitted_at:rows[0].submitted_at}];
    }
    async function submission(chapterUuid,options={}){
      const rows=await rpc('cq_v4_my_submission',{p_chapter_uuid:chapterUuid},options);
      if(!Array.isArray(rows)||rows.length>1||rows.some(row=>!row||row.chapter_uuid!==chapterUuid||typeof row.submitted_at!=='string'||!Number.isFinite(Date.parse(row.submitted_at))||typeof row.feedback_released!=='boolean'||(row.feedback!==null&&typeof row.feedback!=='string')))throw Error('제출 상태 응답을 확인할 수 없습니다. 기존 답안·녹음을 보존하고 다시 시도하세요.');
      return rows.map(row=>({chapter_uuid:row.chapter_uuid,submitted_at:row.submitted_at,feedback_released:row.feedback_released,feedback:row.feedback_released?row.feedback:null}));
    }
    async function chapterActivities(chapterUuid,options={}){
      const rows=await rpc('cq_v4_my_chapter_activities',{p_chapter_uuid:chapterUuid},options);
      if(!Array.isArray(rows)||rows.length!==1)throw Error('챕터 학습 활동 응답을 확인하세요.');
      const row=rows[0];
      if(!row||!Array.isArray(row.vocabulary)||row.vocabulary.some(v=>!v||typeof v.word!=='string'||!v.word.trim()||typeof v.meaning!=='string'||(v.example!=null&&typeof v.example!=='string'))||typeof row.writing_prompt!=='string'||typeof row.speaking_prompt!=='string')throw Error('챕터 학습 활동 형식을 확인하세요. 기존 입력은 유지됩니다.');
      return [{vocabulary:row.vocabulary.map(v=>({word:v.word,meaning:v.meaning,example:v.example||''})),writing_prompt:row.writing_prompt,speaking_prompt:row.speaking_prompt}];
    }
    return Object.freeze({
      assignedChapters,
      chapterActivities,
      submit,
      submission
    });
  }
  root.CQStudentAPI=Object.freeze({createStudentAPI});
  if(typeof module!=='undefined')module.exports={createStudentAPI};
})(typeof window!=='undefined'?window:globalThis);
