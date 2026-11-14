/* Render UTF-8 TXT visually into a PDF accepted by the existing private PDF backend.
   The original TXT remains in IndexedDB; this conversion makes no network requests. */
(function(root){
 'use strict';
 async function convert(file){
  if(!file||file.size<1||file.size>1024*1024)throw Error('TXT는 1MB 이하로 등록하세요.');
  const text=new TextDecoder('utf-8',{fatal:true}).decode(await file.arrayBuffer());
  if(!text.trim())throw Error('TXT 원문이 비어 있습니다.');
  if(text.length>250000)throw Error('TXT 원문이 너무 깁니다. 챕터별로 나눠 주세요.');
  const canvas=document.createElement('canvas');canvas.width=900;canvas.height=1273;
  const ctx=canvas.getContext('2d');if(!ctx)throw Error('이 기기에서 TXT PDF 변환을 지원하지 않습니다.');
  ctx.font='20px sans-serif';
  const lines=[];
  for(const line of text.replace(/\r\n?/g,'\n').split('\n')){
   let current='';
   for(const char of line){if(ctx.measureText(current+char).width>788&&current){lines.push(current);current='';}current+=char;}
   lines.push(current);
  }
  const images=[];let total=0;
  for(let start=0;start<lines.length;start+=38){
   ctx.fillStyle='white';ctx.fillRect(0,0,900,1273);ctx.fillStyle='#17233a';ctx.font='20px sans-serif';ctx.textBaseline='top';
   lines.slice(start,start+38).forEach((line,i)=>ctx.fillText(line,56,58+i*30));
   const blob=await new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(Error('TXT 변환에 실패했습니다.')),'image/jpeg',0.92));
   const bytes=new Uint8Array(await blob.arrayBuffer());total+=bytes.length;
   if(total>49*1024*1024)throw Error('변환한 PDF가 너무 큽니다. 챕터를 나누세요.');
   images.push(bytes);await new Promise(resolve=>setTimeout(resolve,0));
  }
  const enc=new TextEncoder(),chunks=[],offsets=[0];let size=0;
  const append=v=>{const bytes=typeof v==='string'?enc.encode(v):v;chunks.push(bytes);size+=bytes.length;};
  const object=(id,body)=>{offsets[id]=size;append(id+' 0 obj\n');append(body);append('\nendobj\n');};
  append('%PDF-1.4\n');object(1,'<< /Type /Catalog /Pages 2 0 R >>');object(2,'<< /Type /Pages /Count '+images.length+' /Kids ['+images.map((_,i)=>(3+i*3)+' 0 R').join(' ')+'] >>');
  images.forEach((bytes,i)=>{
   const id=3+i*3,command='q 595 0 0 842 0 0 cm /Original Do Q';
   object(id,'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /XObject << /Original '+(id+2)+' 0 R >> >> /Contents '+(id+1)+' 0 R >>');
   object(id+1,'<< /Length '+enc.encode(command).length+' >>\nstream\n'+command+'\nendstream');
   offsets[id+2]=size;append((id+2)+' 0 obj\n<< /Type /XObject /Subtype /Image /Width 900 /Height 1273 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length '+bytes.length+' >>\nstream\n');append(bytes);append('\nendstream\nendobj\n');
  });
  const xref=size;append('xref\n0 '+offsets.length+'\n0000000000 65535 f \n');for(const offset of offsets.slice(1))append(String(offset).padStart(10,'0')+' 00000 n \n');append('trailer\n<< /Size '+offsets.length+' /Root 1 0 R >>\nstartxref\n'+xref+'\n%%EOF\n');
  return new File(chunks,String(file.name||'chapter.txt').replace(/\.txt$/i,'')+'.pdf',{type:'application/pdf'});
 }
 root.CQTextPDF=Object.freeze({convert});
})(globalThis);
