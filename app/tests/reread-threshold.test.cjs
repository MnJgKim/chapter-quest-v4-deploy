// Isolated 70% threshold regression: node app/tests/reread-threshold.test.cjs
const assert=require('node:assert/strict');
const needsReread=(correct,total)=>total>0&&correct*10<total*7;
for(const [correct,total,expected] of [
 [0,10,true],[6,10,true],[7,10,false],[8,10,false],
 [2,3,true],[3,4,false],[0,0,false],[13,20,true],[14,20,false]
])assert.equal(needsReread(correct,total),expected,`${correct}/${total}`);
console.log('REREAD_70_PERCENT_BOUNDARIES_PASSED');
