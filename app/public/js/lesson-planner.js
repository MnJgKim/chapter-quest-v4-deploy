/* Chapter Quest V4: deterministic Monday/Thursday lesson planner.
 * Pure module: does not publish assignments, change submissions or bypass server RLS.
 * Dates are calendar dates in Asia/Seoul (YYYY-MM-DD), not UTC timestamps.
 */
(function(root){
 'use strict';
 const DAY_MS=86400000;
 function parseDate(value){
  if(typeof value!=='string'||!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(value))throw Error('Invalid lesson date');
  const [y,m,d]=value.split('-').map(Number);
  const date=new Date(Date.UTC(y,m-1,d));
  if(date.toISOString().slice(0,10)!==value)throw Error('Invalid lesson date');
  return date;
 }
 function dateKey(date){return date.toISOString().slice(0,10);}
 function nextStudyDate(date){
  const day=date.getUTCDay();
  let days=1;
  while(![1,4].includes(new Date(date.getTime()+days*DAY_MS).getUTCDay()))days++;
  return new Date(date.getTime()+days*DAY_MS);
 }
 function plan({startDate='2026-11-23',chapters=[]}={}){
  let date=parseDate(startDate);
  if(![1,4].includes(date.getUTCDay()))throw Error('Start date must be Monday or Thursday');
  if(!Array.isArray(chapters))throw Error('Chapters must be an array');
  const seen=new Set();
  return chapters.map((chapter,index)=>{
   const id=chapter?.chapter_uuid||chapter?.chapter_id||chapter?.id;
   if(typeof id!=='string'||!id||seen.has(id))throw Error('Chapter ID missing or duplicated');
   seen.add(id);
   const item={chapterId:id,chapterTitle:String(chapter.chapter_title||chapter.title||'Chapter '+(index+1)),lessonDate:dateKey(date),weekday:date.getUTCDay()===1?'월':'목',status:'planned'};
   date=nextStudyDate(date);
   return item;
  });
 }
 root.CQLessonPlanner=Object.freeze({plan});
 if(typeof module==='object'&&module.exports)module.exports=root.CQLessonPlanner;
})(typeof window==='object'?window:globalThis);
