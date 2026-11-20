// node app/tests/chapter2-replacement-contract.test.cjs
const assert=require('node:assert/strict');
const fs=require('node:fs');
const replace=fs.readFileSync('app/sql/development-replace-published-activity-not-for-production.sql','utf8');
const reread=fs.readFileSync('app/sql/development-reread-progress-not-for-production.sql','utf8');
const expected=['for update','cq_v4_student_submissions','approval_hash is distinct from','p_old_approval_id','p_new_approval_id','update public.cq_v4_activities','parent_user_id=v_uid','jsonb_array_length(v_new.questions)<>jsonb_array_length(v_new.answer_key)'];
for(const term of expected)assert.ok(replace.toLowerCase().includes(term.toLowerCase()),'missing replacement guard '+term);
assert.ok(reread.includes('v_correct*10<v_total*7'),'70% integer boundary');
assert.ok(!reread.includes("!~ '^(0|[1-9][0-9]*)\n"),'truncated regex');
const score=(answers,keys)=>{let n=0,c=0;for(let i=0;i<keys.length;i++){if(keys[i]===null)continue;n++;if(answers[i]===keys[i])c++}return {n,c,required:n>0&&c*10<n*7}};
const keys=[0,1,1,2,1,0,2,null,null,null];
assert.deepEqual(score([0,1,1,2,1,0,2,'a','b','c'],keys),{n:7,c:7,required:false});
assert.deepEqual(score([0,1,1,2,1,9,9,'a','b','c'],keys),{n:7,c:5,required:false});
assert.deepEqual(score([0,1,1,2,9,9,9,'a','b','c'],keys),{n:7,c:4,required:true});
assert.deepEqual(score(['short'],[null]),{n:0,c:0,required:false});
console.log('CHAPTER2_REPLACEMENT_STATIC_CONTRACT_PASSED');
