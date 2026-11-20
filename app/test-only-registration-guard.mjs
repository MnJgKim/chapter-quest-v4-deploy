// Guardrail for isolated V4 TEST uploads. Pure validation; never performs server writes.
// Existing catalog UUIDs are protected regardless of matching chapter titles.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function validateIsolatedTestRegistration({testStudentUserId,targetStudentUserId,existingChapters,uploads,proposedChapterIds,proposedStoragePaths}){
 if(!uuid.test(testStudentUserId||'')||targetStudentUserId!==testStudentUserId)throw new Error('Only the explicitly identified V4 TEST account may be targeted');
 if(!Array.isArray(existingChapters)||!Array.isArray(uploads)||!Array.isArray(proposedChapterIds)||!Array.isArray(proposedStoragePaths)||uploads.length!==3||proposedChapterIds.length!==3||proposedStoragePaths.length!==3)throw new TypeError('Three complete isolated uploads required');
 const protectedIds=new Set(existingChapters.map(x=>x.chapterId));
 const protectedPaths=new Set(existingChapters.map(x=>x.storagePath));
 const ids=new Set(),paths=new Set(),hashes=new Set();
 for(let i=0;i<3;i++){
  const u=uploads[i],id=proposedChapterIds[i],path=proposedStoragePaths[i];
  if(!u||!['2-3.pdf','2-4.pdf','2-5.pdf'].includes(u.filename)||!/^([a-f0-9]{64})$/i.test(u.sha256||'')||hashes.has(u.sha256))throw new Error('Invalid or repeated test PDF');
  if(!uuid.test(id||'')||protectedIds.has(id)||ids.has(id))throw new Error('Existing or repeated chapter UUID');
  if(typeof path!=='string'||!path.startsWith('v4-test-only/'+testStudentUserId+'/')||path.includes('..')||protectedPaths.has(path)||paths.has(path))throw new Error('Unsafe test storage path');
  hashes.add(u.sha256);ids.add(id);paths.add(path);
 }
 if(new Set(uploads.map(x=>x.filename)).size!==3)throw new Error('Duplicate test filename');
 return {isolated:true,allowedTarget:testStudentUserId,existingChaptersUnchanged:true,productionWritesPerformed:0,executable:false};
}
