import { Course } from './Timeline';
export const CAMPUS_LMS: string='https://lms.xjtu.edu.cn/';
export const CAMPUS_JW: string='https://jwxt.xjtu.edu.cn/';
export function campusUrlAllowed(url: string): boolean {
  const m=/^https:\/\/([^/:?#]+)(?::443)?(?:[/?#]|$)/i.exec(url);
  return !!m && (m[1].toLowerCase()==='xjtu.edu.cn' || m[1].toLowerCase().endsWith('.xjtu.edu.cn'));
}
export function loginPage(url: string): boolean { return /\/auth\/|\/login(?:[/?#]|$)|\/oauth\/authorize/i.test(url) || /identity\d?\.xjtu|org\.xjtu/.test(url); }
export class CampusPage { text: string=''; studentId: string=''; name: string=''; authenticated: boolean=false; }
export function inspectCampusPage(text: string, url: string): CampusPage {
  const p=new CampusPage();
  if(!campusUrlAllowed(url) || loginPage(url)) { throw new Error('请先在校方页面完成登录，再打开个人课表或作业页面'); }
  p.text=text.slice(0,100000);
  const student=/(?:学号|用户名|账号)[：:\s]*([A-Za-z0-9_-]{6,30})/.exec(text);
  const name=/(?:姓名|真实姓名)[：:\s]*([^\s：:]{2,12})/.exec(text);
  p.studentId=student?student[1]:''; p.name=name?name[1]:'';
  p.authenticated=!!p.studentId && /退出|注销|个人信息|我的课表/.test(text);
  return p;
}
export function parseIcs(text: string): Course[] {
  const out: Course[]=[]; const blocks=text.replace(/\r?\n[ \t]/g,'').split('BEGIN:VEVENT').slice(1);
  const get=(block:string,key:string):string=>{ const m=new RegExp('(?:^|\\n)'+key+'(?:;[^:]*)?:([^\\r\\n]*)').exec(block); return m?m[1].replace(/\\n/g,' ').replace(/\\,/g,',').replace(/\\;/g,';'):''; };
  const dt=(v:string):string=>{ const m=/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?$/.exec(v); if(!m) { return ''; } const d=new Date(m[1]+'-'+m[2]+'-'+m[3]+'T'+m[4]+':'+m[5]+':'+(m[6]||'00')+(m[7]||'')); if(!Number.isFinite(d.getTime())) { return ''; } return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')+' '+String(d.getHours()).padStart(2,'0')+':'+String(d.getMinutes()).padStart(2,'0'); };
  blocks.slice(0,1000).forEach((block:string)=>{ const t=new Course(); t.id=get(block,'UID'); t.name=get(block,'SUMMARY'); t.location=get(block,'LOCATION'); const start=dt(get(block,'DTSTART')),end=dt(get(block,'DTEND')); t.date=start.slice(0,10); t.start=start.slice(11,16); t.end=end.slice(11,16); if(t.name && t.date) { out.push(t); } });
  return out;
}
