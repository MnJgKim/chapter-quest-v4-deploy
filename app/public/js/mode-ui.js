/* Dedicated student tablets: server learning is the only visible student workflow.
 * Existing local demo data is retained in storage for recovery, never deleted.
 * Parent management is unaffected.
 */
(()=>{
 const previousRender=render;
 studentUI=function(){return CQStudentMode132.serverOnlyMarkup()};
 render=function(){
  previousRender();
  const studentScreen=mode==='student';
  const selector=document.getElementById('student');
  if(selector){
   const label=selector.closest('label');
   if(label){label.hidden=studentScreen;label.style.display=studentScreen?'none':'';}
  }
  const panel=document.getElementById('cqChildAccount');
  if(panel)panel.hidden=false;
 };
 // Remove obsolete mode preference, not the actual local demo records.
 try{localStorage.setItem('cq_v4_student_mode_v1','server')}catch(_){}
 window.CQStage132Mode=CQStudentMode132.createMode('server');
 render();
})();
