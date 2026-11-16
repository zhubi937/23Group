import {
  camera
}
from '@kit.CameraKit';
import {
  common
}
from '@kit.AbilityKit';
import {
  image
}
from '@kit.ImageKit';
import {
  fileIo as fs
}
from '@kit.CoreFileKit';
import {
  BusinessError
}
from '@kit.BasicServicesKit';
@Component
export struct CameraCapture {
  onCapture: (path:string)=>void=()=>{
  };
  onCancel: ()=>void=()=>{
  };
  @State available: boolean=false;
  @State taking: boolean=false;
  @State error: string='正在打开相机';
  private surface: XComponentController=new XComponentController();
  private input: camera.CameraInput|null=null;
  private preview: camera.PreviewOutput|null=null;
  private photo: camera.PhotoOutput|null=null;
  private session: camera.PhotoSession|null=null;
  private context: common.UIAbilityContext|null=null;
  private closed: boolean=false;
  private rawPhoto: boolean=false;
  private captureTimer: number=-1;
  private async initialize(): Promise<void> {
    try {
      this.context=this.getUIContext().getHostContext() as common.UIAbilityContext;
      const manager=camera.getCameraManager(this.context);
      const devices=manager.getSupportedCameras();
      if(!devices.length){
        throw new Error('当前设备没有可用相机，请改用相册或文件录入');
      }
      const device=devices.find((d:camera.CameraDevice)=>d.cameraPosition===camera.CameraPosition.CAMERA_POSITION_BACK)||devices[0];
      const capability=manager.getSupportedOutputCapability(device,camera.SceneMode.NORMAL_PHOTO);
      const previewOptions=capability.previewProfiles.filter((p:camera.Profile)=>p.size.width*p.size.height<=12000000);
      let previews=previewOptions.filter((p:camera.Profile)=>p.size.width*p.size.height<=1920*1080).sort((a:camera.Profile,b:camera.Profile)=>b.size.width*b.size.height-a.size.width*a.size.height);
      if(!previews.length){previews=previewOptions.sort((a:camera.Profile,b:camera.Profile)=>a.size.width*a.size.height-b.size.width*b.size.height);}
      const photoOptions=capability.photoProfiles.filter((p:camera.Profile)=>p.format===camera.CameraFormat.CAMERA_FORMAT_JPEG&&p.size.width*p.size.height<=40000000);
      let photos=photoOptions.filter((p:camera.Profile)=>p.size.width*p.size.height<=8000000).sort((a:camera.Profile,b:camera.Profile)=>b.size.width*b.size.height-a.size.width*a.size.height);
      if(!photos.length){photos=photoOptions.sort((a:camera.Profile,b:camera.Profile)=>a.size.width*a.size.height-b.size.width*b.size.height);}
      if(!photos.length){
        photos=capability.photoProfiles.filter((p:camera.Profile)=>p.format===camera.CameraFormat.CAMERA_FORMAT_RGBA_8888&&p.size.width*p.size.height<=12000000);
        this.rawPhoto=true;
      }
      if(!previews.length||!photos.length){
        throw new Error('设备没有提供可用的拍照规格，请使用相册或文件');
      }
      this.input=manager.createCameraInput(device);
      await this.input.open();
      if(this.closed){
        await this.release();
        return;
      }
      this.preview=manager.createPreviewOutput(previews[0],this.surface.getXComponentSurfaceId());
      this.photo=manager.createPhotoOutput(photos[0]);
      this.photo.on('photoAvailable',(error:BusinessError,photo:camera.Photo)=>{
        clearTimeout(this.captureTimer);
        if(error){
          this.error='拍照未完成：'+error.message;
          this.taking=false;
          return;
        }
        this.savePhoto(photo);
      });
      this.session=manager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
      this.session.beginConfig();
      this.session.addInput(this.input);
      this.session.addOutput(this.preview);
      this.session.addOutput(this.photo);
      await this.session.commitConfig();
      await this.session.start();
      this.available=true;
      this.error='';
      if(this.closed){
        await this.release();
      }
    }
    catch(e){
      this.error=(e as Error).message||'相机打开失败';
      await this.release();
    }
  }
  private async savePhoto(photo: camera.Photo): Promise<void> {
    let path='';
    try {
      if(!this.context){
        throw new Error('相机上下文已关闭');
      }
      const component=await photo.main.getComponent(image.ComponentType.JPEG);
      path=this.context.cacheDir+'/photo-'+Date.now()+'.jpg';
      let bytes=component.byteBuffer;
      const signature=new Uint8Array(bytes);
      const encoded=(signature[0]===0xff&&signature[1]===0xd8)||(signature[0]===0x89&&signature[1]===0x50);
      if(this.rawPhoto&&!encoded){
        const size=photo.main.size;
        const packed=new Uint8Array(size.width*size.height*4),raw=new Uint8Array(bytes);
        const stride=component.rowStride>=size.width*4?component.rowStride:size.width*4;
        if(raw.length<(size.height-1)*stride+size.width*4){
          throw new Error('相机回传图像不完整，请重新拍摄');
        }
        for(let y=0;
        y<size.height;
        y++){
          packed.set(raw.subarray(y*stride,y*stride+size.width*4),y*size.width*4);
        }
        for(let i=3;
        i<packed.length;
        i+=4){
          packed[i]=255;
        }
        const pixels=await image.createPixelMap(packed.buffer,{
          size:size,srcPixelFormat:image.PixelMapFormat.RGBA_8888,pixelFormat:image.PixelMapFormat.RGBA_8888
        });
        const packer=image.createImagePacker();
        try{
          bytes=await packer.packing(pixels,{
            format:'image/jpeg',quality:95
          });
        }
        finally{
          await packer.release();
          await pixels.release();
        }
      }
      const f=fs.openSync(path,fs.OpenMode.CREATE|fs.OpenMode.READ_WRITE|fs.OpenMode.TRUNC);
      try{
        await fs.write(f.fd,bytes);
      }
      finally{
        fs.closeSync(f);
      }
    }
    catch(e){
      this.error=(e as Error).message;
      this.taking=false;
    }
    finally{
      await photo.release();
    }
    if(path&&!this.closed){
      this.onCapture(path);
    }
  }
  private async capture(): Promise<void> {
    if(!this.photo||!this.available||this.taking){
      return;
    }
    this.taking=true;
    this.captureTimer=setTimeout(()=>{
      this.taking=false;
      this.error='拍照超时，请重试';
    },15000);
    try{
      await this.photo.capture();
    }
    catch(e){
      clearTimeout(this.captureTimer);
      this.error=(e as Error).message;
      this.taking=false;
    }
  }
  private async release(): Promise<void> {
    this.available=false;
    if(this.session){
      try{
        await this.session.stop();
      }
      catch(_){
      }
      try{
        await this.session.release();
      }
      catch(_){
      }
      this.session=null;
    }
    if(this.photo){
      try{
        await this.photo.release();
      }
      catch(_){
      }
      this.photo=null;
    }
    if(this.preview){
      try{
        await this.preview.release();
      }
      catch(_){
      }
      this.preview=null;
    }
    if(this.input){
      try{
        await this.input.close();
      }
      catch(_){
      }
      this.input=null;
    }
  }
  aboutToDisappear(): void {
    this.closed=true;
    clearTimeout(this.captureTimer);
    this.release();
  }
  build(){
    Column(){
      Row(){
        Button('取消').fontColor('#F2F1E9').backgroundColor(Color.Transparent).onClick(this.onCancel);
        Blank();
        Text('拍摄通知').fontSize(17).fontColor('#F2F1E9');
        Blank();
      }.width('100%').height(60);
      XComponent({
        id:'jt-camera-preview',type:XComponentType.SURFACE,controller:this.surface
      }).width('100%').layoutWeight(1).onLoad(()=>{
        this.initialize();
      });
      if(this.error){
        Text(this.error).fontSize(13).fontColor('#E7D4B9').padding(18);
      }
      Button('●').width(76).height(76).borderRadius(38).backgroundColor('#F5F2E8').fontColor('#32382D').fontSize(56).enabled(this.available&&!this.taking).onClick(()=>{
        this.capture();
      }).margin({
        top:20,bottom:30
      }).id('camera-shutter');
    }.width('100%').height('100%').backgroundColor('#151913')
  }
}
