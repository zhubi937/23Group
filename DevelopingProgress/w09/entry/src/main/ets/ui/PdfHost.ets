import {
  PdfBridge
}
from '../platform/PdfBridge';
@Component
export struct PdfHost {
  @State active: boolean=false;
  private bridge: PdfBridge=PdfBridge.shared;
  aboutToAppear(): void {
    this.bridge.mount=()=>{
      this.active=true;
    };
  }
  build(){
    Stack(){
      if(this.active){
        Web({
          src:$rawfile('pdfjs/reader.html'),controller:this.bridge.controller
        }).javaScriptAccess(true).fileAccess(true).domStorageAccess(false).onlineImageAccess(false).multiWindowAccess(false).javaScriptProxy({
          object:this.bridge,name:'Reader',methodList:['ready','complete'],controller:this.bridge.controller
        }).onLoadIntercept((event)=>{
          return event?/^https?:/i.test(event.data.getRequestUrl()):false;
        }).width(1).height(1);
      }
    }.width(1).height(1).opacity(0).hitTestBehavior(HitTestMode.None)
  }
}
