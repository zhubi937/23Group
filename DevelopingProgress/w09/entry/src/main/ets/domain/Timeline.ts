import { TaskRecord, cloneTask, FIELD_KEYS, fieldValue, setField } from './Models';
export const TASK_TYPES: string[]=['作业','出行','会议','活动','考试','其他'];
export function eventAt(t: TaskRecord): number {
  const timed=t.date&&t.startTime?t.date+' '+t.startTime:'';
  const value=t.type==='作业'?(t.deadline||timed):(timed||t.deadline);
  const m=/^(\d{4})-(\d{2})-(\d{2}) ([01]\d|2[0-3]):([0-5]\d)$/.exec(value);
  if(!m) {return 0;}
  const d=new Date(Number(m[1]),Number(m[2])-1,Number(m[3]),Number(m[4]),Number(m[5]));
  if(d.getFullYear()!==Number(m[1])||d.getMonth()+1!==Number(m[2])||d.getDate()!==Number(m[3])) {return 0;}
  return d.getTime();
}
export function timeConflicts(draft: TaskRecord, tasks: TaskRecord[]): TaskRecord[] {
  if(!draft.date || !draft.startTime || draft.status!=='待办') { return []; }
  const start=eventAt(Object.assign(new TaskRecord(),draft,{deadline:''}));
  let end=draft.endTime?new Date(draft.date+'T'+draft.endTime+':00').getTime():start+3600000;
  if(end<start && /跨日|次日/.test(draft.notes)) {end+=86400000;}
  return tasks.filter((t:TaskRecord) => {
    if(t.id===draft.id || t.status!=='待办' || !t.date || !t.startTime) { return false; }
    const a=eventAt(Object.assign(new TaskRecord(),t,{deadline:''}));
    let b=t.endTime?new Date(t.date+'T'+t.endTime+':00').getTime():a+3600000;
    if(b<a && /跨日|次日/.test(t.notes)) {b+=86400000;}
    return start<b && end>a;
  });
}
export function mergeUpdate(existing: TaskRecord, incoming: TaskRecord, keys: string[]): TaskRecord {
  const t=cloneTask(existing);
  keys.filter((k:string)=>FIELD_KEYS.includes(k)).forEach((k:string)=>setField(t,k,fieldValue(incoming,k)));
  return t;
}
export function updateIntent(text: string): string {
  if(/取消|终止|不再举行|无需参加/.test(text)) { return '取消'; }
  if(/延期|推迟|提前|改至|改为|变更|改到|调整/.test(text)) { return '变更'; }
  return '新建';
}
export class Course {
  id: string = ''; name: string = ''; teacher: string = ''; location: string = ''; date: string = ''; start: string = ''; end: string = '';
}
