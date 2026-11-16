import { OcrLine, TaskRecord } from './Models';
import { extract, parseDate } from './Rules';
import { TASK_TYPES } from './Timeline';
export class MlpModel {
  format: string = ''; inputDim: number = 512; labels: string[] = []; sizes: number[] = []; weights: number[][] = []; biases: number[][] = [];
}
export class Prediction { label: string=''; confidence: number=0; probabilities: number[]=[]; }
export function vectorize(text: string, dim: number): number[] {
  const s=text.toLowerCase().replace(/\s/g,'').slice(0,1000); const out=new Array<number>(dim).fill(0);
  for(let n=1;n<=2;n++) { for(let i=0;i<=s.length-n;i++) { let h=2166136261; for(let j=i;j<i+n;j++) { h=Math.imul(h^s.charCodeAt(j),16777619)>>>0; } out[h%dim]++; } }
  const norm=Math.max(1,Math.sqrt(out.reduce((a:number,b:number)=>a+b*b,0))); return out.map((v:number)=>v/norm);
}
export function infer(model: MlpModel, text: string): Prediction {
  let x=vectorize(text,model.inputDim);
  for(let l=0;l<model.weights.length;l++) {
    const size=model.sizes[l+1],w=model.weights[l],b=model.biases[l]; const y=b.slice();
    for(let i=0;i<x.length;i++) { if(x[i]!==0) { for(let j=0;j<size;j++) { y[j]+=x[i]*w[i*size+j]; } } }
    x=l<model.weights.length-1?y.map((v:number)=>Math.max(0,v)):y;
  }
  const max=Math.max(...x); const exp=x.map((v:number)=>Math.exp(v-max)); const sum=exp.reduce((a:number,b:number)=>a+b,0);
  const p=new Prediction(); p.probabilities=exp.map((v:number)=>v/sum); p.confidence=Math.max(...p.probabilities); p.label=model.labels[p.probabilities.indexOf(p.confidence)]; return p;
}
export class SemanticResult {
  tasks: TaskRecord[]=[]; warnings: string[]=[]; labels: string[]=[];
}
export class SemanticEngine {
  classifier: MlpModel = new MlpModel(); roles: MlpModel = new MlpModel(); ready: boolean=false;
  analyze(lines: OcrLine[], now: number=Date.now()): SemanticResult {
    const result=new SemanticResult();
    // Explicit blank lines / numbered blocks delimit independent notices, not arbitrary OCR lines.
    const groups: OcrLine[][]=[[]];
    lines.forEach((line:OcrLine)=>{
      if(!line.text.trim() || /^【(?:事项|通知)\d+】/.test(line.text)) { if(groups[groups.length-1].length) { groups.push([]); } }
      else { line.text.replace(/\s*(提交截止日期|报名截止日期|截止日期|截止时间|提交截止|报名截止|活动时间|开始时间|结束时间|日期|时间|地点|地址|截止)[：:]/g,'\n$1：').split('\n').filter((s:string)=>!!s.trim()).forEach((s:string,i:number)=>{groups[groups.length-1].push(new OcrLine(line.id+'_'+i,s.trim()));}); }
    });
    groups.filter((g:OcrLine[])=>g.length>0).slice(0,20).forEach((group:OcrLine[])=>{
      const r=extract(group,now); const text=group.map((l:OcrLine)=>l.text).join('\n');
      result.warnings.push(...r.warnings.map((w:string)=>w.replace('对照红框核对','对照原文核对')));
      if(this.ready) {
        const cls=infer(this.classifier,text); r.task.type=cls.confidence>=.58?cls.label:'其他';
        if(cls.confidence<.7) { result.warnings.push('类型不确定，请检查这条日程的类型'); }
        let titleScore=0;
        group.forEach((line:OcrLine)=>{
          const role=infer(this.roles,line.text);
          if(role.label==='标题' && role.confidence>titleScore && role.confidence>.65) { titleScore=role.confidence; r.task.title=line.text.replace(/^(通知|安排|提醒|请留意|新消息)[：:]\s*/,'').trim().slice(0,100); }
          if(role.label==='地点' && role.confidence>.65 && !r.task.location) { r.task.location=line.text.replace(/^(地点|地址|请到)[：:\s]*/,'').trim(); }
        });
        result.labels.push(cls.label+' '+Math.round(cls.confidence*100)+'%');
      } else { r.task.type=TASK_TYPES.includes(r.task.type)?r.task.type:'其他'; result.warnings.push('语义模型未加载，当前使用规则提取'); }
      // A cropped capture may retain the end of a submission window but lose its label.
      // Keep this an explicit candidate, never an asserted deadline without a warning.
      const window=text.match(/\d{1,2}[:：]\d{2}\s*[-~～至]\s*(20\d{2}[年.\/-]\d{1,2}[月.\/-]\d{1,2}日?)\s*((?:[01]?\d|2[0-3])[:：][0-5]\d)/);
      if(r.task.type==='作业' && !r.task.deadline && /作业|提交|递交|开题/.test(text) && window) {
        const date=parseDate(window[1],now);
        if(date){r.task.deadline=date+' '+window[2].replace('：',':').padStart(5,'0');r.task.date=date;r.task.startTime='';r.task.endTime='';result.warnings.push('从提交时间范围末端推得候选截止，请对照完整原图确认；拍摄时请确保标签入镜');}
      }
      if(!r.task.title) { r.task.title=group[0].text.slice(0,100); }
      if(!r.task.date && !r.task.deadline) { result.warnings.push('请补充日期或截止时间'); }
      result.tasks.push(r.task);
    });
    if(groups.filter((g:OcrLine[])=>g.length>0).length>20) {result.warnings.push('一次最多整理20条，剩余原文仍保留，请分批录入');}
    if(!result.tasks.length) { result.tasks.push(new TaskRecord()); result.warnings.push('没有读到文字，请重试或输入原文'); }
    result.warnings=Array.from(new Set<string>(result.warnings)); return result;
  }
}
