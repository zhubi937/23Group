import { rankMatches } from './Association';
import { Box, OcrLine, TaskRecord, FieldCandidate, Extraction, MatchCandidate, FIELD_KEYS, FIELD_LABELS, fieldValue, setField } from './Models';

export function parsingText(text: string): string {
  return text.replace(/([\u4e00-\u9fff])\s+(?=[\u4e00-\u9fff])/g, '$1')
    .replace(/(\d)\s*([年月日.\/:：\-])\s*(?=\d)/g, '$1$2')
    .replace(/\b([GDKTZC])\s+(?=\d)/gi, '$1');
}
export function pad(n: number): string { return n.toString().padStart(2, '0'); }
export function dateText(d: Date): string { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }
export function displayAt(ts: number): string {
  if (!ts) { return '未设置'; }
  const d = new Date(ts); return dateText(d) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
}
export function validDate(y: number, m: number, d: number): boolean {
  const v = new Date(y, m - 1, d); return v.getFullYear() === y && v.getMonth() === m - 1 && v.getDate() === d;
}
// Month/day without a year is intentionally kept incomplete, never silently assigned a year.
export function parseDate(text: string, base: number): string {
  text = parsingText(text);
  let m = text.match(/(20\d{2})[年.\/-](\d{1,2})[月.\/-](\d{1,2})日?/);
  if (m) { return validDate(Number(m[1]), Number(m[2]), Number(m[3])) ? m[1] + '-' + pad(Number(m[2])) + '-' + pad(Number(m[3])) : ''; }
  m = text.match(/(?:^|[^\d])(\d{1,2})[月\/-](\d{1,2})日?/);
  if (m) { return validDate(2000, Number(m[1]), Number(m[2])) ? pad(Number(m[1])) + '-' + pad(Number(m[2])) : ''; }
  const d = new Date(base);
  if (text.includes('后天')) { d.setDate(d.getDate() + 2); return dateText(d); }
  if (text.includes('明天')) { d.setDate(d.getDate() + 1); return dateText(d); }
  if (text.includes('今天')) { return dateText(d); }
  m = text.match(/(下周|本周|周|星期)([一二三四五六日天])/);
  if (m) {
    const target = '一二三四五六日'.indexOf(m[2] === '天' ? '日' : m[2]);
    const today = (d.getDay() + 6) % 7;
    let delta = target - today;
    if (m[1] === '下周') { delta += 7; }
    else if (m[1] !== '本周' && delta < 0) { delta += 7; }
    d.setDate(d.getDate() + delta); return dateText(d);
  }
  return '';
}
export function times(text: string): string[] {
  text = parsingText(text);
  const result: string[] = [];
  const pattern = /(^|[^\d])((?:[01]?\d|2[0-3])[:：][0-5]\d)(?!\d)/g;
  let found = pattern.exec(text);
  while (found) { const v = found[2]; result.push(pad(Number(v.replace('：', ':').split(':')[0])) + ':' + v.slice(-2)); found = pattern.exec(text); }
  return result;
}
export function reminderEpoch(date: string, time: string): number {
  if (!/^20\d{2}-\d{2}-\d{2}$/.test(date) || !/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) { return 0; }
  const a = date.split('-').map((v: string) => Number(v));
  const b = time.split(':').map((v: string) => Number(v));
  return validDate(a[0], a[1], a[2]) ? new Date(a[0], a[1] - 1, a[2], b[0], b[1]).getTime() : 0;
}
export function validateTask(t: TaskRecord): string[] {
  const errors: string[] = [];
  if (!t.title.trim()) { errors.push('请填写事项标题'); }
  if (t.date && !/^20\d{2}-\d{2}-\d{2}$/.test(t.date) && !/^\d{2}-\d{2}$/.test(t.date)) { errors.push('日期格式应为 YYYY-MM-DD；年份未知可暂留 MM-DD'); }
  if (t.date && !parseDate(t.date, Date.now())) { errors.push('日期不存在，请核对原文'); }
  [t.startTime, t.endTime].forEach((v: string) => { if (v && !/^([01]\d|2[0-3]):[0-5]\d$/.test(v)) { errors.push('时间格式应为 HH:mm'); } });
  if (t.startTime && t.endTime && t.endTime < t.startTime && !/跨日|次日/.test(t.notes)) { errors.push('结束时间早于开始时间，请核对，或在备注说明跨日'); }
  if (t.deadline) {
    const m = t.deadline.match(/^(20\d{2}-\d{2}-\d{2}|\d{2}-\d{2}) (\d{2}:\d{2})$/);
    if (!m || !parseDate(m[1], Date.now()) || !/^([01]\d|2[0-3]):[0-5]\d$/.test(m[2])) { errors.push('截止时间格式应为 YYYY-MM-DD HH:mm，年份未知时可用 MM-DD HH:mm'); }
  }
  return errors;
}
export function extract(lines: OcrLine[], base: number): Extraction {
  const out = new Extraction();
  if (!lines.length) { out.warnings.push('没有识别到文字，可以手动补充'); return out; }
  const all = lines.map((v: OcrLine) => parsingText(v.text)).join('\n');
  const isTrain = /\b[GDKTZC]\d{1,5}\b/i.test(all);
  out.task.type = isTrain ? '出行' : /作业|提交|课程/.test(all) ? '作业' : /讲座|活动|会议|报告/.test(all) ? '活动' : '普通事项';
  function add(key: string, label: string, value: string, l: OcrLine | undefined, note: string = ''): void {
    if (!value) { return; }
    const old = out.fields.findIndex((f: FieldCandidate) => f.key === key);
    const f = new FieldCandidate(key, label, value, l, note);
    if (old >= 0) { out.fields[old] = f; } else { out.fields.push(f); }
    setField(out.task, key, value);
  }
  const train = lines.find((l: OcrLine) => /\b[GDKTZC]\d{1,5}\b/i.test(l.text));
  const courseHeading = lines.find((l: OcrLine) => /《[^》]{2,50}》.*(?:提交|开题|作业|通知|项目)/.test(parsingText(l.text)));
  const heading = train || courseHeading || lines.find((l: OcrLine) => {
    const text = parsingText(l.text);
    return /作业|讲座|通知|会议|活动|预约|提交材料/.test(text) && !/^(作业内容|我的作业|作业说明|活动时间|作业形式|完成指标|评分方式|教师评阅|占成绩比例|计分规则|公布成绩时间)/.test(text);
  }) || lines[0];
  const trainNo = train ? train.text.match(/\b[GDKTZC]\d{1,5}\b/i) : null;
  add('title', '标题', trainNo ? trainNo[0] + ' 出行' : parsingText(heading.text).replace(/^(标题|主题)[:：]\s*/, '').slice(0, 80), heading, trainNo ? '根据车次生成，请确认' : '规则建议，请确认');
  const course = all.match(/(?:课程|科目|项目名称)[:：]\s*([^\n，。；;]{1,40})/) || all.match(/《([^》]{2,32})》/);
  if (course) { add('context', '所属课程 / 项目', course[1].trim(), lines.find((l: OcrLine) => l.text.includes(course[1]))); }
  let startAssigned = false;
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i]; const txt = parsingText(l.text);
    const previousLabel = i > 0 ? parsingText(lines[i - 1].text) : '';
    const uncertainDeadline = /裁止/.test(txt) && /提交|报名|日期|时间/.test(txt);
    const deadline = /截止|最晚|延至|延期至/.test(txt) || uncertainDeadline || (/^(报名|提交)?截止[:：]?\s*$/.test(previousLabel));
    if (uncertainDeadline) { out.warnings.push('“裁止”可能是“截止”的识别误差，已提取候选截止时间，请对照红框核对。'); }
    const assignmentWindow = out.task.type === '作业' && /^活动时间/.test(txt) && /20\d{2}.*[-~～至].*20\d{2}/.test(txt);
    let d = parseDate(txt, base); const tt = times(txt);
    if (!d && /20\d{2}[年.\/-]\d{1,2}[月.\/-]\d{1,2}|\d{1,2}月\d{1,2}日/.test(txt)) { out.warnings.push('原文包含无效日期：' + txt); }
    if (deadline) {
      if (!d && i > 0) { d = parseDate(lines[i - 1].text, base); }
      if (d && tt.length) { add('deadline', '截止时间', d + ' ' + tt[tt.length - 1], l); }
      else { out.warnings.push('截止信息不完整，请核对：' + txt); }
    } else if (!assignmentWindow) {
      if (d && !out.task.date) { add('date', '日期', d, l, d.length === 5 ? '原文未明确年份' : /今天|明天|后天|周|星期/.test(txt) && !/\d月/.test(txt) ? '相对日期依据导入时间换算，请确认' : ''); }
      if (tt.length && !/历时|检票口|座位|乘车码/.test(txt)) {
        if (/到达|结束|终到/.test(txt) && tt.length === 1) { add('endTime', '结束时间', tt[0], l); }
        else if (!startAssigned || /出发|开始|举行/.test(txt)) {
          add('startTime', '开始时间', tt[0], l); startAssigned = true;
          if (tt.length > 1) { add('endTime', '结束时间', tt[1], l); }
        } else if (isTrain && !out.task.endTime) { add('endTime', '结束时间', tt[0], l); }
      }
    }
    const loc = txt.match(/(?:地点|会场|地址|教室)[:：]\s*(.+)/);
    if (loc) { add('location', '地点', loc[1].trim(), l); }
    if (isTrain) {
      const station = txt.match(/[\u4e00-\u9fff]{2,9}(?:东|西|南|北|站)(?=\s|[›>\/]|$)/g);
      if (station) {
        const clean = station.map((v: string) => v.replace(/^(出发|到达|始发|终到)/, ''));
        if (clean.length > 1) { add('location', '出发站', clean[0], l); add('destination', '到达站', clean[1], l); }
        else if (/到达|终到/.test(txt) || out.task.location) { add('destination', '到达站', clean[0], l); }
        else { add('location', '出发站', clean[0], l); }
      }
      if (/检票口/.test(txt)) { add('notes', '备注', txt, l); }
    }
    if (/已取消|取消通知|活动取消|取消本次/.test(txt)) { add('status', '状态', '已取消', l, '仅建议取消，需由用户确认'); }
  }
  if (!isTrain) {
    const requirements = lines.filter((l: OcrLine) => /^\s*[1-9]\s*[、.．]/.test(l.text) && /提交|材料|模板|代码仓|组长|小组/.test(parsingText(l.text)) && !/截止|裁止|最晚/.test(parsingText(l.text)));
    if (requirements.length) {
      add('notes', '备注', requirements.map((l: OcrLine) => parsingText(l.text)).join('\n').slice(0,500), requirements[0], '提交要求，请对照原文核对');
      const note = out.fields.find((f: FieldCandidate) => f.key === 'notes');
      if (note) {
        note.lineIds = requirements.map((l: OcrLine) => l.id);
        note.original = requirements.map((l: OcrLine) => l.text).join('\n');
        note.boxes = requirements.filter((l: OcrLine) => l.box.width > 0 && l.box.height > 0).map((l: OcrLine) => l.box);
      }
    }
  }
  if (out.task.date.length === 5 || /^\d{2}-\d{2} /.test(out.task.deadline)) { out.warnings.push('年份未知：事项可保存，设置提醒前需要补全年份'); }
  if (!out.task.date && !out.task.deadline) { out.warnings.push('未找到可靠日期，请补充后再设置提醒'); }
  if (isTrain && out.task.startTime && out.task.endTime) {
    const m = all.match(/历时\s*(\d+)小时\s*(\d+)分/);
    if (m) {
      const start = out.task.startTime.split(':').map((v: string) => Number(v));
      const end = out.task.endTime.split(':').map((v: string) => Number(v));
      const duration = (end[0] * 60 + end[1] - start[0] * 60 - start[1] + 1440) % 1440;
      if (duration !== Number(m[1]) * 60 + Number(m[2])) { out.warnings.push('出发、到达与历时不一致，请逐项核对'); }
    }
  }
  return out;
}
export function matchTasks(draft: TaskRecord, tasks: TaskRecord[]): MatchCandidate[] { return rankMatches(draft, tasks); }
export function changes(before: TaskRecord | null, after: TaskRecord): string[] {
  const result: string[] = [];
  FIELD_KEYS.forEach((k: string, i: number) => {
    const old = before ? fieldValue(before, k) : '';
    const value = fieldValue(after, k);
    if (old !== value) { result.push(FIELD_LABELS[i] + '：' + (old || '未填写') + ' → ' + (value || '未填写')); }
  });
  if (before) {
    const added = after.sourceIds.filter((id: string) => !before.sourceIds.includes(id));
    const removed = before.sourceIds.filter((id: string) => !after.sourceIds.includes(id));
    if (added.length) { result.push('新增来源依据（' + added.length + '份）'); }
    if (removed.length) { result.push('解除当前来源关联（' + removed.length + '份），历史仍保留'); }
  }
  return result;
}
// Only explicitly selected fields may change an associated task. Blank OCR candidates never erase old fields.
export function applySelected(existing: TaskRecord, incoming: TaskRecord, keys: string[]): TaskRecord {
  const copy = JSON.parse(JSON.stringify(existing)) as TaskRecord;
  keys.forEach((key: string) => { setField(copy, key, fieldValue(incoming, key)); });
  return copy;
}
export function scaledBox(box: Box, originalWidth: number, renderedWidth: number): Box {
  const scale = renderedWidth / Math.max(1, originalWidth);
  return new Box(box.x * scale, box.y * scale, box.width * scale, box.height * scale);
}
