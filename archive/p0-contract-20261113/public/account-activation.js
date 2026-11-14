// Supabase invite/recovery callbacks keep their token only in this module's memory.
(()=>{
const fragment=new URLSearchParams(location.hash.slice(1));
if(fragment.has('access_token')||fragment.has('refresh_token')) {
 const token=fragment.get('access_token');const type=fragment.get('type');
 history.replaceState(null,'',location.pathname+location.search);
 if(token&&['invite','recovery'].includes(type)) {
 const activate=()=>{
  const section=document.createElement('section');section.className='card';
  section.innerHTML='<h2>학생 계정 비밀번호 설정</h2><p>비밀번호 설정 후 학생 계정으로 로그인하고 부모 초대코드를 입력하세요.</p><form id="cqActivate"><label>Supabase 프로젝트 URL<input name="url" type="url" required></label><label>프로젝트 공개 키<input name="key" required></label><label>새 비밀번호 (12자 이상)<input name="password" type="password" minlength="12" autocomplete="new-password" required></label><button type="submit">비밀번호 설정</button><p role="status"></p></form>';
  document.querySelector('main').prepend(section);
  const form=section.querySelector('form');const status=form.querySelector('[role="status"]');
  let stored=null;try{stored=JSON.parse(localStorage.getItem('cq_v4_cloud_project')||'null');}catch{}
  form.elements.namedItem('url').value=stored?.url||window.CQ_PUBLIC_CONFIG?.supabaseUrl||'';
  form.elements.namedItem('key').value=stored?.anonKey||window.CQ_PUBLIC_CONFIG?.supabaseAnonKey||'';
  form.addEventListener('submit',async event=>{
   event.preventDefault();const button=form.querySelector('button');button.disabled=true;
   const url=form.elements.namedItem('url').value.trim().replace(/\/$/,'');const key=form.elements.namedItem('key').value.trim();const password=form.elements.namedItem('password').value;
   try {
    if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url)||!key||password.length<12)throw Error('프로젝트 설정과 비밀번호를 확인하세요.');
    const headers={apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'};
    const verified=await fetch(url+'/auth/v1/user',{headers});if(!verified.ok)throw Error('초대 링크가 만료됐거나 유효하지 않습니다.');
    const response=await fetch(url+'/auth/v1/user',{method:'PUT',headers,body:JSON.stringify({password})});if(!response.ok)throw Error('비밀번호 설정에 실패했습니다. 새 초대 링크가 필요할 수 있습니다.');
    localStorage.setItem('cq_v4_cloud_project',JSON.stringify({url,anonKey:key}));
    form.elements.namedItem('password').value='';status.textContent='설정 완료. 페이지를 새로고침한 뒤 학생 계정으로 로그인하세요.';
   } catch(error) {status.textContent=error.message;button.disabled=false;}
  });
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',activate,{once:true});else activate();
 }
}
})();
