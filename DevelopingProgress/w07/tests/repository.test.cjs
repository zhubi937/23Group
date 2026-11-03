const fs=require('node:fs'),path=require('node:path'),Module=require('node:module'),assert=require('node:assert/strict');
const devEco=process.env.DEVECO_HOME;
if(!devEco){console.error('请通过 scripts/test.ps1 运行，或设置 DEVECO_HOME');process.exit(2)}
const ts=require(path.join(devEco,'tools/hvigor/hvigor/node_modules/typescript'));
for(const ext of ['.ts','.ets'])require.extensions[ext]=(m,f)=>m._compile(ts.transpileModule(fs.readFileSync(f,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,f);
const {DatabaseSync}=require('node:sqlite');const sql=new DatabaseSync(':memory:');let failHistory=false;
class ResultSet{constructor(rows){this.rows=rows;this.at=-1}goToNextRow(){return ++this.at<this.rows.length}goToFirstRow(){this.at=0;return !!this.rows.length}getString(i){return Object.values(this.rows[this.at])[i]}close(){}}
const db={executeSql:async(s,a=[])=>{if(failHistory&&s.startsWith('INSERT INTO history'))throw new Error('injected history write failure');sql.prepare(s).run(...a)},querySql:async(s,a=[])=>new ResultSet(sql.prepare(s).all(...a)),beginTransaction:()=>sql.exec('BEGIN'),commit:()=>sql.exec('COMMIT'),rollBack:()=>sql.exec('ROLLBACK')};
const original=Module._load;Module._load=function(id,parent,isMain){if(id==='@kit.ArkData')return{relationalStore:{SecurityLevel:{S1:1},getRdbStore:async()=>db}};return original.call(this,id,parent,isMain)};
const {Repository}=require('../entry/src/main/ets/data/Repository.ets');const M=require('../entry/src/main/ets/domain/Models.ts');Module._load=original;
async function run(){const repo=new Repository();await repo.open({});let checks=0;
const src=new M.SourceRecord();src.id='s1';src.hash='hash1';src.name='原始通知';
let t=new M.TaskRecord();t.title='应用设计作业';t.deadline='2026-12-18 23:59';
t=await repo.saveTask(t,'确认新建',src);assert.equal(t.revision,1);assert.equal((await repo.tasks()).length,1);assert.equal((await repo.history(t.id))[0].sourceSnapshot.name,'原始通知');checks++;console.log('PASS 实际SQL建表与新建事务、来源快照');
const old=M.cloneTask(t);const src2=new M.SourceRecord();src2.id='s2';src2.hash='hash2';src2.name='延期通知';t.deadline='2026-12-20 23:59';t=await repo.saveTask(t,'关联更新',src2);assert.equal(t.sourceIds.length,2);const history=await repo.history(t.id);assert.equal(history.length,2);assert.equal(history[0].before.deadline,'2026-12-18 23:59');assert.equal(history[0].after.deadline,'2026-12-20 23:59');checks++;console.log('PASS 更新保留前后值和两个来源');
await assert.rejects(repo.saveTask(old,'过期修改'),/已更新/);assert.equal((await repo.tasks())[0].deadline,'2026-12-20 23:59');checks++;console.log('PASS 旧版本写入被拒绝');
const src3=new M.SourceRecord();src3.id='s3';src3.hash='hash3';const failed=M.cloneTask(t);failed.title='不应保存';failHistory=true;await assert.rejects(repo.saveTask(failed,'故障注入',src3));failHistory=false;assert.equal((await repo.sources()).length,2);assert.equal((await repo.tasks())[0].title,'应用设计作业');assert.equal((await repo.history(t.id)).length,2);checks++;console.log('PASS 历史写入失败时事项和来源全部回滚');
await assert.rejects(repo.removeSource('s1'),/引用/);checks++;console.log('PASS 被引用来源不可单独删除');
await repo.putSource(src3);await repo.removeSource('s3');assert.equal((await repo.sources()).length,2);checks++;console.log('PASS 未引用来源可删除');
t.status='已删除';await repo.saveTask(t,'删除');assert.equal((await repo.tasks()).length,0);assert.equal((await repo.tasks(true)).length,1);assert.equal((await repo.history(t.id)).length,3);checks++;console.log('PASS 软删除保留历史');
await repo.clear();assert.equal((await repo.sources()).length,0);assert.equal((await repo.tasks(true)).length,0);assert.equal((await repo.history(t.id)).length,0);checks++;console.log('PASS 清空本地表');
console.log('\n'+checks+' repository contract tests passed using Node SQLite. This validates SQL/transaction logic, not HarmonyOS API behavior.');sql.close()}
run().catch(e=>{console.error(e);process.exitCode=1});
