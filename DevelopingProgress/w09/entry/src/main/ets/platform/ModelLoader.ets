import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { SemanticEngine, MlpModel } from '../domain/Neural';
export async function loadModels(context: common.UIAbilityContext): Promise<SemanticEngine> {
  const engine=new SemanticEngine();
  const a=await context.resourceManager.getRawFileContent('ml/classifier.json'); const b=await context.resourceManager.getRawFileContent('ml/roles.json');
  engine.classifier=JSON.parse(util.TextDecoder.create('utf-8').decodeToString(a)) as MlpModel;
  engine.roles=JSON.parse(util.TextDecoder.create('utf-8').decodeToString(b)) as MlpModel;
  if(engine.classifier.format!=='jt-mlp-1' || engine.roles.format!=='jt-mlp-1') { throw new Error('语义模型格式不匹配'); }
  engine.ready=true; return engine;
}
