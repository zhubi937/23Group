import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

// Create native materials once. Older devices keep the backdrop-blur fallback.
let thin: uiMaterial.Material | undefined = undefined;
let regular: uiMaterial.Material | undefined = undefined;
let empty: uiMaterial.Material | undefined = undefined;
let initialized: boolean = false;
export function glassMaterial(clear: boolean, sheet: boolean = false): uiMaterial.Material | undefined {
  if (deviceInfo.sdkApiVersion < 26) { return undefined; }
  if (!initialized) {
    initialized = true;
    try {
      empty = uiMaterial.Material.empty;
      const supported=uiMaterial.isImmersiveMaterialSupported();
      console.info('ScreenshotToTask native immersive glass supported='+supported);
      if (supported) {
        thin = new uiMaterial.ImmersiveMaterial({style:uiMaterial.ImmersiveStyle.ULTRA_THIN,materialColor:'#00FFFFFF',interactive:true,lightEffect:{color:'#FFFFFF'},applyShadow:false});
        regular = new uiMaterial.ImmersiveMaterial({style:uiMaterial.ImmersiveStyle.ULTRA_THIN,materialColor:'#08FFFFFF',applyShadow:false});
      }
    } catch (_) { /* The supported, native blur path remains available. */ }
  }
  return clear ? empty : sheet ? regular : thin;
}
