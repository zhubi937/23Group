import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { PdfBridge } from './PdfBridge';
import { image } from '@kit.ImageKit';
import { SourceRecord, OcrLine, uid } from '../domain/Models';
import { xmlText, wordEntry } from '../domain/Documents';
import nativeOcr from 'libjtocr.so';
import { Images } from './Images';
import { OfflineRecognition } from './OfflineRecognition';
export class Documents {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context=context; }
  async fromText(text: string): Promise<SourceRecord> {
    const path=this.context.cacheDir+'/'+uid('text')+'.txt';const data=new util.TextEncoder().encodeInto(text);
    const f=fs.openSync(path,fs.OpenMode.CREATE|fs.OpenMode.READ_WRITE|fs.OpenMode.TRUNC);
    try{await fs.write(f.fd,data.buffer.slice(data.byteOffset,data.byteOffset+data.byteLength));}finally{fs.closeSync(f);}
    try{const source=await this.read(path);source.name='文字录入 '+new Date().toLocaleString();return source;}finally{try{fs.unlinkSync(path);}catch(_){}}
  }
  async choose(): Promise<string> {
    const v=new picker.DocumentViewPicker(this.context); const uris=await v.select({maxSelectNumber:1,fileSuffixFilters:['支持的文件|.png,.jpg,.jpeg,.webp,.pdf,.docx,.txt,.ics']}); return uris&&uris.length?uris[0]:'';
  }
  async read(uri: string): Promise<SourceRecord> {
    const file=await fs.open(uri,fs.OpenMode.READ_ONLY); const s=new SourceRecord(); s.id=uid('source'); s.createdAt=Date.now(); s.name=decodeURIComponent(uri.split('/').pop()||'导入文件');
    let raw=new Uint8Array(0);
    try {
      const stat=await fs.stat(file.fd); if(stat.size===0 || stat.size>20*1024*1024) { throw new Error('请选择 20 MB 以内的文件'); }
      s.hash=await new Images(this.context).fingerprint(file.fd);
      const dir=this.context.filesDir+'/sources'; if(!fs.accessSync(dir)) { fs.mkdirSync(dir); }
      s.path=dir+'/'+s.id+'.bin'; await fs.copyFile(file.fd,s.path);
      const local=await fs.open(s.path,fs.OpenMode.READ_ONLY);
      try { raw=new Uint8Array(stat.size); await fs.read(local.fd,raw.buffer); } finally { fs.closeSync(local); }
    } finally { fs.closeSync(file); }
    let text='';
    try {
      if(raw[0]===0x25 && raw[1]===0x50 && raw[2]===0x44 && raw[3]===0x46) {
        const result=await PdfBridge.shared.read(raw);
        for(const page of result.pages) {
          let content=page.text;
          if(!content.trim() && page.png) {
            const data=new util.Base64Helper().decodeSync(page.png);const source=image.createImageSource(data.buffer);
            try {const pixels=await source.createPixelMap({desiredPixelFormat:image.PixelMapFormat.RGBA_8888});try{const info=await pixels.getImageInfo();const lines=await new OfflineRecognition().run(pixels,info.size.width,info.size.height,this.context);content=lines.map((l:OcrLine)=>l.text).join('\n');}finally{await pixels.release();}}finally{source.release();}
          }
          text+=content+'\n';
        }
        if(!text.trim()){throw new Error('没有读取到 PDF 文字，请检查清晰度');}
        s.mode='pdf';
      } else if(raw[0]===0x50 && raw[1]===0x4b) {
        const entry=wordEntry(raw);text=xmlText(await nativeOcr.inflateWord(entry.data,entry.size,entry.crc,entry.method));
        s.mode='word';
      } else {
        // Image source inspection is authoritative; extension alone is not trusted.
        if(raw[0]===0x89 || raw[0]===0xff || (raw[0]===0x52 && raw[1]===0x49)) {
          fs.unlinkSync(s.path); return await new Images(this.context).importUri(uri);
        }
        text=util.TextDecoder.create('utf-8',{fatal:true}).decodeToString(raw); s.mode='text';
        if(text.includes('\u0000') || text.length>200000) { throw new Error('请选择 UTF-8 文本或支持的文档格式'); }
      }
      s.lines=text.split(/\r?\n/).map((v:string,i:number)=>new OcrLine('text_'+i,v)); s.ocrState='recognized'; return s;
    } catch(e) { try { fs.unlinkSync(s.path); } catch(_) {} throw new Error((e as Error).message); }
  }
}
