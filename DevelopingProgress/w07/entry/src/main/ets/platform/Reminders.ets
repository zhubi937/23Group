import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { TaskRecord } from '../domain/Models';
import { BusinessError } from '@kit.BasicServicesKit';

export class Reminders {
  async publish(t: TaskRecord, at: number, context: common.UIAbilityContext, countdown: boolean = false): Promise<number> {
    if (t.status !== '待办') { throw new Error('仅待办事项可设置提醒'); }
    if (at < Date.now() + 10000) { throw new Error('提醒时间必须至少晚于当前时间10秒'); }
    await notificationManager.requestEnableNotification(context);
    const d = new Date(at);
    const request: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: { year: d.getFullYear(), month: d.getMonth() + 1, day: d.getDate(), hour: d.getHours(), minute: d.getMinutes(), second: d.getSeconds() },
      title: '截图成事 · ' + t.title.slice(0, 32), content: (t.location || '事项提醒') + ' · 点击查看',
      wantAgent: { pkgName: 'com.jietuchengshi.app', abilityName: 'EntryAbility' },
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
        let count = -1;
        try { count = (await reminderAgentManager.getValidReminders()).length; } catch (_) {}
        throw new Error('系统未接受提醒：提醒名额受限（1700002）'+(count >= 0 ? '，本应用已登记'+count+'条。' : '。')+'请检查设备提醒服务后重试，事项本身已保留。');
      }
      if (error.code === 1700001 || error.code === 201) { throw new Error('系统未接受提醒，请在系统设置中允许截图成事发送通知后重试（'+error.code+'）'); }
      throw new Error('系统未接受提醒（'+error.code+'）：'+error.message);
    }
  }
  async cancel(id: number): Promise<void> { if (id >= 0) { await reminderAgentManager.cancelReminder(id); } }
}
