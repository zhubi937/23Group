import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { common, bundleManager, abilityAccessCtrl } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import { TaskRecord } from '../domain/Models';
import { eventAt } from '../domain/Timeline';
import { BusinessError } from '@kit.BasicServicesKit';

export class Reminders {
  private context: common.UIAbilityContext|null=null;
  setContext(context: common.UIAbilityContext): void { this.context=context; }
  private async calendar(): Promise<calendarManager.Calendar> {
    if(!this.context) {throw new Error('提醒服务尚未初始化');}
    const result=await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context,['ohos.permission.READ_CALENDAR','ohos.permission.WRITE_CALENDAR']);
    if(result.authResults.some((v:number)=>v!==0)) {throw new Error('系统日历权限未允许，无法登记后台提醒');}
    const bundle=await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    const manager=calendarManager.getCalendarManager(this.context);
    const account:calendarManager.CalendarAccount={name:bundle.name+'.reminders',type:calendarManager.CalendarType.LOCAL,displayName:'截图成事'};
    let calendar:calendarManager.Calendar;
    try {calendar=await manager.getCalendar(account);}catch(_){calendar=await manager.createCalendar(account);}
    await calendar.setConfig({enableReminder:true,color:'#71846B'});return calendar;
  }
  private async calendarReminder(t: TaskRecord, at: number): Promise<number> {
    const calendar=await this.calendar();
    const start=eventAt(t)||at;
    const end=t.date&&t.endTime?new Date(t.date+'T'+t.endTime+':00').getTime():start+60000;
    const event:calendarManager.Event={type:calendarManager.EventType.NORMAL,title:'截图成事 · '+t.title,startTime:start,endTime:Math.max(end,start+60000),reminderTime:[Math.round((start-at)/60000)],location:{location:t.location},description:t.notes+'\n由截图成事登记，提前'+Math.round((start-at)/60000)+'分钟提醒',identifier:'jt:'+t.ownerId+':'+t.id+':'+at};
    const id=await calendar.addEvent(event);return -(id+2);
  }
  async publish(t: TaskRecord, at: number, context: common.UIAbilityContext, countdown: boolean = false): Promise<number> {
    this.context=context;
    if (t.status !== '待办') { throw new Error('仅待办事项可设置提醒'); }
    if (at < Date.now() + 10000) { throw new Error('提醒时间必须至少晚于当前时间10秒'); }
    await notificationManager.requestEnableNotification(context);
    const bundle=await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    const d = new Date(at);
    const request: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: { year: d.getFullYear(), month: d.getMonth() + 1, day: d.getDate(), hour: d.getHours(), minute: d.getMinutes(), second: d.getSeconds() },
      title: '截图成事 · ' + t.title.slice(0, 32), content: (t.location || '事项提醒') + ' · 点击查看',
      wantAgent: { pkgName: bundle.name, abilityName: 'EntryAbility' },
      ringDuration: 1, snoozeTimes: 0,
      actionButton: [{ title: '关闭', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }]
    };
    try {
      if (countdown) {
        const timer: reminderAgentManager.ReminderRequestTimer = {
          reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
          triggerTimeInSeconds: Math.max(10, Math.round((at - Date.now()) / 1000)),
          title: request.title, content: request.content, wantAgent: request.wantAgent,
          ringDuration: 1, actionButton: request.actionButton
        };
        return await reminderAgentManager.publishReminder(timer);
      }
      return await reminderAgentManager.publishReminder(request);
    } catch (e) {
      const error = e as BusinessError;
      if (error.code === 1700002) {
        return await this.calendarReminder(t,at);
      }
      if (error.code === 1700001 || error.code === 201) { throw new Error('系统未接受提醒，请在系统设置中允许截图成事发送通知后重试（'+error.code+'）'); }
      throw new Error('系统未接受提醒（'+error.code+'）：'+error.message);
    }
  }
  async cancel(id: number): Promise<void> {
    if(id<=-2){await (await this.calendar()).deleteEvent(-id-2);return;}
    if(id>=0){try{await reminderAgentManager.cancelReminder(id);}catch(e){if((e as BusinessError).code!==1700003){throw new Error((e as Error).message);}}}
  }
}
