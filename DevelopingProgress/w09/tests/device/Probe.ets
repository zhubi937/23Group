// Installed only by scripts/device-probe.ps1 in an isolated test bundle.
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Documents } from '../../entry/src/main/ets/platform/Documents';
import { Images } from '../../entry/src/main/ets/platform/Images';
import { Recognition } from '../../entry/src/main/ets/platform/Recognition';
import { loadModels } from '../../entry/src/main/ets/platform/ModelLoader';
import { analyzeAsync } from '../../entry/src/main/ets/platform/Semantics';
import nativeOcr from 'libjtocr.so';
import { PdfHost } from '../../entry/src/main/ets/ui/PdfHost';
import { wordEntry } from '../../entry/src/main/ets/domain/Documents';
@Entry
@Component
struct Probe {
  @State result: string='RUNNING';
  private async run(): Promise<void> {
    const context=this.getUIContext().getHostContext() as common.UIAbilityContext;
    const documents=new Documents(context);const results:string[]=[];
    for(const name of ['notice.txt','notice.docx','notice.pdf','scanned.pdf']) {
      try {
        const raw=await context.resourceManager.getRawFileContent('device-fixtures/'+name);const path=context.cacheDir+'/'+name;
        const f=fs.openSync(path,fs.OpenMode.CREATE|fs.OpenMode.READ_WRITE|fs.OpenMode.TRUNC);try{fs.writeSync(f.fd,raw.buffer.slice(raw.byteOffset,raw.byteOffset+raw.byteLength));}finally{fs.closeSync(f);}
        const s=await documents.read(path);const text=s.lines.map((l)=>l.text).join('\n');
        if(!text.includes(name==='scanned.pdf'?'2026':'2027-01-01')) {throw new Error('expected date missing');}
        results.push('PASS '+name+' '+s.mode+' '+s.lines.length+' lines');
        if(name==='notice.docx'){const e=wordEntry(raw);try{await nativeOcr.inflateWord(e.data,e.size,e.crc^1,e.method);throw new Error('CRC accepted');}catch(err){if((err as Error).message==='CRC accepted'){throw new Error((err as Error).message);}results.push('PASS native CRC rejection');}}
      }catch(e){results.push('FAIL '+name+' '+(e as Error).message);}
      this.result=results.join('\n');
    }
    try {
      const s=await new Images(context).sample('notice');const r=new Recognition();r.setContext(context);await r.run(s);
      if(s.ocrState!=='recognized'||!s.lines.length){throw new Error(s.error);}
      const engine=await loadModels(context);const semantic=await analyzeAsync(engine,s.lines.map((l)=>l.text).join('\n'));
      if(!semantic.tasks.length||!semantic.tasks[0].title){throw new Error('empty semantics');}
      results.push('PASS OCR '+s.mode+' '+s.lines.length+' lines');results.push('PASS taskpool '+semantic.tasks[0].type+' '+semantic.tasks[0].deadline);
    }catch(e){results.push('FAIL OCR '+(e as Error).message);}
    this.result=results.join('\n')+'\nDONE';
  }
  aboutToAppear(): void {this.run();}
  build(){Stack(){PdfHost();Column(){Text(this.result).fontSize(16).fontColor('#111111').id('probe-result');}.width('100%').height('100%').padding(24).backgroundColor('#FFFFFF')}}
}
