import {
  util
}
from '@kit.ArkTS';
import {
  webview
}
from '@kit.ArkWeb';
export class PdfPageData {
  text: string='';
  png: string='';
}
export class PdfData {
  pages: PdfPageData[]=[];
  error: string='';
}
export class PdfBridge {
  static shared: PdfBridge=new PdfBridge();
  controller: webview.WebviewController=new webview.WebviewController();
  mount: ()=>void=()=>{
  };
  private loaded: boolean=false;
  private readyResolve: (()=>void)|null=null;
  private resolve: ((data:PdfData)=>void)|null=null;
  private reject: ((error:Error)=>void)|null=null;
  private timer: number=-1;
  ready(): void {
    this.loaded=true;
    if(this.readyResolve){
      this.readyResolve();
      this.readyResolve=null;
    }
  }
  complete(json: string): void {
    try{
      const data=JSON.parse(json) as PdfData;
      if(data.error){
        if(this.reject){
          this.reject(new Error(data.error));
        }
      }
      else if(this.resolve){
        this.resolve(data);
      }
    }
    catch(e){
      if(this.reject){
        this.reject(new Error('PDF 读取结果格式错误'));
      }
    }
    finally{
      clearTimeout(this.timer);
      this.resolve=null;
      this.reject=null;
    }
  }
  async read(raw: Uint8Array): Promise<PdfData> {
    if(this.resolve){
      throw new Error('已有 PDF 正在读取，请稍后再试');
    }
    if(!this.loaded){
      const ready=new Promise<void>((resolve,reject)=>{
        this.readyResolve=resolve;
        this.timer=setTimeout(()=>{
          this.readyResolve=null;
          reject(new Error('本地 PDF 组件加载超时，请重试'));
        },15000);
      });
      this.mount();
      await ready;
      clearTimeout(this.timer);
    }
    const data=new util.Base64Helper().encodeToStringSync(raw);
    return await new Promise<PdfData>((resolve,reject)=>{
      this.resolve=resolve;
      this.reject=reject;
      this.timer=setTimeout(()=>{
        this.resolve=null;
        this.reject=null;
        reject(new Error('PDF 读取超时，请拆分文件后重试'));
      },90000);
      this.controller.runJavaScript('window.openPdf("'+data+'")').catch((e:Error)=>{
        clearTimeout(this.timer);
        this.resolve=null;
        this.reject=null;
        reject(e);
      });
    });
  }
}
