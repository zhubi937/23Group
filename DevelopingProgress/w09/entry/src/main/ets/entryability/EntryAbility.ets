import { UIAbility, ConfigurationConstant, Configuration } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
export default class EntryAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void {
    AppStorage.setOrCreate('systemDark',this.context.config.colorMode===ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    stage.loadContent('pages/Index');
  }
  onConfigurationUpdate(config: Configuration): void { AppStorage.setOrCreate('systemDark',config.colorMode===ConfigurationConstant.ColorMode.COLOR_MODE_DARK); }
}
