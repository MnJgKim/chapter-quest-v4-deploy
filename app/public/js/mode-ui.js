/* Stage 132 UI integration. Default stays local demo to preserve existing files. */
(()=>{
 const modeKey='cq_v4_student_mode_v1';let initialMode=state.books.length?'local-demo':'server';
 try{const saved=localStorage.getItem(modeKey);if(['server','local-demo'].includes(saved))initialMode=saved;else if(localStorage.getItem('cq-v4-dedicated-child-session-v1'))initialMode='server';}catch{}
 const gate=CQStudentMode132.createMode(initialMode);
 const oldStudentUI=studentUI;
 studentUI=function(){return gate.isServer()?CQStudentMode132.serverOnlyMarkup():oldStudentUI()};
 const previousRender=render;
 render=function(){
   previousRender();
   const studentScreen=mode==='student';
   const selector=document.getElementById('student');
   if(selector){const label=selector.closest('label');if(label){label.hidden=studentScreen&&gate.isServer();label.style.display=studentScreen&&gate.isServer()?'none':'';}}
   if(!studentScreen)return;
   const panel=document.getElementById('cqChildAccount');
   if(!panel)return;
   const switcher=document.createElement('section');
   switcher.className='card';switcher.id='cqStage132ModeSwitch';
   switcher.innerHTML='<h2>학습 저장 방식</h2><div class="row"><button type="button" data-stage132="local-demo">기기 데모</button><button type="button" data-stage132="server">학생 서버 학습</button></div><p class="muted" id="cqStage132ModeStatus"></p>';
   panel.before(switcher);
   const s=switcher.querySelector('#cqStage132ModeStatus');
   s.textContent=gate.isServer()?'학생 본인의 계정으로 배정된 챕터를 학습합니다.':'기기 데모: 로컬 학습 기록이며 서버 동기화되지 않습니다.';
   for(const b of switcher.querySelectorAll('[data-stage132]')){
     b.classList.toggle('active',b.dataset.stage132===gate.get());
   }
   // The existing server account panel remains available only in server mode.
   panel.hidden=!gate.isServer();
 };
 document.addEventListener('click',event=>{
   const b=event.target.closest?.('[data-stage132]');if(!b)return;
   event.preventDefault();
   if(mode!=='student')return;
   const next=b.dataset.stage132;
   if(next===gate.get())return;
   if(window.CQStudentNavigation&&!window.CQStudentNavigation.leave())return;
   gate.set(next);try{localStorage.setItem(modeKey,next)}catch{}view='home';tab='read';selectedBook='';selectedChapter='';audioBlob=null;
   render();
 });
 // Stop accidental demo actions when the server-only screen is selected.
 document.addEventListener('click',event=>{
   if(mode!=='student'||!gate.isServer())return;
   if(event.target.closest?.('[data-act]')){event.stopImmediatePropagation();event.preventDefault();}
 },true);
 window.CQStage132Mode=gate;
 render();
})();
