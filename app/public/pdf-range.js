/* Extract a derived lesson PDF; the input bytes and original storage object are retained. */
(function(root){
 function validate(start,end,total){
  start=Number(start);end=Number(end);
  if(!Number.isSafeInteger(total)||total<1||!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||start<1||end<start||end>total)throw Error('PDF 파일 페이지 기준으로 1 ≤ 시작 ≤ 끝 ≤ 전체 페이지 수를 확인하세요.');
  return {start,end,total,count:end-start+1};
 }
 async function extract(bytes,start,end,{pdfLib=root.PDFLib,title='Chapter 1'}={}){
  if(!pdfLib?.PDFDocument)throw Error('PDF 범위 도구를 불러오지 못했습니다. 연결을 확인하고 다시 불러와 주세요.');
  if(!(bytes instanceof Uint8Array)||bytes.length<5||bytes.length>50*1024*1024||String.fromCharCode(...bytes.slice(0,5))!=='%PDF-')throw Error('50MB 이하의 유효한 PDF 원본이 필요합니다.');
  let source;try{source=await pdfLib.PDFDocument.load(bytes,{updateMetadata:false});}catch(error){throw Error(/encrypt/i.test(error.message)?'암호화된 PDF는 범위를 만들 수 없습니다. 원본을 보존하고 암호 없는 사본을 준비하세요.':'PDF 원본을 읽지 못했습니다. 파일을 확인하세요.');}
  const range=validate(start,end,source.getPageCount()),output=await pdfLib.PDFDocument.create();
  const pages=await output.copyPages(source,Array.from({length:range.count},(_,i)=>range.start+i-1));
  for(const page of pages)output.addPage(page);
  output.setTitle(String(title).slice(0,200));output.setProducer('Chapter Quest V4');
  const result=await output.save();if(result.length>50*1024*1024)throw Error('선택 범위 PDF가 50MB를 초과합니다. 더 짧은 범위를 선택하세요.');
  return {bytes:result,...range};
 }
 root.CQPdfRange=Object.freeze({validate,extract});
 if(typeof module!=='undefined'&&module.exports)module.exports=root.CQPdfRange;
})(typeof window!=='undefined'?window:globalThis);
