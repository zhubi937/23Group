const fs=require('node:fs'),path=require('node:path'),Module=require('node:module'),assert=require('node:assert/strict');
const ts=require(path.join(process.env.DEVECO_HOME,'tools/hvigor/hvigor/node_modules/typescript'));
for(const ext of ['.ts','.ets'])require.extensions[ext]=(m,f)=>m._compile(ts.transpileModule(fs.readFileSync(f,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,f);
const T=require('../entry/src/main/ets/ui/Appearance.ts');
const state=new Map();let flushes=0,fail=false;
const store={get:async(k,f)=>state.has(k)?state.get(k):f,put:async(k,v)=>{if(fail){fail=false;throw Error('disk failure')}await new Promise(r=>setTimeout(r,1));state.set(k,v)},flush:async()=>{flushes++}};
const original=Module._load;Module._load=function(id,p,m){if(id==='@kit.ArkData')return{preferences:{getPreferences:async()=>store}};return original.call(this,id,p,m)};
const {AppearanceStore}=require('../entry/src/main/ets/platform/AppearanceStore.ets');Module._load=original;
function luminance(hex){return hex.slice(1).match(/../g).map(v=>parseInt(v,16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4).reduce((n,v,i)=>n+v*[.2126,.7152,.0722][i],0)}
(async()=>{
 assert.equal(new Set(T.THEMES.map(x=>x.id)).size,6);for(const t of T.THEMES)assert(1.05/(luminance(t.accent)+.05)>=4.5,t.name+' accent contrast');console.log('PASS 六套主题标识唯一且强调色对白底对比度不低于4.5');
 state.set('themeId','invalid');state.set('clearGlass','yes');const prefs=new AppearanceStore();const loaded=await prefs.open({});assert.equal(loaded.themeId,'morandi-blue');assert.equal(loaded.clearGlass,false);console.log('PASS 旧版无设置或无效值安全回退');
 const writes=T.THEMES.map(t=>{const a=new T.Appearance();a.themeId=t.id;return prefs.save(a)});await Promise.all(writes);assert.equal(state.get('themeId'),T.THEMES.at(-1).id);assert.equal(flushes,6);const again=await new AppearanceStore().open({});assert.equal(again.themeId,T.THEMES.at(-1).id);console.log('PASS 快速连续选择后最终主题完整落盘并可恢复');
 fail=true;await assert.rejects(prefs.save(new T.Appearance()),/disk failure/);const final=new T.Appearance();final.themeId='matcha';final.clearGlass=true;final.reduceMotion=true;await prefs.save(final);assert.equal(state.get('themeId'),'matcha');assert.equal(state.get('clearGlass'),true);assert.equal(state.get('reduceMotion'),true);console.log('PASS 一次写入失败不阻断后续保存，清晰与动态偏好独立持久化');
})().catch(e=>{console.error(e);process.exitCode=1});
