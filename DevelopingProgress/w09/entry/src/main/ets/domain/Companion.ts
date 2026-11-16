import { TaskRecord } from './Models';
export class Profile {
  ownerId: string = 'guest';
  studentId: string = '';
  name: string = '';
  nickname: string = '';
  school: string = '西安交通大学';
  gender: string = '未设置';
  className: string = '';
  avatar: string = '叶';
  avatarPath: string = '';
}
export class Preferences {
  mode: string = 'system';
  themeId: string = 'morandi-blue';
  reduceMotion: boolean = false;
  clearGlass: boolean = false;
  notifications: boolean = false;
  reminderMinutes: number = 300;
  campusConsent: boolean = false;
}
export class Drink {
  id: string = '';
  at: number = 0;
  ml: number = 0;
}
export class CompanionState {
  drinks: Drink[] = [];
  goal: number = 1800;
  cup: number = 250;
  waterReminder: boolean = false;
  waterStart: number = 9;
  waterEnd: number = 21;
  waterInterval: number = 120;
  waterReminderIds: number[] = [];
  petName: string = '小墨';
  plantName: string = '银杏';
  pet: string = '猫';
  completedIds: string[] = [];
  strokes: string[] = [];
}
export function dayKey(at: number = Date.now()): string {
  const d = new Date(at); return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
}
export function waterTotal(s: CompanionState, day: string = dayKey()): number {
  return s.drinks.filter((d: Drink) => dayKey(d.at)===day).reduce((n: number,d: Drink) => n+d.ml,0);
}
export function addDrink(s: CompanionState, ml: number, at: number = Date.now()): CompanionState {
  if (!Number.isFinite(ml) || ml<10 || ml>2000) { throw new Error('每次记录 10–2000 mL'); }
  const next=JSON.parse(JSON.stringify(s)) as CompanionState;
  const d=new Drink(); d.id=at.toString(36)+'-'+Math.random().toString(36).slice(2,8); d.at=at; d.ml=Math.round(ml);
  next.drinks.push(d); return next;
}
export function completionReward(s: CompanionState, t: TaskRecord): CompanionState {
  const next=JSON.parse(JSON.stringify(s)) as CompanionState;
  if (t.status==='已完成' && !next.completedIds.includes(t.id)) { next.completedIds.push(t.id); }
  return next;
}
export class Fortune {
  level: string = ''; good: string[] = []; avoid: string[] = [];
}
export function fortune(owner: string, day: string = dayKey()): Fortune {
  let seed=2166136261; const text=owner+'|'+day;
  for (let i=0;i<text.length;i++) { seed=Math.imul(seed^text.charCodeAt(i),16777619)>>>0; }
  const next=(): number => { seed=(Math.imul(seed,1664525)+1013904223)>>>0; return seed; };
  const good=['先写最难的一题','备份刚写的代码','早五分钟出门','给朋友发条消息','整理一页笔记','把水杯放在手边','去图书馆坐一会儿','散步看树','提交前再读一遍','做一个小实验'];
  const avoid=['临交作业才找文件','把所有事留到明天','空腹调试程序','一口气开二十个标签页','用熬夜换效率','只看答案不看题','忘记保存文档','下雨不带伞','提交前大改代码','边走路边刷手机'];
  const f=new Fortune(); f.level=['大吉','中吉','小吉','平','小凶','凶','大凶'][next()%7];
  const g=next()%good.length,a=next()%avoid.length; f.good=[good[g],good[(g+1+next()%(good.length-1))%good.length]]; f.avoid=[avoid[a],avoid[(a+1+next()%(avoid.length-1))%avoid.length]]; return f;
}
export function waterTimes(s: CompanionState, now: number): number[] {
  const out: number[]=[];
  if (!s.waterReminder) { return out; }
  if (![s.waterStart,s.waterEnd,s.waterInterval].every((v:number)=>Number.isFinite(v)) || s.waterStart<0 || s.waterEnd>23 || s.waterStart>=s.waterEnd || s.waterInterval<30) { throw new Error('请检查喝水时段与间隔，间隔至少30分钟'); }
  for(let day=0;day<3;day++) {
    const d=new Date(now); d.setDate(d.getDate()+day); d.setHours(s.waterStart,0,0,0);
    const end=new Date(d.getTime()); end.setHours(s.waterEnd,0,0,0);
    for(let at=d.getTime();at<=end.getTime();at+=s.waterInterval*60000) { if(at>now+10000) { out.push(at); } }
  }
  return out.slice(0,12);
}
