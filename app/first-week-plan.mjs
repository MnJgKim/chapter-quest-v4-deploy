// Offline first-week plan. Does not infer student identity or write to Supabase.
export const FIRST_WEEK=Object.freeze([
 {student:'서우',date:'2026-11-23',weekday:1},
 {student:'서진',date:'2026-11-24',weekday:2},
 {student:'서우',date:'2026-11-25',weekday:3},
 {student:'서진',date:'2026-11-25',weekday:3},
 {student:'서우',date:'2026-11-26',weekday:4},
 {student:'서진',date:'2026-11-27',weekday:5}
]);
export function firstWeekReadiness({identities,scheduled}){
 if(!identities||!Array.isArray(scheduled)) throw new TypeError('Invalid input');
 const names=['서우','서진'];
 const identityIds=names.map(name=>identities[name]?.studentUserId).filter(Boolean);
 const sharedIdentity=identityIds.length!==new Set(identityIds).size;
 const findings=FIRST_WEEK.map(slot=>{
  const identity=identities[slot.student];
  const matching=scheduled.filter(r=>r.date===slot.date&&r.student===slot.student);
  const blockers=[];
  if(!identity||identity.approved!==true||identity.enrolled!==true||typeof identity.studentUserId!=='string'||!identity.studentUserId) blockers.push('approved-enrolled-identity-required');
  if(sharedIdentity) blockers.push('shared-student-identity');
  if(matching.length!==1) blockers.push(matching.length?'duplicate-slot':'missing-slot');
  if(matching.length===1){
   const r=matching[0];
   if(!identity||r.studentUserId!==identity.studentUserId) blockers.push('identity-mismatch');
   if(r.pdfReady!==true||r.pdfVerified!==true||r.activityPublished!==true||r.assigned!==true||r.released!==true) blockers.push('material-not-ready');
  }
  return {...slot,blockers,readyForDeviceTest:blockers.length===0};
 });
 return {findings,allReadyForDeviceTest:findings.every(f=>f.readyForDeviceTest),writesPerformed:0,deployable:false};
}
