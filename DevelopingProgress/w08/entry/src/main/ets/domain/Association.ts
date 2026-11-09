import { TaskRecord, SourceRecord, MatchCandidate } from './Models';

function normalize(text: string): string {
  return (text || '').toLowerCase().replace(/[\s，。:：、（）()·《》【】\-_/]/g, '');
}
function titleKey(text: string): string {
  return normalize(text).replace(/延期|变更|更新|通知|取消|调整|改期/g, '');
}
function dateKey(task: TaskRecord): string { return task.date || task.deadline.split(' ')[0] || ''; }
function comparableDates(a: string, b: string): boolean { return a.length === b.length && (a.length === 10 || a.length === 5); }
function trainKey(text: string): string {
  const m = text.toUpperCase().match(/\b[GDKTZC]\d{1,5}\b/); return m ? m[0] : '';
}
function similarity(a: string, b: string): number {
  if (a === b) { return 1; }
  if (a.length < 3 || b.length < 3) { return 0; }
  const grams: Set<string> = new Set<string>();
  for (let i = 0; i < a.length - 1; i++) { grams.add(a.slice(i, i + 2)); }
  const other: Set<string> = new Set<string>();
  for (let i = 0; i < b.length - 1; i++) { other.add(b.slice(i, i + 2)); }
  let shared = 0; grams.forEach((part: string) => { if (other.has(part)) { shared++; } });
  return 2 * shared / (grams.size + other.size);
}
// Fit score is an explainable ranking value, never a model probability or auto-merge permission.
export function rankMatches(draft: TaskRecord, tasks: TaskRecord[], source?: SourceRecord): MatchCandidate[] {
  const a = titleKey(draft.title); if (!a) { return []; }
  const raw = draft.title + '\n' + draft.notes + '\n' + (source ? source.lines.map((l) => l.text).join('\n') : '');
  const changeNotice = /延期|延至|改为|调整|变更|取消|推迟|更改|更新|改期|提前/.test(raw);
  const incomingDate = dateKey(draft); const incomingTrain = trainKey(draft.title);
  const seen: Set<string> = new Set<string>(); const result: MatchCandidate[] = [];
  tasks.forEach((task: TaskRecord) => {
    if (task.status === '已删除' || (task.id && seen.has(task.id))) { return; }
    if (task.id) { seen.add(task.id); }
    const linked = !!source && task.sourceIds.includes(source.id);
    const b = titleKey(task.title); const likeness = similarity(a, b);
    if (!linked && likeness < 0.6) { return; }
    const reasons: string[] = []; const conflicts: string[] = [];
    const contextA = normalize(draft.context); const contextB = normalize(task.context);
    const oldTrain = trainKey(task.title); const oldDate = dateKey(task);
    if (!linked && contextA && contextB && contextA !== contextB) { return; }
    if (!linked && incomingTrain && oldTrain && incomingTrain !== oldTrain) { return; }
    if (!linked && draft.type !== '普通事项' && task.type !== '普通事项' && draft.type !== task.type) { return; }
    if (incomingDate && oldDate && comparableDates(incomingDate, oldDate) && incomingDate !== oldDate) {
      if (!linked && !changeNotice) { return; }
      conflicts.push('日期不同：' + oldDate + ' → ' + incomingDate);
    }
    if (draft.startTime && task.startTime && draft.startTime !== task.startTime) {
      if (!linked && !changeNotice) { return; }
      conflicts.push('开始时间不同');
    }
    if (draft.deadline && task.deadline && draft.deadline !== task.deadline && !conflicts.length) {
      conflicts.push('截止时间不同');
    }
    if (draft.location && task.location && normalize(draft.location) !== normalize(task.location)) { conflicts.push('地点不同'); }
    if (a.length < 3 && !linked && !(contextA && contextA === contextB) && !(incomingDate && incomingDate === oldDate)) { return; }
    let score = a === b ? 52 : Math.round(likeness * 42);
    reasons.push(a === b ? '标题一致' : '标题相近');
    if (contextA && contextA === contextB) { score += 18; reasons.push('课程 / 项目一致'); }
    if (incomingTrain && incomingTrain === oldTrain) { score += 14; reasons.push('车次一致'); }
    if (incomingDate && incomingDate === oldDate) { score += 12; reasons.push('日期一致'); }
    if (draft.startTime && draft.startTime === task.startTime) { score += 7; reasons.push('时间一致'); }
    if (draft.location && normalize(draft.location) === normalize(task.location)) { score += 6; reasons.push('地点一致'); }
    if (draft.type === task.type) { score += 3; }
    if (task.status === '待办') { score += 3; } else { conflicts.push('原事项为' + task.status); score -= 8; }
    if (changeNotice) { reasons.push('检测到变更语义'); }
    if (linked) { score = 100; reasons.unshift('此截图已是该事项来源'); }
    else { score -= conflicts.length * 7; }
    if (score < 40 && !linked) { return; }
    const candidate = new MatchCandidate(task, Math.max(0, Math.min(100, score)), reasons);
    candidate.conflicts = conflicts; candidate.alreadyLinked = linked;
    candidate.level = linked ? '已关联' : conflicts.length ? '存在差异' : score >= 70 ? '较为匹配' : '信息待核对';
    result.push(candidate);
  });
  return result.sort((x: MatchCandidate, y: MatchCandidate) => y.score - x.score || y.task.updatedAt - x.task.updatedAt || x.task.id.localeCompare(y.task.id)).slice(0, 8);
}

export function normalizeTags(text: string): string[] {
  const tags: string[] = [];
  text.split(/[,，、\n]/).map((v: string) => v.trim().slice(0, 16)).forEach((v: string) => { if (v && !tags.includes(v) && tags.length < 6) { tags.push(v); } });
  return tags;
}
export function sourceMatches(source: SourceRecord, query: string): boolean {
  const text = [source.name, source.note || '', (source.tags || []).join(' '), source.lines.map((l) => l.text).join(' ')].join(' ').toLowerCase();
  return !query.trim() || text.includes(query.trim().toLowerCase());
}
