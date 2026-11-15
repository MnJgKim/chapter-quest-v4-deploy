(function(){
 const show=()=>{const app=document.getElementById('app');if(!app||app.children.length)return;const section=document.createElement('section');section.className='card';const text=document.createElement('p');text.textContent='학습 화면을 불러오지 못했습니다. 연결을 확인하고 다시 불러와 주세요. 브라우저 저장 자료는 보존됩니다.';const retry=document.createElement('button');retry.type='button';retry.textContent='화면 다시 불러오기';retry.addEventListener('click',()=>location.reload());section.append(text,retry);app.append(section);};
 window.addEventListener('DOMContentLoaded',show,{once:true});
})();
