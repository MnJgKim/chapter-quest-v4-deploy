(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;root.CQVoiceManifest=api;})(typeof globalThis!=='undefined'?globalThis:this,function(){
 'use strict';
 const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
 const HEX=/^[0-9a-f]{64}$/;
 const MIMES=new Set(['audio/webm','audio/mp4','audio/ogg']);
 async function digest(blob){const bytes=await blob.arrayBuffer();const hash=await crypto.subtle.digest('SHA-256',bytes);return Array.from(new Uint8Array(hash),b=>b.toString(16).padStart(2,'0')).join('');}
 async function create(blob,uid,chapterUuid){if(!UUID.test(uid)||!UUID.test(chapterUuid))throw Error('학생 또는 챕터 ID가 올바르지 않습니다.');if(!blob||!MIMES.has(blob.type)||blob.size<1||blob.size>10485760)throw Error('지원하지 않는 녹음 파일입니다.');return {format:'chapterquest-voice-backup',version:1,uid,chapterUuid,mime:blob.type,size:blob.size,sha256:await digest(blob),createdAt:new Date().toISOString()};}
 async function verify(blob,manifest,uid,chapterUuid){if(!manifest||manifest.format!=='chapterquest-voice-backup'||manifest.version!==1)throw Error('녹음 백업 정보가 올바르지 않습니다.');if(!UUID.test(uid)||!UUID.test(chapterUuid)||manifest.uid!==uid||manifest.chapterUuid!==chapterUuid)throw Error('현재 학생 또는 챕터의 녹음이 아닙니다.');if(!blob||!MIMES.has(blob.type)||blob.size<1||blob.size>10485760||manifest.mime!==blob.type||manifest.size!==blob.size)throw Error('녹음 파일 형식 또는 크기가 일치하지 않습니다.');if(typeof manifest.sha256!=='string'||!HEX.test(manifest.sha256)||await digest(blob)!==manifest.sha256)throw Error('녹음 파일 무결성 검증에 실패했습니다.');return true;}
 return {create,verify,digest};
});
