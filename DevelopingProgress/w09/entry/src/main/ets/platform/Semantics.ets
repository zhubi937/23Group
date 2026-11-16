import { taskpool } from '@kit.ArkTS';
import { MlpModel, SemanticEngine, SemanticResult } from '../domain/Neural';
import { OcrLine } from '../domain/Models';
@Concurrent
function analyzeTask(classifier: string, roles: string, text: string, at: number): SemanticResult {
  const engine=new SemanticEngine();
  if(classifier && roles) {engine.classifier=JSON.parse(classifier) as MlpModel;engine.roles=JSON.parse(roles) as MlpModel;engine.ready=true;}
  return engine.analyze(text.split('\n').map((value:string,index:number)=>new OcrLine('text_'+index,value)),at);
}
export async function analyzeAsync(engine: SemanticEngine,text: string): Promise<SemanticResult> {
  const a=engine.ready?JSON.stringify(engine.classifier):'',b=engine.ready?JSON.stringify(engine.roles):'';
  return await taskpool.execute(analyzeTask,a,b,text,Date.now()) as SemanticResult;
}
