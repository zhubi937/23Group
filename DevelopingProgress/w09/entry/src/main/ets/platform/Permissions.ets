import { abilityAccessCtrl, common, bundleManager } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
export class PermissionState { camera: boolean=false; notifications: boolean=false; calendar: boolean=false; }
export class Permissions {
  async read(): Promise<PermissionState> {
    const s=new PermissionState(); const info=await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    s.camera=await abilityAccessCtrl.createAtManager().checkAccessToken(info.appInfo.accessTokenId,'ohos.permission.CAMERA')===abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    s.notifications=await notificationManager.isNotificationEnabled();const manager=abilityAccessCtrl.createAtManager();s.calendar=await manager.checkAccessToken(info.appInfo.accessTokenId,'ohos.permission.READ_CALENDAR')===abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED&&await manager.checkAccessToken(info.appInfo.accessTokenId,'ohos.permission.WRITE_CALENDAR')===abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;return s;
  }
  async camera(context: common.UIAbilityContext): Promise<void> {
    const result=await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context,['ohos.permission.CAMERA']);
    if(result.authResults[0]!==0) { throw new Error('相机权限未允许，可以使用相册或文件录入'); }
  }
  async notifications(context: common.UIAbilityContext): Promise<boolean> { await notificationManager.requestEnableNotification(context); return await notificationManager.isNotificationEnabled(); }
  async settings(context: common.UIAbilityContext): Promise<void> {
    const info=await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    await context.startAbility({action:'ohos.settings.app.info',parameters:{bundleName:info.name}});
  }
}
