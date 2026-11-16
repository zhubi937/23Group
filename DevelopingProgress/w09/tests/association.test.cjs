const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const ts=require(path.join(process.env.DEVECO_HOME,'tools/hvigor/hvigor/node_modules/typescript'));
require.extensions['.ts']=(m,f)=>m._compile(ts.transpileModule(fs.readFileSync(f,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,f);
const M=require('../entry/src/main/ets/domain/Models.ts'),A=require('../entry/src/main/ets/domain/Association.ts');
let count=0;function test(name,fn){fn();count++;console.log('PASS '+name)}
function task(id,title='课程作业',date='2026-12-10'){const t=new M.TaskRecord();t.id=id;t.title=title;t.type='作业';t.deadline=date+' 23:59';return t}
test('同名不同周的作业不会被当成同一件事',()=>{assert.equal(A.rankMatches(task('new'),[task('other','课程作业','2026-12-17')]).length,0)});
test('不同课程的同名事项保持独立',()=>{const a=task('a'),b=task('b');a.context='数据库';b.context='操作系统';assert.equal(A.rankMatches(a,[b]).length,0)});
test('不同车次不能只凭相近标题关联',()=>{const a=task('a','G970 出行'),b=task('b','G971 出行');a.type=b.type='出行';assert.equal(A.rankMatches(a,[b]).length,0)});
test('相同日期不同举行时间视作不同场次',()=>{const a=task('a','学术讲座'),b=task('b','学术讲座');a.type=b.type='活动';a.startTime='09:00';b.startTime='19:00';assert.equal(A.rankMatches(a,[b]).length,0)});
test('明确延期语义允许候选并展示日期差异',()=>{const a=task('a','课程作业延期通知','2026-12-17'),b=task('b');const m=A.rankMatches(a,[b]);assert.equal(m.length,1);assert.equal(m[0].level,'存在差异');assert(m[0].conflicts.some(x=>x.includes('日期不同')));assert.equal(b.deadline,'2026-12-10 23:59')});
test('课程日期一致的候选排在缺少依据的同名项之前',()=>{const a=task('a'),b=task('b'),c=task('c');a.context=b.context='数据库';c.deadline='';assert.equal(A.rankMatches(a,[c,b])[0].task.id,'b')});
test('同一来源已关联项优先标记而非重复附加',()=>{const a=task('a'),b=task('b');const s=new M.SourceRecord();s.id='image';b.sourceIds=['image'];const m=A.rankMatches(a,[b],s);assert.equal(m[0].level,'已关联');assert(m[0].alreadyLinked);assert.equal(b.sourceIds.length,1)});
test('删除事项排除且重复记录去重',()=>{const a=task('a'),b=task('b'),c=task('c');c.status='已删除';assert.equal(A.rankMatches(a,[b,b,c]).length,1)});
test('地点变化保留差异提示',()=>{const a=task('a'),b=task('b');a.location='一号楼';b.location='二号楼';assert(A.rankMatches(a,[b])[0].conflicts.includes('地点不同'))});
test('低信息通用标题不产生仅凭名称的关联',()=>{const a=task('a','会议'),b=task('b','会议');a.deadline=b.deadline='';assert.equal(A.rankMatches(a,[b]).length,0)});
test('同分候选按更新时间及ID稳定排序',()=>{const a=task('a'),b=task('b'),c=task('c');b.updatedAt=c.updatedAt=100;assert.deepEqual(A.rankMatches(a,[c,b]).map(x=>x.task.id),['b','c'])});
test('标签去重、去空并限制数量与长度',()=>{assert.deepEqual(A.normalizeTags('课程，课程, 作业 、 ,'),['课程','作业']);assert.equal(A.normalizeTags('1,2,3,4,5,6,7').length,6);assert.equal(A.normalizeTags('长'.repeat(30))[0].length,16)});
test('来源搜索覆盖标签、备注和OCR原文',()=>{const s=new M.SourceRecord();s.name='截图';s.tags=['数据库'];s.note='老师通知';s.lines=[new M.OcrLine('l','提交作业')];for(const q of ['数据库','老师','提交'])assert(A.sourceMatches(s,q));assert(!A.sourceMatches(s,'不存在'))});
test('5000条事项排序结果有界且输入保持不变',()=>{const items=Array.from({length:5000},(_,i)=>task('t'+i,'课程第'+i+'周作业'));const incoming=task('new','课程第1024周作业');const start=performance.now();const result=A.rankMatches(incoming,items);const ms=performance.now()-start;assert.equal(result[0].task.id,'t1024');assert(result.length<=8);assert.equal(items[1024].sourceIds.length,0);console.log('BENCH association_5000_ms='+ms.toFixed(2))});
console.log(count+' association tests passed.');
