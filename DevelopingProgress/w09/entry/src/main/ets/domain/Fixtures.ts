import { OcrLine, Box } from './Models';
// Predefined coordinates are used only by the explicitly labelled demonstration flow.
export function fixtureLines(name: string): OcrLine[] {
  const texts = name === 'train' ? ['G970', '9月10日（周四）', '10:56', '14:46', '成都东', '西安北', '历时3小时50分', '检票口：A16 / A17 / B16 / B17'] : name === 'update' ? ['移动应用设计作业延期通知', '课程：移动应用开发', '提交截止：2026年12月20日 23:59', '地点：在线提交', '请以本次延期通知为准'] : ['移动应用设计作业通知', '课程：移动应用开发', '提交截止：2026年12月18日 23:59', '地点：在线提交', '完成应用原型与工程说明'];
  const out: OcrLine[] = [];
  texts.forEach((t: string, i: number) => out.push(new OcrLine('fixture_' + i, t, new Box(60, 140 + i * 72, name === 'train' ? [140, 360, 140, 140, 180, 180, 350, 650][i] : 680, 54))));
  return out;
}
