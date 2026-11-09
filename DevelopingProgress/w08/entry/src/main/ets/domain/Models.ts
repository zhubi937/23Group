export class Box {
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
  constructor(x: number = 0, y: number = 0, width: number = 0, height: number = 0) {
    this.x = x; this.y = y; this.width = width; this.height = height;
  }
}
export class OcrLine {
  id: string = '';
  text: string = '';
  box: Box = new Box();
  words: OcrLine[] = [];
  constructor(id: string = '', text: string = '', box: Box = new Box()) {
    this.id = id; this.text = text; this.box = box;
  }
}
function evidenceText(value: string): string {
  return value.replace(/[\s年月日晚.\/:：，。；;、（）()《》「」【】\[\]\-]/g, '').toLowerCase();
}
export function evidenceBox(line: OcrLine, value: string): Box {
  const needle = evidenceText(value);
  if (!needle || !line.words || !line.words.length) { return line.box; }
  let best = line.box; let bestArea = best.width * best.height;
  for (let i = 0; i < line.words.length; i++) {
    let text = ''; let left = Number.MAX_VALUE; let top = Number.MAX_VALUE; let right = 0; let bottom = 0;
    for (let j = i; j < Math.min(line.words.length, i + 40); j++) {
      const word = line.words[j]; text += evidenceText(word.text);
      left = Math.min(left, word.box.x); top = Math.min(top, word.box.y);
      right = Math.max(right, word.box.x + word.box.width); bottom = Math.max(bottom, word.box.y + word.box.height);
      if (text.includes(needle)) {
        const area = (right - left) * (bottom - top);
        if (area > 0 && area <= bestArea) { best = new Box(left, top, right - left, bottom - top); bestArea = area; }
        break;
      }
    }
  }
  return best;
}
export class FieldCandidate {
  key: string = '';
  label: string = '';
  value: string = '';
  original: string = '';
  lineIds: string[] = [];
  boxes: Box[] = [];
  note: string = '';
  constructor(key: string, label: string, value: string, line: OcrLine | undefined, note: string = '') {
    this.key = key; this.label = label; this.value = value; this.note = note;
    if (line) { this.original = line.text; this.lineIds = [line.id]; if (line.box.width > 0 && line.box.height > 0) { this.boxes = [evidenceBox(line,value)]; } }
  }
}
export class SourceRecord {
  id: string = '';
  path: string = '';
  hash: string = '';
  name: string = '';
  width: number = 1;
  height: number = 1;
  createdAt: number = 0;
  mode: string = 'system';
  ocrState: string = 'pending';
  error: string = '';
  diagnostic: string = '';
  lines: OcrLine[] = [];
  candidates: FieldCandidate[] = [];
  tags: string[] = [];
  note: string = '';
  archived: boolean = false;
}
export class TaskRecord {
  id: string = '';
  title: string = '';
  type: string = '普通事项';
  date: string = '';
  startTime: string = '';
  endTime: string = '';
  deadline: string = '';
  location: string = '';
  destination: string = '';
  notes: string = '';
  status: string = '待办';
  sourceIds: string[] = [];
  createdAt: number = 0;
  updatedAt: number = 0;
  revision: number = 0;
  reminderId: number = -1;
  reminderAt: number = 0;
  reminderState: string = '未设置';
  context: string = '';
}
export class HistoryRecord {
  id: string = '';
  taskId: string = '';
  at: number = 0;
  action: string = '';
  changes: string[] = [];
  sourceId: string = '';
  sourceSnapshot: SourceRecord | null = null;
  before: TaskRecord | null = null;
  after: TaskRecord | null = null;
}
export class Extraction {
  fields: FieldCandidate[] = [];
  warnings: string[] = [];
  task: TaskRecord = new TaskRecord();
}
export class MatchCandidate {
  task: TaskRecord;
  score: number;
  reasons: string[];
  conflicts: string[] = [];
  level: string = '需核对';
  alreadyLinked: boolean = false;
  constructor(task: TaskRecord, score: number, reasons: string[]) {
    this.task = task; this.score = score; this.reasons = reasons;
  }
}
export function uid(prefix: string): string {
  return prefix + '_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 10);
}
export function cloneTask(t: TaskRecord): TaskRecord { return JSON.parse(JSON.stringify(t)) as TaskRecord; }
export function fieldValue(t: TaskRecord, key: string): string {
  switch (key) {
    case 'title': return t.title;
    case 'date': return t.date;
    case 'startTime': return t.startTime;
    case 'endTime': return t.endTime;
    case 'deadline': return t.deadline;
    case 'location': return t.location;
    case 'destination': return t.destination;
    case 'notes': return t.notes;
    case 'status': return t.status;
    case 'type': return t.type;
    case 'context': return t.context || '';
    default: return '';
  }
}
export function setField(t: TaskRecord, key: string, value: string): void {
  switch (key) {
    case 'title': t.title = value; break;
    case 'date': t.date = value; break;
    case 'startTime': t.startTime = value; break;
    case 'endTime': t.endTime = value; break;
    case 'deadline': t.deadline = value; break;
    case 'location': t.location = value; break;
    case 'destination': t.destination = value; break;
    case 'notes': t.notes = value; break;
    case 'status': t.status = value; break;
    case 'type': t.type = value; break;
    case 'context': t.context = value; break;
  }
}
export const FIELD_KEYS: string[] = ['title', 'date', 'startTime', 'endTime', 'deadline', 'location', 'destination', 'notes', 'status', 'type', 'context'];
export const FIELD_LABELS: string[] = ['标题', '日期', '开始时间', '结束时间', '截止时间', '地点', '到达站', '备注', '状态', '类型', '所属课程 / 项目'];
