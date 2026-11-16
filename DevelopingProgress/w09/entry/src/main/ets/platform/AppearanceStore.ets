import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Appearance, themeById } from '../ui/Appearance';

export class AppearanceStore {
  private store: preferences.Preferences | null = null;
  private writes: Promise<void> = Promise.resolve();
  async open(context: common.UIAbilityContext): Promise<Appearance> {
    this.store = await preferences.getPreferences(context, { name: 'appearance_v1' });
    const value = new Appearance();
    const theme = await this.store.get('themeId', value.themeId);
    value.themeId = themeById(typeof theme === 'string' ? theme : value.themeId).id;
    const clear = await this.store.get('clearGlass', false); value.clearGlass = clear === true;
    const motion = await this.store.get('reduceMotion', false); value.reduceMotion = motion === true;
    return value;
  }
  save(value: Appearance): Promise<void> {
    const snapshot = new Appearance(); snapshot.themeId = value.themeId;
    snapshot.clearGlass = value.clearGlass; snapshot.reduceMotion = value.reduceMotion;
    const write = this.writes.catch(() => {}).then(async () => {
      if (!this.store) { throw new Error('外观设置尚未就绪'); }
      await this.store.put('themeId', snapshot.themeId);
      await this.store.put('clearGlass', snapshot.clearGlass);
      await this.store.put('reduceMotion', snapshot.reduceMotion);
      await this.store.flush();
    });
    this.writes = write; return write;
  }
}
