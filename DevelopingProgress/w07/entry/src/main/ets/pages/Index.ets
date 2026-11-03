import { KeyboardAvoidMode } from '@kit.ArkUI';
import { canCommitText } from '../domain/TextEntry';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Repository } from '../data/Repository';
import { Images } from '../platform/Images';
import { Recognition } from '../platform/Recognition';
import { Reminders } from '../platform/Reminders';
import { TaskRecord, SourceRecord, HistoryRecord, FieldCandidate, Box, MatchCandidate, OcrLine, FIELD_KEYS, FIELD_LABELS, cloneTask, fieldValue, setField } from '../domain/Models';
import { extract, validateTask, matchTasks, applySelected, displayAt, scaledBox, reminderEpoch } from '../domain/Rules';
import { fixtureLines } from '../domain/Fixtures';
const PAPER: string = '#F5F3EE';
const INK: string = '#292D30';
const MUTED: string = '#78746C';
const RED: string = '#C72C33';
const BORDER: string = '#DEDAD2';
@Entry
@Component
struct Index {
  @State ready: boolean = false;
  @State busy: boolean = false;
  @State screen: string = 'home';
  @State tab: string = '事项';
  @State query: string = '';
  @State filter: string = '全部';
  @State taskList: TaskRecord[] = [];
  @State sources: SourceRecord[] = [];
  @State draft: TaskRecord = new TaskRecord();
  @State detail: TaskRecord = new TaskRecord();
  @State active: SourceRecord = new SourceRecord();
  @State historyList: HistoryRecord[] = [];
  @State candidates: FieldCandidate[] = [];
  @State warnings: string[] = [];
  @State matches: MatchCandidate[] = [];
  @State targetId: string = '';
  @State selectedKeys: string[] = [];
  @State focusKey: string = '';
  @State boxes: Box[] = [];
  @State previewWidth: number = 1;
  @State showOriginal: boolean = false;
  @State reminderDate: string = '';
  @State reminderTime: string = '';
  @State statusMessage: string = '';
  @State manualText: string = '';
  private scroller: Scroller = new Scroller();
  private repo: Repository = new Repository();
  private recognition: Recognition = new Recognition();
  private reminders: Reminders = new Reminders();
  private context: common.UIAbilityContext | null = null;
  private images: Images | null = null;
  aboutToAppear(): void { this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE); this.initialize(); }
  onBackPress(): boolean {
    if (this.screen !== 'home') { this.scroller.scrollTo({ xOffset:0,yOffset:0 }); this.screen = 'home'; return true; }
    return false;
  }
  private toast(s: string): void { this.statusMessage = s; this.getUIContext().getPromptAction().showToast({ message: s, duration: 3000 }); }
  private fail(e: Object): void { const err = e as BusinessError; this.toast(err.message || String(e)); }
  private async initialize(): Promise<void> {
    try {
      this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.recognition.setContext(this.context); this.images = new Images(this.context); await this.repo.open(this.context); await this.reload(); this.ready = true;
    } catch (e) { this.fail(e); }
  }
  private async reload(): Promise<void> { this.taskList = await this.repo.tasks(); this.sources = await this.repo.sources(); }
  private visibleTasks(): TaskRecord[] {
    const q = this.query.trim().toLowerCase();
    return this.taskList.filter((t: TaskRecord) => (this.filter === '全部' || t.status === this.filter) && (!q || [t.title,t.type,t.date,t.deadline,t.location,t.notes].join(' ').toLowerCase().includes(q)));
  }
  private pendingCount(): number { return this.taskList.filter((t: TaskRecord) => t.status === '待办').length; }
  private async importPicture(): Promise<void> {
    if (this.busy || !this.images) { return; } this.busy = true;
    try {
      const uri = await this.images.choose(); if (!uri) { return; }
      const s = await this.images.importUri(uri); const old = await this.repo.byHash(s.hash);
      if (old) { this.images.remove(s); if (old.mode !== 'manual' && old.ocrState !== 'recognized' && old.mode !== 'example') { await this.recognition.run(old); await this.repo.putSource(old); await this.reload(); } this.openReview(old); this.toast('这张截图已导入，已打开原来的来源'); return; }
      await this.repo.putSource(s); await this.recognition.run(s); await this.repo.putSource(s); await this.reload(); this.openReview(s);
      if (s.error) { this.toast('图片识别未完成，可重试或补充原文'); }
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async loadSample(name: string): Promise<void> {
    if (this.busy || !this.images) { return; } this.busy = true;
    try {
      const s = await this.images.sample(name); const old = await this.repo.byHash(s.hash);
      if (old) { this.images.remove(s); this.openReview(old); return; }
      s.mode = 'example'; s.name = name === 'train' ? '演示样例 · 出行' : name === 'update' ? '演示样例 · 作业延期' : '演示样例 · 作业通知';
      s.lines = fixtureLines(name); s.ocrState = 'example'; s.candidates = extract(s.lines,s.createdAt).fields;
      await this.repo.putSource(s); await this.reload(); this.openReview(s);
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private openReview(s: SourceRecord): void {
    if (s.ocrState === 'unavailable') { s.error = '本图尚未转写，可点击下方的本机离线识别。'; }
    this.active = s; this.showOriginal = s.mode === 'example'; const r = extract(s.lines,s.createdAt || Date.now());
    if (!s.lines.length && s.ocrState === 'unavailable') { r.warnings = ['请补充通知原文，或直接填写下方事项字段。']; }
    this.draft = r.task; this.candidates = r.fields; this.warnings = r.warnings; this.targetId = ''; this.focusKey = ''; this.boxes = [];
    this.selectedKeys = r.fields.map((f: FieldCandidate) => f.key); this.matches = matchTasks(this.draft,this.taskList); this.manualText = s.lines.map((l: OcrLine) => l.text).join('\n'); this.scroller.scrollTo({ xOffset:0,yOffset:0 }); this.screen = 'review';
  }
  private newTask(): void { this.openReview(new SourceRecord()); this.warnings = []; }
  private updateField(key: string, value: string): void {
    const t = cloneTask(this.draft); setField(t,key,value); this.draft = t;
    if (!this.selectedKeys.includes(key)) { this.selectedKeys = [...this.selectedKeys,key]; }
  }
  private selectField(key: string): void {
    this.focusKey = key; const f = this.candidates.find((v: FieldCandidate) => v.key === key); this.boxes = f ? f.boxes : []; if (this.boxes.length) { this.showOriginal = true; setTimeout(() => { this.scroller.scrollTo({ xOffset:0,yOffset:0 }); },80); }
    if (!f || !this.boxes.length) { this.toast('此字段没有对应的图像坐标，可对照原图手工核对'); }
  }
  private async extractManual(): Promise<void> {
    if (this.busy || !this.manualText.trim()) { return; } this.busy = true;
    try {
      const lines: OcrLine[] = [];
      this.manualText.split('\n').filter((v: string) => v.trim().length > 0).forEach((v: string, i: number) => { lines.push(new OcrLine('manual_'+i,v.trim(),new Box())); });
      this.active.lines = lines; this.active.mode = 'manual'; this.active.ocrState = 'manual'; this.active.error = '';
      this.active.candidates = extract(lines,this.active.createdAt || Date.now()).fields;
      if (this.active.id) { await this.repo.putSource(this.active); await this.reload(); }
      this.openReview(this.active); this.toast('已按手工文字整理，请对照原图确认，未生成图像坐标');
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async recognizeAgain(): Promise<void> {
    if (this.busy || !this.active.id) { return; } this.busy = true;
    try { await this.recognition.run(this.active); await this.repo.putSource(this.active); await this.reload(); this.openReview(this.active); }
    catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async confirm(message: string, label: string): Promise<boolean> {
    const r = await this.getUIContext().getPromptAction().showDialog({ title: '请确认',message,buttons: [{ text:'取消',color:MUTED },{ text:label,color:RED }] }); return r.index === 1;
  }
  private async saveReview(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      let t = cloneTask(this.draft); let action = t.id ? '人工编辑' : '确认新建';
      if (this.targetId) {
        const existing = this.taskList.find((v: TaskRecord) => v.id === this.targetId);
        if (!existing) { throw new Error('所关联的事项已不存在'); }
        if (existing.reminderId >= 0) { throw new Error('请先到原事项中取消提醒，再确认变更，避免旧时间继续触发'); }
        if (!this.selectedKeys.length) { throw new Error('请至少勾选一个需要采用的字段'); }
        t = applySelected(existing,this.draft,this.selectedKeys); action = '确认关联并更新';
        const preview = this.selectedKeys.map((key: string) => FIELD_LABELS[FIELD_KEYS.indexOf(key)]+'：'+(fieldValue(existing,key)||'未填写')+' → '+(fieldValue(t,key)||'未填写')).join('\n');
        if (!await this.confirm('将更新“'+existing.title+'”\n'+preview+'\n原来的来源和历史会保留。','确认更新')) { return; }
      }
      const errors = validateTask(t); if (errors.length) { throw new Error(errors.join('\n')); }
      const saved = await this.repo.saveTask(t,action,this.active.id ? this.active : null);
      await this.reload(); await this.openDetail(saved); this.toast('已保存事项与来源依据');
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async openDetail(t: TaskRecord): Promise<void> {
    this.detail = cloneTask(t); this.historyList = await this.repo.history(t.id); const due = t.deadline.split(' '); this.reminderDate = t.date.length === 10 ? t.date : (due[0] && due[0].length === 10 ? due[0] : ''); this.reminderTime = t.startTime || due[1] || '09:00'; this.scroller.scrollTo({ xOffset:0,yOffset:0 }); this.screen = 'detail';
  }
  private editDetail(): void {
    if (this.detail.reminderId >= 0) { this.toast('编辑前请先取消已设置的提醒'); return; }
    this.active = new SourceRecord(); this.draft = cloneTask(this.detail); this.candidates = []; this.matches = []; this.targetId = ''; this.boxes = []; this.warnings = []; this.selectedKeys = FIELD_KEYS.slice(); this.scroller.scrollTo({ xOffset:0,yOffset:0 }); this.screen = 'review';
  }
  private async cancelReminder(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      await this.reminders.cancel(this.detail.reminderId); const t = cloneTask(this.detail); t.reminderId = -1; t.reminderAt = 0; t.reminderState = '未设置';
      const saved = await this.repo.saveTask(t,'取消系统提醒'); await this.reload(); await this.openDetail(saved); this.toast('已取消提醒');
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async setReminder(test: boolean = false): Promise<void> {
    if (this.busy || !this.context) { return; } this.busy = true;
    try {
      if (this.detail.reminderId >= 0) { throw new Error('请先取消原提醒，再重新设置'); }
      const at = test ? Date.now()+60000 : reminderEpoch(this.reminderDate,this.reminderTime);
      if (!at) { throw new Error('请填写完整且有效的提醒日期和时间'); }
      const id = await this.reminders.publish(this.detail,at,this.context,test); const t = cloneTask(this.detail); t.reminderId = id; t.reminderAt = at; t.reminderState = '已设置';
      try { const saved = await this.repo.saveTask(t,'设置系统提醒'); await this.reload(); await this.openDetail(saved); }
      catch (e) { await this.reminders.cancel(id); throw new Error((e as Error).message || String(e)); }
      this.toast('提醒已设置，系统将在指定时间通知');
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async changeStatus(status: string): Promise<void> {
    if (this.busy) { return; }
    if (status === '已删除' && !await this.confirm('删除后将从列表移除，来源和修改历史仍保留。','删除事项')) { return; }
    this.busy = true;
    try {
      const t = cloneTask(this.detail); if (t.reminderId >= 0) { await this.reminders.cancel(t.reminderId); t.reminderId = -1; t.reminderState = '未设置'; t.reminderAt = 0; }
      t.status = status; const saved = await this.repo.saveTask(t,status === '已删除' ? '删除事项' : '状态变更'); await this.reload();
      if (status === '已删除') { this.screen = 'home'; } else { await this.openDetail(saved); } this.toast('已更新事项状态');
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async deleteSource(s: SourceRecord): Promise<void> {
    if (this.busy || !this.images || !await this.confirm('仅删除未被事项引用的来源及其本地副本。','删除来源')) { return; }
    this.busy = true;
    try { await this.repo.removeSource(s.id); this.images.remove(s); await this.reload(); this.toast('来源已删除'); }
    catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async clearAll(): Promise<void> {
    if (this.busy || !this.images || !await this.confirm('将永久清空本应用中的事项、历史、截图副本，并取消已记录的提醒。无法撤销。','清空本地数据')) { return; }
    this.busy = true;
    try {
      for (const t of await this.repo.tasks(true)) { await this.reminders.cancel(t.reminderId); }
      await this.repo.clear(); this.images.clearSources();
      await this.reload(); this.toast('本地数据已清空');
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  @Builder
  sectionTitle(label: string, caption: string) {
    Column({ space: 8 }) {
      Text(label).fontSize(26).fontWeight(FontWeight.Bold).fontColor(INK).fontFamily('serif')
      if (caption) { Text(caption).fontSize(13).fontColor(MUTED).lineHeight(21) }
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
  @Builder
  smallButton(label: string, action: () => void, primary: boolean = false) {
    Button(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(primary ? '#FFFFFF' : RED).backgroundColor(primary ? RED : '#EEE8DF').borderRadius(8).height(42).padding({ left:17,right:17 }).margin({ right:8,bottom:8 }).enabled(!this.busy).onClick(action)
  }
  @Builder
  backHeader(title: string) {
    Row() { Text('‹ 返回').fontSize(15).fontColor(RED).onClick(() => { this.screen = 'home'; }); Blank(); Text(title).fontSize(16).fontColor(INK) }.width('100%').padding({ bottom:18 })
  }
  @Builder
  sampleActions() {
    Column({ space: 14 }) {
      Text('用自制样例体验').fontSize(16).fontColor(INK).fontWeight(FontWeight.Medium)
      Text('样例带有预置文字与坐标，并非系统OCR结果。').fontSize(12).fontColor(MUTED)
      Flex({ wrap: FlexWrap.Wrap }) {
        this.smallButton('出行截图',() => { this.loadSample('train'); })
        this.smallButton('作业通知',() => { this.loadSample('notice'); })
        this.smallButton('延期通知',() => { this.loadSample('update'); })
      }
    }.alignItems(HorizontalAlign.Start).width('100%').padding({ top:18,bottom:12 })
  }
  @Builder
  homePage() {
    Column({ space: 20 }) {
      this.sectionTitle('把截图，变成安排','通知里的时间与地点，整理后再确认。')
      Row({ space: 8 }) {
        Text(this.pendingCount().toString()).fontSize(44).fontColor(RED).fontFamily('serif')
        Text('件待办').fontSize(13).fontColor(MUTED)
        Blank()
        this.smallButton('导入截图',() => { this.importPicture(); },true)
        this.smallButton('新建',() => { this.newTask(); })
      }.width('100%')
      Search({ value:this.query,placeholder:'搜索标题、日期、地点或备注' }).height(44).backgroundColor('#EBE8E1').enablePreviewText(true).onChange((v: string,p?: PreviewText) => { if (canCommitText(p?.value)) { this.query = v; } })
      Row({ space: 22 }) {
        ForEach(['全部','待办','已完成','已取消'],(v: string) => {
          Text(v).fontSize(14).fontColor(this.filter === v ? RED : MUTED).fontWeight(this.filter === v ? FontWeight.Bold : FontWeight.Normal).padding({ bottom:10 }).border({ width:{ bottom:this.filter === v ? 2 : 0 },color:RED }).onClick(() => { this.filter = v; })
        })
      }.width('100%')
      if (!this.visibleTasks().length) {
        Column({ space: 16 }) {
          Text(this.taskList.length ? '没有匹配的事项' : '从一张截图开始').fontSize(24).fontFamily('serif').fontColor(INK)
          Text('导入后查看原文依据，确认每一项信息，再加入你的安排。').fontSize(14).fontColor(MUTED).lineHeight(24)
        }.padding({ top:26,bottom:26 }).width('100%').alignItems(HorizontalAlign.Start)
      }
      ForEach(this.visibleTasks(),(t: TaskRecord) => {
        Column({ space: 9 }) {
          Row() { Text(t.type).fontSize(12).fontColor(RED); Blank(); Text(t.status).fontSize(12).fontColor(MUTED) }.width('100%')
          Text(t.title).fontSize(21).fontColor(INK).fontWeight(FontWeight.Medium).maxLines(2).textOverflow({ overflow:TextOverflow.Ellipsis })
          Text(t.deadline ? '截止 '+t.deadline : (t.date||'日期待补充')+(t.startTime ? '  '+t.startTime : '')).fontSize(14).fontColor(MUTED)
          if (t.location) { Text(t.location+(t.destination ? ' · 到达 '+t.destination : '')).fontSize(14).fontColor(MUTED) }
          Row() {
            Text(t.sourceIds.length+' 份来源依据').fontSize(12).fontColor(MUTED)
            Blank()
            if (t.reminderId >= 0) { Text('已设置提醒').fontSize(12).fontColor(RED) }
            Text('查看 ›').fontSize(13).fontColor(RED).margin({ left:14 })
          }.width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ top:18,bottom:20 }).border({ width:{ bottom:1 },color:BORDER }).onClick(() => { this.openDetail(t); })
      },(t: TaskRecord) => t.id+'_'+t.revision)
      if (!this.taskList.length) { this.sampleActions() }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  sourcesPage() {
    Column({ space: 20 }) {
      this.sectionTitle('原文一直在','截图副本只保存在本机。重新打开可核对或关联已有事项。')
      this.smallButton('导入截图',() => { this.importPicture(); },true)
      ForEach(this.sources,(s: SourceRecord) => {
        Row({ space: 14 }) {
          Image('file://'+s.path).width(64).height(86).objectFit(ImageFit.Contain).backgroundColor('#FFFFFF').borderRadius(4)
          Column({ space: 8 }) {
            Text(s.name).fontSize(16).fontColor(INK).maxLines(2)
            Text(s.mode === 'example' ? '演示样例 · 预置坐标' : s.mode === 'manual' ? '手工补充 · 无图像坐标' : s.mode === 'offline' ? '本机离线OCR · '+s.lines.length+'段原文' : s.ocrState === 'unavailable' ? '待重新识别' : s.ocrState === 'recognized' ? '系统OCR · '+s.lines.length+'段原文' : '待补充或重新识别').fontSize(12).fontColor(s.mode === 'example' ? RED : MUTED)
            Row({ space: 20 }) {
              Text('打开核对 ›').fontSize(14).fontColor(RED).onClick(() => { this.openReview(s); })
              Text('删除').fontSize(12).fontColor(MUTED).onClick(() => { this.deleteSource(s); })
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').padding({ bottom:16 }).border({ width:{ bottom:1 },color:BORDER })
      },(s: SourceRecord) => s.id+s.ocrState)
      this.sampleActions()
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  settingsPage() {
    Column({ space: 22 }) {
      this.sectionTitle('留在本机，随时可查','截图成事 · 第7周整合版 · 0.7.2')
      Text('图片、识别片段、事项和更新历史保存在应用本地。无需账号，不上传图片，也不接入云端AI。').fontSize(15).fontColor(INK).lineHeight(26)
      Divider().color(BORDER)
      Text('中文输入').fontSize(19).fontColor(INK)
      Text('可使用系统中文拼音选词，也支持复制粘贴中文。使用电脑键盘时，请让拼音字母进入模拟器中的中文输入法，再选择候选词。').fontSize(14).fontColor(MUTED).lineHeight(24)
      Text('提醒与权限').fontSize(19).fontColor(INK)
      Text('设置提醒时，系统会请求通知授权。修改已设置提醒的事项前，请先取消原提醒，再按新时间设置。').fontSize(14).fontColor(MUTED).lineHeight(24)
      Text('当前范围').fontSize(19).fontColor(INK)
      Text('支持截图整理、原文核对、基础关联、变更历史与系统提醒。校园同步、模型增强和备份恢复将按后续计划继续开发。').fontSize(14).fontColor(MUTED).lineHeight(24)
      Text('本地保存：'+this.taskList.length+' 个事项 / '+this.sources.length+' 份来源').fontSize(14).fontColor(MUTED)
      this.smallButton('清空全部本地数据',() => { this.clearAll(); })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  preview() {
    if (this.active.path) {
      Column({ space: 10 }) {
        Text(this.active.mode === 'example' ? '自制演示样例 · 非系统识别结果' : this.active.mode === 'manual' ? '手工补充文字 · 未生成图像坐标' : this.active.mode === 'offline' ? '本机离线识别 · 点击字段查看红框' : '原图依据 · 点击下方字段查看红框').fontSize(12).fontColor(this.active.mode === 'example' ? RED : MUTED)
        Button(this.showOriginal ? '收起原图' : '查看原图').fontSize(13).fontColor(RED).backgroundColor('#EEE8DF').height(36).borderRadius(6).onClick(() => { this.showOriginal = !this.showOriginal; })
        if (this.showOriginal) {
        Stack({ alignContent: Alignment.TopStart }) {
          Image('file://'+this.active.path).width('100%').aspectRatio(this.active.width/Math.max(1,this.active.height)).objectFit(ImageFit.Contain)
          ForEach(this.boxes,(box: Box) => {
            Rect().width(scaledBox(box,this.active.width,this.previewWidth).width).height(scaledBox(box,this.active.width,this.previewWidth).height).fill('#18C72C33').stroke(RED).strokeWidth(2).position({ x:scaledBox(box,this.active.width,this.previewWidth).x,y:scaledBox(box,this.active.width,this.previewWidth).y }).hitTestBehavior(HitTestMode.None)
          })
        }.width('100%').aspectRatio(this.active.width/Math.max(1,this.active.height)).backgroundColor('#FFFFFF').onAreaChange((_old: Area,next: Area) => { this.previewWidth = Number(next.width); })
        }
        if (this.active.error) { Text(this.active.error).fontSize(12).fontColor(RED).lineHeight(20) }
        if (this.active.id) { this.smallButton('识别图片（系统 / 本机离线）',() => { this.recognizeAgain(); }) }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }
  @Builder
  editor(key: string,label: string) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        if (this.targetId) {
          Checkbox({ name:key }).select(this.selectedKeys.includes(key)).selectedColor(RED).width(20).height(20).onChange((checked: boolean) => { this.selectedKeys = checked ? [...this.selectedKeys.filter((v: string) => v !== key),key] : this.selectedKeys.filter((v: string) => v !== key); })
        }
        Text(label).fontSize(14).fontColor(this.focusKey === key ? RED : MUTED).onClick(() => { this.selectField(key); })
        Blank()
        if (this.candidates.some((f: FieldCandidate) => f.key === key)) { Text('定位原文 ↗').fontSize(12).fontColor(RED).onClick(() => { this.selectField(key); }) }
      }.width('100%')
      if (key === 'notes') {
        TextArea({ text:fieldValue(this.draft,key),placeholder:'可补充提交要求或备注' }).id('field-notes').fontSize(15).fontColor(INK).backgroundColor('#FFFFFF').borderRadius(6).height(136).maxLength(500).border({ width:1,color:this.focusKey === key ? RED : BORDER }).type(TextAreaType.NORMAL).enablePreviewText(true).onChange((v: string,p?: PreviewText) => { if (canCommitText(p?.value)) { this.updateField(key,v); } })
      } else {
        TextInput({ text:fieldValue(this.draft,key),placeholder:key === 'date' ? 'YYYY-MM-DD；年份未知可留 MM-DD' : key === 'deadline' ? 'YYYY-MM-DD HH:mm' : key === 'startTime'||key === 'endTime' ? 'HH:mm' : '未识别到，可手动填写' }).id('field-'+key).fontSize(16).fontColor(INK).backgroundColor('#FFFFFF').borderRadius(6).height(46).maxLength(120).border({ width:1,color:this.focusKey === key ? RED : BORDER }).type(InputType.Normal).enablePreviewText(true).onChange((v: string,p?: PreviewText) => { if (canCommitText(p?.value)) { this.updateField(key,v); } })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  reviewPage() {
    Column({ space: 20 }) {
      this.backHeader(this.draft.id ? '编辑事项' : '核对截图')
      this.sectionTitle('确认之后，再入安排','原文片段与事项字段分别保存；缺失内容由你补充。')
      this.preview()
      if (this.active.ocrState === 'recognized') { Text('识别原文（可修正；按文字重新整理后标记为手工补充）').fontSize(13).fontColor(MUTED) }
      if (this.active.path && (this.active.ocrState === 'recognized' || this.active.ocrState === 'unavailable' || this.active.ocrState === 'failed' || this.active.ocrState === 'empty' || this.active.ocrState === 'manual')) {
        TextArea({ text:this.manualText,placeholder:'可手工输入或粘贴原文，每行一段。例如：提交截止：2026年12月18日 23:59' }).fontSize(14).height(130).backgroundColor('#FFFFFF').id('manual-original-text').type(TextAreaType.NORMAL).enablePreviewText(true).onChange((v: string,p?: PreviewText) => { if (canCommitText(p?.value)) { this.manualText = v; } })
        this.smallButton('按补充文字整理字段',() => { this.extractManual(); })
      }
      ForEach(this.warnings,(v: string) => { Text(v).fontSize(13).fontColor(RED).lineHeight(22) })
      if (this.active.id && this.matches.length && !this.draft.id) {
        Column({ space: 12 }) {
          Text('可能是同一件事').fontSize(19).fontColor(INK)
          Text('选择关联后，仅勾选的字段会更新；其余内容继续保留。').fontSize(12).fontColor(MUTED).lineHeight(20)
          Text((!this.targetId ? '● ' : '○ ')+'保存为新事项').fontSize(15).fontColor(!this.targetId ? RED : INK).onClick(() => { this.targetId = ''; })
          ForEach(this.matches,(m: MatchCandidate) => {
            Column({ space: 5 }) {
              Text((this.targetId === m.task.id ? '● ' : '○ ')+m.task.title).fontSize(15).fontColor(this.targetId === m.task.id ? RED : INK)
              Text(m.reasons.join('，')+' · '+(m.task.deadline||m.task.date||'日期未填')).fontSize(12).fontColor(MUTED)
            }.width('100%').alignItems(HorizontalAlign.Start).onClick(() => { this.targetId = m.task.id; })
          })
        }.width('100%').alignItems(HorizontalAlign.Start).padding(16).backgroundColor('#ECE7DE').borderRadius(8)
      }
      ForEach(FIELD_KEYS.slice(0,8),(key: string,i: number) => { this.editor(key,FIELD_LABELS[i]) })
      Row({ space: 12 }) {
        Text('状态').fontSize(14).fontColor(MUTED)
        Select([{ value:'待办' },{ value:'已完成' },{ value:'已取消' }]).value(this.draft.status).onSelect((_i: number,v: string) => { this.updateField('status',v); }).fontColor(INK).backgroundColor('#FFFFFF')
        Blank()
        Select([{ value:'普通事项' },{ value:'出行' },{ value:'活动' },{ value:'作业' }]).value(this.draft.type).onSelect((_i: number,v: string) => { this.updateField('type',v); }).font({ size:14 }).fontColor(INK).backgroundColor('#FFFFFF')
      }.width('100%')
      if (this.targetId) {
        Row({ space:12 }) {
          Checkbox({ name:'status-update' }).select(this.selectedKeys.includes('status')).selectedColor(RED).onChange((v: boolean) => { this.selectedKeys = v ? [...this.selectedKeys.filter((k: string) => k !== 'status'),'status'] : this.selectedKeys.filter((k: string) => k !== 'status'); })
          Text('采用上述状态').fontSize(13).fontColor(MUTED)
          Checkbox({ name:'type-update' }).select(this.selectedKeys.includes('type')).selectedColor(RED).onChange((v: boolean) => { this.selectedKeys = v ? [...this.selectedKeys.filter((k: string) => k !== 'type'),'type'] : this.selectedKeys.filter((k: string) => k !== 'type'); })
          Text('采用上述类型').fontSize(13).fontColor(MUTED)
        }.width('100%')
      }
      Button(this.targetId ? '确认关联并更新' : '确认并保存事项').fontSize(15).fontColor('#FFFFFF').backgroundColor(RED).borderRadius(8).height(46).padding({ left:18,right:18 }).enabled(!this.busy).onClick(() => { this.saveReview(); })
      Text('保存即确认本页信息。可在事项详情中查看来源与历次变更。').fontSize(12).fontColor(MUTED).lineHeight(21)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  detailPage() {
    Column({ space: 20 }) {
      this.backHeader('事项详情')
      Column({ space:8 }) {
        Text(this.detail.title).fontSize(26).fontWeight(FontWeight.Bold).fontColor(INK).fontFamily('serif')
        Text(this.detail.type+' · '+this.detail.status).fontSize(13).fontColor(MUTED)
      }.alignItems(HorizontalAlign.Start).width('100%')
      ForEach(FIELD_KEYS.slice(1,8),(key: string,i: number) => {
        if (fieldValue(this.detail,key)) {
          Row({ space: 16 }) { Text(FIELD_LABELS[i+1]).fontSize(14).fontColor(MUTED).width(80); Text(fieldValue(this.detail,key)).fontSize(16).fontColor(INK).layoutWeight(1) }.width('100%')
        }
      })
      Flex({ wrap:FlexWrap.Wrap }) {
        this.smallButton('编辑',() => { this.editDetail(); })
        Button(this.detail.status === '已完成' ? '恢复待办' : '标记完成').fontSize(14).fontColor(RED).backgroundColor('#EEE8DF').borderRadius(8).height(42).padding({ left:17,right:17 }).margin({ right:8,bottom:8 }).enabled(!this.busy).onClick(() => { this.changeStatus(this.detail.status === '已完成' ? '待办' : '已完成'); })
        this.smallButton('取消事项',() => { this.changeStatus('已取消'); })
        this.smallButton('删除',() => { this.changeStatus('已删除'); })
      }
      Divider().color(BORDER)
      Text('系统提醒').fontSize(21).fontFamily('serif').fontColor(INK)
      Text(this.detail.reminderId >= 0 ? '已设置 · '+displayAt(this.detail.reminderAt) : '尚未设置提醒').fontSize(14).fontColor(this.detail.reminderId >= 0 ? RED : MUTED)
      if (this.detail.reminderId >= 0) { this.smallButton('取消已设置的提醒',() => { this.cancelReminder(); }) }
      else if (this.detail.status === '待办') {
        Row({ space: 10 }) {
          TextInput({ text:this.reminderDate,placeholder:'YYYY-MM-DD' }).layoutWeight(1).fontSize(15).backgroundColor('#FFFFFF').onChange((v: string) => { this.reminderDate = v; })
          TextInput({ text:this.reminderTime,placeholder:'HH:mm' }).width(108).fontSize(15).backgroundColor('#FFFFFF').onChange((v: string) => { this.reminderTime = v; })
        }.width('100%')
        Flex({ wrap:FlexWrap.Wrap }) { this.smallButton('设置提醒',() => { this.setReminder(); },true); this.smallButton('1分钟测试提醒',() => { this.setReminder(true); }) }
      }
      Divider().color(BORDER)
      Text('来源依据').fontSize(21).fontFamily('serif').fontColor(INK)
      if (!this.detail.sourceIds.length) { Text('此事项由人工创建').fontSize(14).fontColor(MUTED) }
      ForEach(this.sources.filter((s: SourceRecord) => this.detail.sourceIds.includes(s.id)),(s: SourceRecord) => {
        Row({ space: 12 }) {
          Image('file://'+s.path).width(48).height(64).objectFit(ImageFit.Contain).backgroundColor('#FFFFFF')
          Column({ space: 5 }) { Text(s.name).fontSize(14).fontColor(INK); Text('核对原文 / 查看提取建议 ›').fontSize(12).fontColor(RED) }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').onClick(() => { this.openReview(s); })
      })
      Divider().color(BORDER)
      Text('变更历史').fontSize(21).fontFamily('serif').fontColor(INK)
      ForEach(this.historyList,(h: HistoryRecord) => {
        Column({ space: 8 }) {
          Text(h.action+' · '+displayAt(h.at)).fontSize(14).fontColor(RED)
          ForEach(h.changes,(v: string) => { Text(v).fontSize(13).fontColor(MUTED).lineHeight(22) })
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom:16 }).border({ width:{ bottom:1 },color:BORDER })
      },(h: HistoryRecord) => h.id)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  build() {
    Column() {
      Row() { Text('截图成事').fontSize(23).fontWeight(FontWeight.Bold).fontFamily('serif').fontColor(INK); Blank(); Text('有据可查').fontSize(12).fontColor(RED).letterSpacing(3) }.width('100%').padding({ left:24,right:24,top:16,bottom:18 }).border({ width:{ bottom:1 },color:BORDER })
      if (this.busy) { Row({ space:10 }) { LoadingProgress().width(18).height(18).color(RED); Text('正在处理，请稍候…').fontSize(12).fontColor(MUTED) }.width('100%').padding(10).backgroundColor('#ECE7DE') }
      if (!this.ready) {
        Column({ space:16 }) { LoadingProgress().color(RED).width(32).height(32); Text(this.statusMessage||'正在打开本地记录').fontSize(14).fontColor(MUTED) }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Scroll(this.scroller) {
          Column() {
            if (this.screen === 'review') { this.reviewPage() }
            else if (this.screen === 'detail') { this.detailPage() }
            else if (this.tab === '来源') { this.sourcesPage() }
            else if (this.tab === '设置') { this.settingsPage() }
            else { this.homePage() }
          }.width('100%').padding({ left:24,right:24,top:24,bottom:36 }).constraintSize({ maxWidth:760 })
        }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Auto)
      }
      if (this.screen === 'home') {
        Row() {
          ForEach(['事项','来源','设置'],(v: string) => {
            Text(v).fontSize(16).fontWeight(this.tab === v ? FontWeight.Bold : FontWeight.Normal).fontColor(this.tab === v ? RED : MUTED).layoutWeight(1).textAlign(TextAlign.Center).padding({ top:17,bottom:17 }).onClick(() => { this.tab = v; })
          })
        }.width('100%').border({ width:{ top:1 },color:BORDER })
      }
    }.width('100%').height('100%').backgroundColor(PAPER)
  }
}


