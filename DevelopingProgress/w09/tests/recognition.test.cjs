const fs=require('node:fs'),path=require('node:path'),Module=require('node:module'),assert=require('node:assert/strict');
const ts=require(path.join(process.env.DEVECO_HOME,'tools/hvigor/hvigor/node_modules/typescript'));
for(const ext of ['.ts','.ets'])require.extensions[ext]=(m,f)=>m._compile(ts.transpileModule(fs.readFileSync(f,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,f);
const {SourceRecord,OcrLine,Box}=require('../entry/src/main/ets/domain/Models.ts');
let system=false,systemCalls=0,offlineCalls=0,offlineFailure=false,released=0;
const pixels={getImageInfo:async()=>({size:{width:100,height:100}}),release:async()=>{released++}};
const original=Module._load;
Module._load=function(id,p,m){
 if(id==='@kit.CoreVisionKit')return{textRecognition:{init:async()=>{systemCalls++;throw Error('system unavailable')},release:async()=>{}}};
 if(id==='@kit.ImageKit')return{image:{PixelMapFormat:{RGBA_8888:3},createImageSource:()=>({createPixelMap:async()=>pixels,release:async()=>{}})}};
 if(id==='@kit.CoreFileKit')return{fileIo:{OpenMode:{READ_ONLY:0},openSync:()=>({fd:1}),closeSync:()=>{}}};
 if(id==='./OfflineRecognition')return{OfflineRecognition:class{async run(){offlineCalls++;if(offlineFailure)throw Error('model failure');return[new OcrLine('native_0','讲座通知',new Box(2,4,30,12))]}}};
 return original.call(this,id,p,m);
};
global.canIUse=cap=>{assert.equal(cap,'SystemCapability.AI.OCR.TextRecognition');return system};
const {Recognition}=require('../entry/src/main/ets/platform/Recognition.ets');Module._load=original;
(async()=>{
 const r=new Recognition();r.setContext({});
 const source=()=>{const s=new SourceRecord();s.path='/existing/source.png';s.width=s.height=100;return s};
 let s=source();await r.run(s);assert.equal(systemCalls,0);assert.equal(offlineCalls,1);assert.equal(s.mode,'offline');assert.equal(s.ocrState,'recognized');assert.equal(s.lines[0].box.x,2);console.log('PASS 系统能力不支持时自动调用本机OCR，保存真实返回的坐标');
 system=true;s=source();await r.run(s);assert.equal(systemCalls,1);assert.equal(offlineCalls,2);assert.equal(s.mode,'offline');console.log('PASS 系统服务失败时回落本机识别');
 offlineFailure=true;s=source();s.lines=[new OcrLine('old','已有中文原文',new Box())];await r.run(s);assert.equal(s.ocrState,'failed');assert.equal(s.lines[0].text,'已有中文原文');assert.equal(s.path,'/existing/source.png');assert.equal(released,3);console.log('PASS 两条识别路径失败时保留图片和旧原文并释放像素');
 console.log('Recognition routing contract tests; not proof of native OCR.');
})().catch(e=>{console.error(e);process.exitCode=1});
