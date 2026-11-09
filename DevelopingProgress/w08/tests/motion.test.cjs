const fs=require('node:fs'),path=require('node:path'),Module=require('node:module'),assert=require('node:assert/strict');
const ts=require(path.join(process.env.DEVECO_HOME,'tools/hvigor/hvigor/node_modules/typescript'));
for(const ext of ['.ts','.ets'])require.extensions[ext]=(m,f)=>m._compile(ts.transpileModule(fs.readFileSync(f,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,f);
const {clampPage,dockDestination}=require('../entry/src/main/ets/ui/Motion.ts');
assert.equal(clampPage(-3),0);assert.equal(clampPage(20),2);assert.equal(clampPage(NaN),0);assert.equal(clampPage(Infinity),0);assert.equal(clampPage(1.3),1.3);console.log('PASS Dock 越界与无效位移不会产生不存在的页面');
assert.equal(dockDestination(.49,0,100),0);assert.equal(dockDestination(.51,0,100),1);assert.equal(dockDestination(1.51,1,-100),2);console.log('PASS 慢拖动按最近页吸附，可以拖过一半后停留');
assert.equal(dockDestination(.1,0,900),1);assert.equal(dockDestination(1.9,2,-900),1);assert.equal(dockDestination(1.9,0,900),2);assert.equal(dockDestination(.1,2,-900),0);assert.equal(dockDestination(0,0,-900),0);assert.equal(dockDestination(2,2,900),2);console.log('PASS 短距离快甩前进一页，长拖动停在释放位置，首尾收住');
const filename=require.resolve('../entry/src/main/ets/ui/GlassMaterial.ets');
function load(api,supported){
 let calls=0,constructions=0;const empty={empty:true};const original=Module._load;
 Module._load=function(id,p,m){
  if(id==='@kit.BasicServicesKit')return{deviceInfo:{sdkApiVersion:api}};
  if(id==='@kit.ArkUI')return{uiMaterial:{Material:{empty},ImmersiveStyle:{ULTRA_THIN:0,THIN:1},isImmersiveMaterialSupported:()=>{calls++;return supported},ImmersiveMaterial:class{constructor(options){constructions++;this.options=options}}}};
  return original.call(this,id,p,m);
 };
 delete require.cache[filename];try{return{glass:require(filename).glassMaterial,empty,counts:()=>[calls,constructions]}}finally{Module._load=original}
}
const old=load(12,true);assert.equal(old.glass(false),undefined);assert.deepEqual(old.counts(),[0,0]);const unsupported=load(26,false);assert.equal(unsupported.glass(false),undefined);assert.equal(unsupported.glass(true),unsupported.empty);assert.deepEqual(unsupported.counts(),[1,0]);console.log('PASS 旧 API 与不支持沉浸材质的设备安全回落，清晰模式可关闭系统材质');
const native=load(26,true);assert.equal(native.glass(false),native.glass(false));assert.notEqual(native.glass(false),native.glass(false,true));assert.equal(native.glass(true),native.empty);assert.deepEqual(native.counts(),[1,2]);console.log('PASS 原生玻璃只创建一次，Dock 与抽屉共用缓存而非逐帧创建');
