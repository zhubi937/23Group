const fs=require('node:fs'),path=require('node:path'),Module=require('node:module'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const devEco=process.env.DEVECO_HOME;if(!devEco){console.error('请通过 scripts/test.ps1 运行，或设置 DEVECO_HOME');process.exit(2)}
const ts=require(path.join(devEco,'tools/hvigor/hvigor/node_modules/typescript'));
for(const ext of ['.ts','.ets'])require.extensions[ext]=(m,f)=>m._compile(ts.transpileModule(fs.readFileSync(f,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,f);
const data=Buffer.alloc(800000);for(let i=0;i<data.length;i++)data[i]=(i*31+i%97)%256;let pointer=0;
const fileIo={read:async(fd,buffer,opt)=>{pointer+=opt.offset||0;const n=Math.min(opt.length,data.length-pointer);new Uint8Array(buffer).set(data.subarray(pointer,pointer+n));pointer+=n;return n}};
const cryptoFramework={createMd:()=>{const h=crypto.createHash('sha256');return{update:async v=>h.update(v.data),digest:async()=>({data:new Uint8Array(h.digest())})}}};
const real=Module._load;Module._load=function(id,p,m){if(id==='@kit.CoreFileKit')return{fileIo};if(id==='@kit.ImageKit')return{image:{}};if(id==='@kit.MediaLibraryKit')return{photoAccessHelper:{}};if(id==='@kit.CryptoArchitectureKit')return{cryptoFramework};return real.call(this,id,p,m)};
const {Images}=require('../entry/src/main/ets/platform/Images.ets');Module._load=real;
(async()=>{const actual=await new Images({}).fingerprint(1);assert.equal(actual,crypto.createHash('sha256').update(data).digest('hex'));console.log('PASS 大于三个分块的图片SHA256完整覆盖，无偏移跳读');console.log('File I/O contract test with sequential file-pointer semantics; not proof of HarmonyOS file selection.')})().catch(e=>{console.error(e);process.exitCode=1});
