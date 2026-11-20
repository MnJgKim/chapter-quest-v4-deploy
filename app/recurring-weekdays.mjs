// Pure recurring lesson date generator. No database access or writes.
const rules=Object.freeze({'서우':[1,3,4],'서진':[2,3,5]});
const first=Object.freeze({'서우':'2026-11-23','서진':'2026-11-24'});
const parse=s=>{if(typeof s!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(s))throw new TypeError('Invalid date');const d=new Date(s+'T00:00:00Z');if(!Number.isFinite(+d)||d.toISOString().slice(0,10)!==s)throw new TypeError('Invalid date');return d;};
export function recurringLessonDates({student,throughDate,fromDate}={}){
 if(!Object.hasOwn(rules,student))throw new TypeError('Unknown student');
 const start=parse(fromDate??first[student]),min=parse(first[student]),end=parse(throughDate);
 if(start<min||end<start||(+end-+start)/86400000>366)throw new RangeError('Invalid date range');
 const result=[];
 for(let t=+start;t<=+end;t+=86400000){const d=new Date(t);if(rules[student].includes(d.getUTCDay()))result.push(d.toISOString().slice(0,10));}
 return {student,timezone:'Asia/Seoul',dates:result,writesPerformed:0,executable:false};
}
