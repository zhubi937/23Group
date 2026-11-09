import { KeyboardAvoidMode } from '@kit.ArkUI';
import { GlassDock } from '../ui/GlassDock';
import { PressSurface } from '../ui/PressSurface';
import { glassMaterial } from '../ui/GlassMaterial';
import { clampPage } from '../ui/Motion';
import { RouteTrail, ScreenRoute } from '../ui/RouteTrail';
import { common } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { canCommitText } from '../domain/TextEntry';
import { Repository } from '../data/Repository';
import { Images } from '../platform/Images';
import { Recognition } from '../platform/Recognition';
import { Reminders } from '../platform/Reminders';
import { AppearanceStore } from '../platform/AppearanceStore';
import { Appearance, ThemePalette, THEMES, themeById } from '../ui/Appearance';
import { TaskListData, SourceListData } from '../ui/ListData';
import { rankMatches, normalizeTags, sourceMatches } from '../domain/Association';
import { TaskRecord, SourceRecord, HistoryRecord, FieldCandidate, Box, MatchCandidate, OcrLine, FIELD_KEYS, FIELD_LABELS, cloneTask, fieldValue, setField } from '../domain/Models';
import { extract, validateTask, applySelected, displayAt, scaledBox, reminderEpoch } from '../domain/Rules';
import { fixtureLines } from '../domain/Fixtures';
const INK: string = '#1C293B';
const SECONDARY: string = '#637086';
const DANGER: string = '#BA3E4D';
@Entry
@Component
struct Index {
  @State ready: boolean = false;
  @State busy: boolean = false;
  @State screen: string = 'home';
  @State tab: string = '事项';
  @State currentTab: number = 0;
  @State dockProgress: number = 0;
  @State sheetOpen: boolean = false;
  @State sheetMode: string = 'create';
  @State sheetDetent: number = 420;
  @State sheetBaseHeight: number = 750;
  @State reviewWorking: boolean = false;
  @State activityLabel: string = '';
  @State activityDone: boolean = false;
  private activityTimer: number = -1;
  private sheetReturnPending: string = '';
  private swiper: SwiperController = new SwiperController();
  private reviewScroller: Scroller = new Scroller();
  private imageScroller: Scroller = new Scroller();
  private settingsScroller: Scroller = new Scroller();
  @State query: string = '';
  @State filter: string = '全部';
  @State sortMode: string = '最近更新';
  @State visibleTaskCount: number = 0;
  @State visibleSourceCount: number = 0;
  @State sourceQuery: string = '';
  @State sourceFilter: string = '在用';
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
  @State showTranscript: boolean = false;
  @State reminderDate: string = '';
  @State reminderTime: string = '';
  @State statusMessage: string = '';
  @State manualText: string = '';
  @State appearance: Appearance = new Appearance();
  @State palette: ThemePalette = themeById('morandi-blue');
  @State sourceName: string = '';
  @State sourceTags: string = '';
  @State sourceNote: string = '';
  @State historyRefs: string[] = [];
  @State attachQuery: string = '';
  private reviewDirty: boolean = false;
  private confirmationOpen: boolean = false;
  private routeTrail: RouteTrail = new RouteTrail();
  private restoringRoute: boolean = false;
  private sourceDirty: boolean = false;
  private reviewReturn: string = 'home';
  private sourceReturn: string = 'home';
  private detailReturn: string = 'home';
  private searchTimer: number = -1;
  private sourceTimer: number = -1;
  private matchTimer: number = -1;
  private scroller: Scroller = new Scroller();
  private taskScroller: Scroller = new Scroller();
  private sourceScroller: Scroller = new Scroller();
  private repo: Repository = new Repository();
  private recognition: Recognition = new Recognition();
  private reminders: Reminders = new Reminders();
  private appearanceStore: AppearanceStore = new AppearanceStore();
  private taskData: TaskListData = new TaskListData();
  private sourceData: SourceListData = new SourceListData();
  private attachData: TaskListData = new TaskListData();
  private sourceUse: Map<string,TaskRecord[]> = new Map<string,TaskRecord[]>();
  private context: common.UIAbilityContext | null = null;
  private images: Images | null = null;
  aboutToAppear(): void { this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE); this.initialize(); }
  aboutToDisappear(): void { clearTimeout(this.searchTimer); clearTimeout(this.sourceTimer); clearTimeout(this.matchTimer); clearTimeout(this.activityTimer); }
  onBackPress(): boolean { if (this.sheetOpen || this.screen !== 'home') { this.goBack(); return true; } return false; }
  private toast(s: string): void { this.statusMessage = s; this.getUIContext().getPromptAction().showToast({ message: s, duration: 3000 }); }
  private fail(e: Object): void { const err = e as BusinessError; this.toast(err.message || String(e)); }
  private async initialize(): Promise<void> {
    try {
      this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.recognition.setContext(this.context); this.images = new Images(this.context); await this.repo.open(this.context);
      try { this.appearance = await this.appearanceStore.open(this.context); this.palette = themeById(this.appearance.themeId); } catch (_) { this.toast('外观暂用默认设置，事项数据不受影响'); }
      await this.reload(); this.ready = true;
    } catch (e) { this.fail(e); }
  }
  private async reload(): Promise<void> {
    this.taskList = await this.repo.tasks(); this.sources = await this.repo.sources();
    this.sourceUse.clear();
    this.taskList.forEach((t: TaskRecord) => t.sourceIds.forEach((id: string) => { const list = this.sourceUse.get(id) || []; list.push(t); this.sourceUse.set(id,list); }));
    this.refreshTasks(); this.refreshSources(); this.refreshAttach();
  }
  private pendingCount(): number { return this.taskList.filter((t: TaskRecord) => t.status === '待办').length; }
  private refreshTasks(): void {
    const q = this.query.trim().toLowerCase();
    let items = this.taskList.filter((t: TaskRecord) => (this.filter === '全部' || t.status === this.filter) && (!q || [t.title,t.context,t.type,t.date,t.deadline,t.location,t.notes].join(' ').toLowerCase().includes(q)));
    if (this.sortMode === '按时间') { items = items.slice().sort((a: TaskRecord,b: TaskRecord) => this.taskTimeKey(a).localeCompare(this.taskTimeKey(b)) || b.updatedAt-a.updatedAt); }
    this.visibleTaskCount = items.length; this.taskData.replace(items);
  }
  private taskTimeKey(t: TaskRecord): string { const date = t.deadline || (t.date.length === 10 ? t.date+' '+(t.startTime||'23:59') : ''); return date && date.length >= 10 ? date : '9999'; }
  private searchTasks(value: string): void { this.query = value; clearTimeout(this.searchTimer); this.searchTimer = setTimeout(() => { this.refreshTasks(); },150); }
  private refreshSources(): void {
    const items = this.sources.filter((s: SourceRecord) => sourceMatches(s,this.sourceQuery) && (this.sourceFilter === '已归档' ? s.archived : !s.archived && (this.sourceFilter === '未关联' ? !this.sourceTasks(s.id).length : this.sourceFilter === '已关联' ? !!this.sourceTasks(s.id).length : true)));
    this.visibleSourceCount = items.length; this.sourceData.replace(items);
  }
  private searchSources(value: string): void { this.sourceQuery = value; clearTimeout(this.sourceTimer); this.sourceTimer = setTimeout(() => { this.refreshSources(); },150); }
  private sourceTasks(id: string): TaskRecord[] { return this.sourceUse.get(id) || []; }
  private refreshMatches(): void {
    this.matches = rankMatches(this.draft,this.taskList,this.active.id ? this.active : undefined);
    if (this.targetId && !this.matches.some((m: MatchCandidate) => m.task.id === this.targetId && !m.alreadyLinked)) { this.targetId = ''; }
  }
  private refreshAttach(): void {
    const q = this.attachQuery.trim().toLowerCase();
    this.attachData.replace(this.taskList.filter((t: TaskRecord) => [t.title,t.context,t.date,t.deadline].join(' ').toLowerCase().includes(q)));
  }
  private activity(label: string, done: boolean = false): void {
    clearTimeout(this.activityTimer);
    this.activityDone=done;
    this.getUIContext().animateTo({duration:this.appearance.reduceMotion?0:180,curve:Curve.EaseOut},() => { this.activityLabel=label; });
    if (done) { this.activityTimer=setTimeout(() => { this.getUIContext().animateTo({duration:this.appearance.reduceMotion?0:180},() => { this.activityLabel=''; }); },1900); }
  }
  private startReviewProcessing(source: SourceRecord, backTo: string): void {
    this.active=source; this.reviewReturn=backTo; this.reviewDirty=false; this.boxes=[]; this.candidates=[]; this.warnings=[];
    this.reviewWorking=true; this.sheetMode='review'; this.sheetDetent=Math.round(this.sheetBaseHeight*0.56); this.screen='review'; this.sheetReturnPending=''; this.sheetOpen=true;
  }
  private async importPicture(): Promise<void> {
    if (this.busy || !this.images) { return; } this.busy=true;
    const backTo=this.screen==='source'?'source':'home';
    try {
      const uri=await this.images.choose(); if (!uri) { return; }
      this.activity('准备图像');
      const source=await this.images.importUri(uri); const old=await this.repo.byHash(source.hash);
      if (old) {
        this.images.remove(source);
        if (old.mode!=='manual' && old.ocrState!=='recognized' && old.mode!=='example') {
          this.startReviewProcessing(old,backTo); await this.recognition.run(old,(label: string) => { this.activity(label); }); await this.repo.putSource(old); await this.reload();
        }
        this.openReview(old,backTo); this.activity('已打开原来的来源',true); return;
      }
      await this.repo.putSource(source); this.startReviewProcessing(source,backTo);
      await this.recognition.run(source,(label: string) => { this.activity(label); }); await this.repo.putSource(source); await this.reload(); this.openReview(source,backTo);
      this.activity(source.error?'原图已保留，请重试':source.lines.length+' 段原文 · '+source.candidates.length+' 个字段',true);
    } catch (e) { this.fail(e); this.activity('未完成，请重试',true); }
    finally { this.reviewWorking=false; this.busy=false; }
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
  private openReview(s: SourceRecord, backTo: string = 'home'): void {
    this.reviewReturn = backTo; this.reviewDirty = false;
    if (s.ocrState === 'unavailable') { s.error = '本图尚未转写，可点击下方的本机离线识别。'; }
    this.active = s; this.showTranscript = s.ocrState !== 'recognized' && s.mode !== 'example'; this.showOriginal = s.mode === 'example'; const r = extract(s.lines,s.createdAt || Date.now());
    if (!s.lines.length && s.ocrState === 'unavailable') { r.warnings = ['请补充通知原文，或直接填写下方事项字段。']; }
    this.draft = r.task; this.candidates = r.fields; this.warnings = r.warnings; this.targetId = ''; this.focusKey = ''; this.boxes = [];
    this.selectedKeys = r.fields.map((f: FieldCandidate) => f.key); this.refreshMatches(); this.manualText = s.lines.map((l: OcrLine) => l.text).join('\n'); this.reviewWorking=false; this.reviewScroller.scrollTo({xOffset:0,yOffset:0}); this.imageScroller.scrollTo({xOffset:0,yOffset:0}); this.sheetMode='review'; this.sheetDetent=Math.round(this.sheetBaseHeight*(s.path?0.56:0.92)); this.sheetReturnPending=''; this.screen='review'; this.sheetOpen=true;
  }
  private newTask(): void { this.openReview(new SourceRecord()); this.warnings = []; }
  private updateField(key: string, value: string): void {
    const t = cloneTask(this.draft); setField(t,key,value); this.draft = t; this.reviewDirty = true;
    clearTimeout(this.matchTimer); this.matchTimer = setTimeout(() => { this.refreshMatches(); },180);
    if (!this.selectedKeys.includes(key)) { this.selectedKeys = [...this.selectedKeys,key]; }
  }
  private selectField(key: string): void {
    this.focusKey=key; const field=this.candidates.find((value: FieldCandidate) => value.key===key); this.boxes=field?field.boxes:[];
    if (this.boxes.length && this.screen==='review') {
      this.getUIContext().getFocusController().clearFocus(); this.sheetDetent=Math.round(this.sheetBaseHeight*0.24);
      setTimeout(() => { this.imageScroller.scrollTo({xOffset:0,yOffset:Math.max(0,scaledBox(this.boxes[0],this.active.width,this.previewWidth).y-72),animation:!this.appearance.reduceMotion}); },240);
    } else if (this.boxes.length) { this.showOriginal=true; this.scroller.scrollTo({xOffset:0,yOffset:0,animation:!this.appearance.reduceMotion}); }
    else { this.toast('此字段没有对应的图像坐标，可对照原图核对'); }
  }
  private async extractManual(): Promise<void> {
    if (this.busy || !this.manualText.trim()) { return; } this.busy = true;
    try {
      const lines: OcrLine[] = [];
      this.manualText.split('\n').filter((v: string) => v.trim().length > 0).forEach((v: string, i: number) => { lines.push(new OcrLine('manual_'+i,v.trim(),new Box())); });
      this.active.lines = lines; this.active.mode = 'manual'; this.active.ocrState = 'manual'; this.active.error = '';
      this.active.candidates = extract(lines,this.active.createdAt || Date.now()).fields;
      if (this.active.id) { await this.repo.putSource(this.active); await this.reload(); }
      this.openReview(this.active,this.reviewReturn); this.toast('已按手工文字整理，请对照原图确认，未生成图像坐标');
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async recognizeAgain(): Promise<void> {
    if (this.busy || !this.active.id) { return; }
    if (this.reviewDirty && !await this.confirm('重新识别会替换尚未保存的文字与字段。','重新识别')) { return; }
    this.busy=true; const backTo=this.screen==='source'?'source':this.reviewReturn;
    this.startReviewProcessing(this.active,backTo);
    try {
      await this.recognition.run(this.active,(label: string) => { this.activity(label); }); await this.repo.putSource(this.active); await this.reload(); this.openReview(this.active,backTo);
      this.activity(this.active.error?'原图已保留，请重试':this.active.lines.length+' 段原文 · '+this.active.candidates.length+' 个字段',true);
    } catch (e) { this.fail(e); this.activity('未完成，请重试',true); }
    finally { this.reviewWorking=false; this.busy=false; }
  }
  private async confirm(message: string, label: string): Promise<boolean> {
    if (this.confirmationOpen) { return false; } this.confirmationOpen=true;
    try { const r=await this.getUIContext().getPromptAction().showDialog({title:'请确认',message,buttons:[{text:'取消',color:SECONDARY},{text:label,color:this.palette.accent}]}); return r.index===1; }
    finally { this.confirmationOpen=false; }
  }
  private async saveReview(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      let t = cloneTask(this.draft); let action = t.id ? '人工编辑' : '确认新建';
      if (this.targetId) {
        const candidate = rankMatches(this.draft,this.taskList,this.active).find((m: MatchCandidate) => m.task.id === this.targetId && !m.alreadyLinked);
        if (!candidate) { throw new Error('当前信息与原候选不再匹配，请重新选择关联或保存为新事项'); }
        const existing = this.taskList.find((v: TaskRecord) => v.id === this.targetId);
        if (!existing) { throw new Error('所关联的事项已不存在'); }
        if (existing.reminderId >= 0) { throw new Error('请先到原事项中取消提醒，再确认变更，避免旧时间继续触发'); }
        if (!this.selectedKeys.length) { throw new Error('请至少勾选一个需要采用的字段'); }
        t = applySelected(existing,this.draft,this.selectedKeys); action = '确认关联并更新';
        const preview = this.selectedKeys.map((key: string) => FIELD_LABELS[FIELD_KEYS.indexOf(key)]+'：'+(fieldValue(existing,key)||'未填写')+' → '+(fieldValue(t,key)||'未填写')).join('\n');
        if (!await this.confirm('将更新“'+existing.title+'”\n'+preview+'\n原来的来源和历史会保留。','确认更新')) { return; }
      }
      clearTimeout(this.matchTimer);
      const errors = validateTask(t); if (errors.length) { throw new Error(errors.join('\n')); }
      const saved = await this.repo.saveTask(t,action,this.active.id ? this.active : null);
      await this.reload(); this.reviewDirty=false; this.sheetReturnPending=''; this.sheetOpen=false; await this.openDetail(saved,this.reviewReturn==='source'?'source':'home'); this.activity('已保存到你的安排',true);
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async openDetail(t: TaskRecord, backTo: string = 'home'): Promise<void> {
    if (this.sheetOpen && this.reviewDirty && !await this.confirm('核对中有尚未保存的修改。','放弃修改')) { return; }
    if (this.screen==='source' && this.sourceDirty && !await this.confirm('来源信息尚未保存，离开后将放弃修改。','放弃修改')) { return; }
    this.reviewDirty=false; this.sourceDirty=false;
    this.sheetReturnPending=''; this.sheetOpen=false; this.detailReturn = backTo;
    this.detail = cloneTask(t); this.historyList = await this.repo.history(t.id); const due = t.deadline.split(' '); this.reminderDate = t.date.length === 10 ? t.date : (due[0] && due[0].length === 10 ? due[0] : ''); this.reminderTime = t.startTime || due[1] || '09:00'; this.scroller.scrollTo({ xOffset:0,yOffset:0 }); this.enterRoute('detail',t.id);
  }
  private editDetail(): void {
    if (this.detail.reminderId >= 0) { this.toast('编辑前请先取消已设置的提醒'); return; }
    this.reviewReturn = 'detail'; this.reviewDirty = false; this.active = new SourceRecord(); this.draft = cloneTask(this.detail); this.candidates = []; this.matches = []; this.targetId = ''; this.boxes = []; this.warnings = []; this.selectedKeys = FIELD_KEYS.slice(); this.reviewScroller.scrollTo({xOffset:0,yOffset:0}); this.sheetMode='review'; this.sheetDetent=Math.round(this.sheetBaseHeight*0.92); this.sheetReturnPending=''; this.screen='review'; this.sheetOpen=true;
  }
  private async cancelReminder(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      await this.reminders.cancel(this.detail.reminderId); const t = cloneTask(this.detail); t.reminderId = -1; t.reminderAt = 0; t.reminderState = '未设置';
      const saved = await this.repo.saveTask(t,'取消系统提醒'); await this.reload(); await this.openDetail(saved,this.detailReturn); this.toast('已取消提醒');
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async setReminder(test: boolean = false): Promise<void> {
    if (this.busy || !this.context) { return; } this.busy = true;
    try {
      if (this.detail.reminderId >= 0) { throw new Error('请先取消原提醒，再重新设置'); }
      const at = test ? Date.now()+60000 : reminderEpoch(this.reminderDate,this.reminderTime);
      if (!at) { throw new Error('请填写完整且有效的提醒日期和时间'); }
      const id = await this.reminders.publish(this.detail,at,this.context,test); const t = cloneTask(this.detail); t.reminderId = id; t.reminderAt = at; t.reminderState = '已设置';
      try { const saved = await this.repo.saveTask(t,'设置系统提醒'); await this.reload(); await this.openDetail(saved,this.detailReturn); }
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
      if (status === '已删除') { this.navigate('home'); } else { await this.openDetail(saved); } this.toast('已更新事项状态');
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async deleteSource(s: SourceRecord): Promise<void> {
    if (this.busy || !this.images || !await this.confirm('仅删除未被事项引用的来源及其本地副本。','删除来源')) { return; }
    this.busy = true;
    try { await this.repo.removeSource(s.id); this.images.remove(s); await this.reload(); this.navigate('home'); this.changeTab('来源'); this.toast('来源已删除'); }
    catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async clearAll(): Promise<void> {
    if (this.busy || !this.images || !await this.confirm('将永久清空本应用中的事项、历史、截图副本，并取消已记录的提醒。无法撤销。','清空本地数据')) { return; }
    this.busy = true;
    try {
      for (const t of await this.repo.tasks(true)) { await this.reminders.cancel(t.reminderId); }
      await this.repo.clear(); this.images.clearSources();
      await this.reload(); this.toast('事项与来源已清空，外观偏好保留');
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async goBack(): Promise<void> {
    if (this.busy) { return; }
    if (this.sheetOpen) {
      if (this.sheetMode==='review' && this.reviewDirty && !await this.confirm('本页有尚未保存的修改，关闭后将放弃这些修改。','放弃修改')) { return; }
      this.reviewDirty=false; this.sheetReturnPending=this.sheetMode==='review'?this.reviewReturn:''; this.sheetOpen=false; return;
    }
    if (this.screen==='source' && this.sourceDirty && !await this.confirm('来源名称或标签尚未保存。','放弃修改')) { return; }
    this.sourceDirty=false; this.scroller.scrollTo({xOffset:0,yOffset:0}); await this.restoreRoute(this.routeTrail.back());
  }
  private async dismissSheet(action: DismissSheetAction): Promise<void> {
    if (this.busy) { return; }
    if (this.sheetMode==='review' && this.reviewDirty && !await this.confirm('本页有尚未保存的修改，关闭后将放弃这些修改。','放弃修改')) { return; }
    this.reviewDirty=false; this.sheetReturnPending=this.sheetMode==='review'?this.reviewReturn:''; action.dismiss();
  }
  private sheetDidDisappear(): void {
    const next=this.sheetReturnPending; this.sheetReturnPending='';
    if (next && this.screen==='review') { this.navigate(next); }
  }
  private openCreate(): void {
    if (this.busy) { return; }
    this.sheetReturnPending=''; this.sheetMode='create'; this.sheetDetent=Math.round(this.sheetBaseHeight*0.56); this.sheetOpen=true;
  }
  private navigate(screen: string): void {
    if (screen==='home') { this.routeTrail.reset(); }
    this.getUIContext().animateTo({duration:this.appearance.reduceMotion?0:210,curve:Curve.EaseOut},() => { this.screen=screen; });
  }
  private enterRoute(screen: string,id: string): void { if (!this.restoringRoute) { this.routeTrail.enter(screen,id); } this.navigate(screen); }
  private async restoreRoute(route: ScreenRoute): Promise<void> {
    this.restoringRoute=true;
    try {
      if (route.screen==='detail') {
        const task=this.taskList.find((value: TaskRecord) => value.id===route.id);
        if (task) { await this.openDetail(task); } else { this.navigate('home'); }
      } else if (route.screen==='source' || route.screen==='attach') {
        const source=this.sources.find((value: SourceRecord) => value.id===route.id);
        if (!source) { this.navigate('home'); }
        else if (route.screen==='source') { await this.openSource(source); }
        else { this.active=source; this.refreshAttach(); this.navigate('attach'); }
      } else { this.navigate('home'); }
    } finally { this.restoringRoute=false; }
  }
  private selectTab(index: number): void {
    if (this.busy) { return; }
    if (this.currentTab===index) {
      this.getUIContext().animateTo({duration:this.appearance.reduceMotion?0:180,curve:Curve.EaseOut},() => { this.dockProgress=index; });
      if (index===0) { this.taskScroller.scrollToIndex(0,!this.appearance.reduceMotion); }
      else if (index===1) { this.sourceScroller.scrollToIndex(0,!this.appearance.reduceMotion); }
      else { this.settingsScroller.scrollTo({xOffset:0,yOffset:0,animation:!this.appearance.reduceMotion}); }
    } else { this.swiper.changeIndex(index,!this.appearance.reduceMotion); }
  }
  private changeTab(tab: string): void { this.selectTab(['事项','来源','外观'].indexOf(tab)); }
  private setAppearance(themeId: string, clear: boolean, reduce: boolean): void {
    const value = new Appearance(); value.themeId = themeById(themeId).id; value.clearGlass = clear; value.reduceMotion = reduce;
    this.getUIContext().animateTo({duration:reduce?0:220,curve:Curve.EaseInOut}, () => { this.appearance = value; this.palette = themeById(value.themeId); });
    this.appearanceStore.save(value).catch((e: Error) => { this.fail(e); });
  }
  private async openSource(source: SourceRecord, backTo: string = 'home'): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      this.active = source; this.sourceReturn = backTo; this.sourceName = source.name; this.sourceTags = (source.tags || []).join('，'); this.sourceNote = source.note || ''; this.sourceDirty = false;
      this.historyRefs = await this.repo.sourceHistoryTaskIds(source.id); this.showOriginal = false; this.showTranscript = false; this.boxes = [];
      this.scroller.scrollTo({xOffset:0,yOffset:0}); this.enterRoute('source',source.id);
    } catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async saveSourceMeta(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try { this.active = await this.repo.saveSourceMeta(this.active.id,this.sourceName,normalizeTags(this.sourceTags),this.sourceNote); this.sourceName=this.active.name; this.sourceTags=this.active.tags.join('，'); this.sourceNote=this.active.note; this.sourceDirty = false; await this.reload(); this.toast('来源信息已保存'); }
    catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async toggleArchive(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try { this.active = await this.repo.archiveSource(this.active.id,!this.active.archived); await this.reload(); this.toast(this.active.archived?'已归档，原图及关联记录仍保留':'已移回在用来源'); }
    catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private openAttach(): void { if (this.busy) { return; } this.attachQuery = ''; this.refreshAttach(); this.enterRoute('attach',this.active.id); }
  private async attachTo(task: TaskRecord): Promise<void> {
    if (this.busy) { return; }
    if (task.sourceIds.includes(this.active.id)) { this.toast('这份来源已经关联到此事项'); return; }
    if (!await this.confirm('将“'+this.active.name+'”补充到“'+task.title+'”。标题、日期和其他字段保持原值。','补充来源')) { return; }
    this.busy = true;
    try { const saved = await this.repo.attachSource(task,this.active.id); await this.reload(); this.historyRefs = await this.repo.sourceHistoryTaskIds(this.active.id); await this.openDetail(saved,'source'); this.toast('已补充来源，事项字段保持原值'); }
    catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private async detachFromDetail(source: SourceRecord): Promise<void> {
    if (this.busy || !await this.confirm('解除“'+source.name+'”与当前事项的关联。原图与既有历史仍保留，可重新关联。','解除关联')) { return; }
    this.busy = true;
    try { const saved = await this.repo.detachSource(this.detail,source.id); await this.reload(); await this.openDetail(saved,this.detailReturn); this.toast('已解除当前关联，历史依据仍保留'); }
    catch (e) { this.fail(e); } finally { this.busy = false; }
  }
  private dateCaption(): string { const d = new Date(); return (d.getMonth()+1)+'月'+d.getDate()+'日 · '+['星期日','星期一','星期二','星期三','星期四','星期五','星期六'][d.getDay()]; }
  private sourceCaption(s: SourceRecord): string { return s.mode === 'example' ? '演示样例 · 预置文字' : s.mode === 'manual' ? '手工补充 · 无图像坐标' : s.mode === 'offline' ? '本机离线识别 · '+s.lines.length+' 段' : s.ocrState === 'recognized' ? '系统识别 · '+s.lines.length+' 段' : '待识别'; }
  private pageTitle(): string { return this.screen === 'review' ? (this.draft.id?'编辑事项':'核对信息') : this.screen === 'detail' ? '事项详情' : this.screen === 'source' ? '来源档案' : this.screen === 'attach' ? '补充来源' : '截图成事'; }
  private icon(name: string): Resource {
    switch (name) {
      case 'home': return $r('app.media.ui_home'); case 'sources': return $r('app.media.ui_sources');
      case 'appearance': return $r('app.media.ui_appearance'); case 'plus': return $r('app.media.ui_plus');
      case 'back': return $r('app.media.ui_back'); case 'chevron': return $r('app.media.ui_chevron');
      case 'scan': return $r('app.media.ui_scan'); case 'link': return $r('app.media.ui_link');
      case 'archive': return $r('app.media.ui_archive'); case 'clock': return $r('app.media.ui_clock');
      default: return $r('app.media.ui_shield');
    }
  }
  @Styles
  glassSurface() {
    .backgroundEffect({radius:this.appearance.clearGlass?0:22,saturation:1.15,brightness:1.04,color:this.appearance.clearGlass?'#FCFDFE':'#18FFFFFF'})
    .linearGradient({angle:135,colors:[['#70FFFFFF',0],['#0AFFFFFF',0.5],['#45FFFFFF',1]]})
    .border({width:1,color:'#E6FFFFFF'}).borderRadius(28)
    .shadow({radius:24,offsetX:0,offsetY:8,color:'#0B253F55'})
  }
  @Styles
  paperSurface() {
    .backgroundColor(this.appearance.clearGlass?'#FFFFFF':'#A8FFFFFF').border({width:1,color:'#E6FFFFFF'}).borderRadius(24)
    .shadow({radius:12,offsetX:0,offsetY:4,color:'#04253F55'})
  }
  @Builder
  glyph(name: string, size: number = 20) { Image(this.icon(name)).width(size).height(size).objectFit(ImageFit.Contain).draggable(false) }
  @Builder
  smallButton(label: string, action: () => void, primary: boolean = false) {
    Button(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(primary?'#FFFFFF':this.palette.accent)
      .backgroundColor(primary?this.palette.accent:'#BFFFFFFF').border({width:primary?0:1,color:'#E6FFFFFF'})
      .borderRadius(16).height(44).padding({left:16,right:16}).margin({right:8,bottom:8}).enabled(!this.busy).stateEffect(true).onClick(action)
  }
  @Builder
  sectionTitle(title: string, caption: string) {
    Column({space:8}) {
      Text(title).fontSize(29).fontWeight(FontWeight.Bold).fontColor(INK).letterSpacing(-0.5)
      if (caption) { Text(caption).fontSize(14).fontColor(SECONDARY).lineHeight(22) }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  appHeader() {
    Row({space:11}) {
      if (this.screen!=='home') {
        Button() { this.glyph('back',18) }.width(38).height(38).backgroundColor('#70FFFFFF').borderRadius(19).accessibilityText('返回').id('nav-back').enabled(!this.busy).onClick(() => { this.goBack(); })
      } else { Image($r('app.media.screen_mark')).width(30).height(30).borderRadius(10).draggable(false) }
      Text(this.pageTitle()).fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK).layoutWeight(1)
      Row({space:5}) { this.glyph('shield',12); Text('本机私享').fontSize(10).fontColor(SECONDARY) }
    }.width('100%').height(60).padding({left:22,right:22})
  }
  @Builder
  activityCapsule() {
    if (this.activityLabel) {
      Row({space:8}) {
        if (!this.activityDone) { LoadingProgress().width(15).height(15).color('#FFFFFF') }
        else { Text('✓').fontSize(14).fontColor('#E4F2EC') }
        Text(this.activityLabel).fontSize(11).fontColor('#FFFFFF').maxLines(1)
      }.padding({left:16,right:16,top:11,bottom:11}).backgroundColor('#ED202A36').borderRadius(24)
        .shadow({radius:14,offsetY:5,color:'#18202A36'}).constraintSize({maxWidth:'90%'})
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({y:-7})))
        .accessibilityText(this.activityLabel).id('activity-capsule')
    }
  }
  @Builder
  homeHero() {
    Row({space:16}) {
      Column({space:5}) {
        Text('待你安排').fontSize(12).fontColor(SECONDARY)
        Row({space:6}) { Text(this.pendingCount().toString().padStart(2,'0')).fontSize(42).fontWeight(300).letterSpacing(-1.5).fontColor(INK); Text('件待办').fontSize(12).fontColor(SECONDARY).margin({top:16}) }
      }.alignItems(HorizontalAlign.Start)
      Blank()
      Column({space:9}) {
        Text(this.sources.filter((source: SourceRecord) => !source.archived).length+' 份原文').fontSize(12).fontColor(SECONDARY)
        Text(this.taskList.filter((task: TaskRecord) => task.status==='已完成').length+' 件已完成').fontSize(12).fontColor(SECONDARY)
      }.alignItems(HorizontalAlign.End)
    }.padding({left:20,right:20,top:17,bottom:16}).width('100%').glassSurface()
  }
  @Builder
  taskCard(task: TaskRecord) {
    PressSurface({reduceMotion:this.appearance.reduceMotion,onActivate:() => { this.openDetail(task); }}) {
    Column({space:12}) {
      Row({space:8}) {
        Text(task.type).fontSize(11).fontColor(this.palette.accent).backgroundColor(this.palette.soft).padding({left:9,right:9,top:5,bottom:5}).borderRadius(10)
        if (task.context) { Text(task.context).fontSize(11).fontColor(SECONDARY).maxLines(1).textOverflow({overflow:TextOverflow.Ellipsis}).layoutWeight(1) } else { Blank() }
        Text(task.status).fontSize(11).fontColor(SECONDARY)
      }.width('100%')
      Text(task.title).fontSize(20).fontWeight(FontWeight.Medium).fontColor(INK).maxLines(2).textOverflow({overflow:TextOverflow.Ellipsis}).lineHeight(28)
      Row({space:7}) { this.glyph('clock',14); Text(task.deadline?'截止 '+task.deadline:(task.date||'日期待补充')+(task.startTime?'  '+task.startTime:'')).fontSize(13).fontColor(SECONDARY).layoutWeight(1) }.width('100%')
      if (task.location) { Text(task.location+(task.destination?' → '+task.destination:'')).fontSize(13).fontColor(SECONDARY).maxLines(1) }
      Row({space:6}) {
        this.glyph('link',13); Text(task.sourceIds.length+' 份来源').fontSize(11).fontColor(SECONDARY); Blank()
        if (task.reminderId>=0) { Text('已设置提醒').fontSize(11).fontColor(this.palette.accent) }
        this.glyph('chevron',14)
      }.width('100%')
    }.padding(20).width('100%').alignItems(HorizontalAlign.Start).paperSurface().id('task-'+task.id)
    }
  }
  @Builder
  tasksPage() {
    List({space:14,scroller:this.taskScroller}) {
      ListItem() {
        Column({space:14}) {
          Column({space:6}) { Text(this.dateCaption()).fontSize(11).fontColor(SECONDARY); Text('从容，安排每一天。').fontSize(27).fontWeight(FontWeight.Bold).fontColor(INK).letterSpacing(-0.7) }.alignItems(HorizontalAlign.Start).width('100%')
          this.homeHero()
          Search({value:this.query,placeholder:'搜索事项、课程或地点'}).height(46).backgroundColor('#A6FFFFFF').borderRadius(17).fontColor(INK).enablePreviewText(true).onChange((v: string,p?: PreviewText) => { if (canCommitText(p?.value)) { this.searchTasks(v); } }).id('task-search')
          Row({space:5}) {
            ForEach(['全部','待办','已完成','已取消'],(v: string) => {
              Text(v).fontSize(13).fontWeight(this.filter===v?FontWeight.Medium:FontWeight.Normal).fontColor(this.filter===v?this.palette.accent:SECONDARY)
                .padding({left:12,right:12,top:9,bottom:9}).backgroundColor(this.filter===v?'#EFFFFFFF':'#00FFFFFF').borderRadius(13).onClick(() => { this.filter=v; this.refreshTasks(); })
            })
          }.width('100%')
          Row() { Text('你的安排').fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK); Text('  '+this.visibleTaskCount).fontSize(12).fontColor(SECONDARY); Blank(); Select([{value:'最近更新'},{value:'按时间'}]).value(this.sortMode).font({size:12}).fontColor(SECONDARY).backgroundColor('#00FFFFFF').onSelect((_i: number,v: string) => { this.sortMode=v; this.refreshTasks(); }) }.width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      if (!this.visibleTaskCount) {
        ListItem() {
          Column({space:14}) {
            Image($r('app.media.screen_mark')).width(64).height(64).borderRadius(20)
            Text(this.query?'没有找到匹配事项':this.taskList.length?'这个分类还没有事项':'从一张截图开始').fontSize(20).fontWeight(FontWeight.Medium).fontColor(INK)
            Text('把时间、地点和要求整理好，确认后加入你的安排。').fontSize(14).fontColor(SECONDARY).lineHeight(23).textAlign(TextAlign.Center)
            if (!this.taskList.length) { this.smallButton('体验样例',() => { this.changeTab('来源'); }) }
          }.width('100%').padding({top:30,bottom:28,left:14,right:14}).paperSurface()
        }
      }
      LazyForEach(this.taskData,(task: TaskRecord) => { ListItem() { this.taskCard(task) } },(task: TaskRecord) => task.id+'_'+task.revision+'_'+this.palette.id+'_'+this.appearance.clearGlass)
      ListItem() { Text('每一份安排，都有迹可循。').fontSize(11).fontColor(SECONDARY).width('100%').textAlign(TextAlign.Center).padding({top:10,bottom:118}) }
    }.width('100%').height('100%').padding({left:22,right:22,top:16}).cachedCount(3).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).transition(TransitionEffect.OPACITY)
  }
  @Builder
  sourceCard(source: SourceRecord) {
    PressSurface({reduceMotion:this.appearance.reduceMotion,onActivate:() => { this.openSource(source); }}) {
    Row({space:15}) {
      Image('file://'+source.path).width(64).height(83).objectFit(ImageFit.Contain).backgroundColor('#E8FFFFFF').borderRadius(13).draggable(false)
      Column({space:7}) {
        Text(source.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK).maxLines(2).textOverflow({overflow:TextOverflow.Ellipsis})
        Text(this.sourceCaption(source)).fontSize(11).fontColor(SECONDARY).maxLines(1)
        Text(source.archived?'已归档 · 原图保留':this.sourceTasks(source.id).length?'关联 '+this.sourceTasks(source.id).length+' 个事项':'尚未关联').fontSize(11).fontColor(this.palette.accent)
        if (source.tags && source.tags.length) { Text(source.tags.join(' · ')).fontSize(11).fontColor(SECONDARY).maxLines(1).textOverflow({overflow:TextOverflow.Ellipsis}) }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      this.glyph('chevron',15)
    }.width('100%').padding(17).paperSurface().id('source-'+source.id)
    }
  }
  @Builder
  sampleActions() {
    Column({space:12}) {
      Row() { Text('体验样例').fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK); Blank(); Text('预置文字与坐标').fontSize(10).fontColor(SECONDARY) }.width('100%')
      Flex({wrap:FlexWrap.Wrap}) {
        this.smallButton('出行截图',() => { this.loadSample('train'); })
        this.smallButton('作业通知',() => { this.loadSample('notice'); })
        this.smallButton('延期通知',() => { this.loadSample('update'); })
      }
      Text('样例用于体验核对流程，预置结果并非实际 OCR。').fontSize(11).fontColor(SECONDARY).lineHeight(18)
    }.width('100%').padding(18).alignItems(HorizontalAlign.Start).paperSurface()
  }
  @Builder
  sourcesPage() {
    List({space:14,scroller:this.sourceScroller}) {
      ListItem() {
        Column({space:18}) {
          this.sectionTitle('每份原文，都有来处。','保留截图，整理标签，串联每一次变更。')
          Search({value:this.sourceQuery,placeholder:'搜索名称、标签或原文'}).height(46).fontColor(INK).backgroundColor('#ACFFFFFF').borderRadius(17).enablePreviewText(true).onChange((v: string,p?: PreviewText) => { if (canCommitText(p?.value)) { this.searchSources(v); } }).id('source-search')
          Row({space:4}) {
            ForEach(['在用','未关联','已关联','已归档'],(v: string) => {
              Text(v).fontSize(12).fontColor(this.sourceFilter===v?this.palette.accent:SECONDARY).backgroundColor(this.sourceFilter===v?'#EFFFFFFF':'#00FFFFFF').padding({left:11,right:11,top:9,bottom:9}).borderRadius(12).onClick(() => { this.sourceFilter=v; this.refreshSources(); })
            })
            Blank(); Text(this.visibleSourceCount+' 份').fontSize(10).fontColor(SECONDARY)
          }.width('100%')
        }.width('100%')
      }
      if (!this.visibleSourceCount) { ListItem() { Text(this.sourceQuery?'未找到匹配来源':'这里还没有来源').fontSize(15).fontColor(SECONDARY).padding(26).width('100%').textAlign(TextAlign.Center) } }
      LazyForEach(this.sourceData,(source: SourceRecord) => { ListItem() { this.sourceCard(source) } },(source: SourceRecord) => source.id+'_'+source.name+'_'+source.archived+'_'+source.ocrState+'_'+this.palette.id)
      ListItem() { this.sampleActions() }
      ListItem() { Text('原图留在本机，历史依据始终保留。').fontSize(11).fontColor(SECONDARY).width('100%').textAlign(TextAlign.Center).padding({top:10,bottom:118}) }
    }.width('100%').height('100%').padding({left:22,right:22,top:16}).cachedCount(3).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).transition(TransitionEffect.OPACITY)
  }
  @Builder
  settingsPage() {
    Column({space:22}) {
      this.sectionTitle('选择你的色彩。','简洁，也可以很有个人风格。')
      Column({space:16}) {
        Row() { Text('LIQUID GLASS').fontSize(10).letterSpacing(2).fontColor(this.palette.accent); Blank(); Text(this.palette.name).fontSize(12).fontColor(SECONDARY) }.width('100%')
        Row({space:16}) {
          Image($r('app.media.screen_mark')).width(52).height(52).borderRadius(17)
          Column({space:7}) { Text('截图成事').fontSize(24).fontWeight(FontWeight.Medium).fontColor(INK); Text('让重要的事，轻盈有序。').fontSize(12).fontColor(SECONDARY) }.alignItems(HorizontalAlign.Start)
        }.width('100%')
        Row({space:7}) { Row().width(7).height(7).borderRadius(4).backgroundColor(this.palette.accent); Text(this.appearance.clearGlass?'清晰模式':'柔光绸缎 · 通透玻璃').fontSize(11).fontColor(SECONDARY) }.width('100%')
      }.width('100%').padding(23).glassSurface()
      Grid() {
        ForEach(THEMES,(theme: ThemePalette) => {
          GridItem() {
            Stack() {
            Image(this.wallpaper(theme.id)).width('100%').height('100%').objectFit(ImageFit.Cover).draggable(false)
            Column({space:16}) {
              Row() { Row().width(26).height(26).borderRadius(13).backgroundColor(theme.accent).border({width:3,color:'#CFFFFFFF'}); Blank(); if (this.palette.id===theme.id) { Text('✓').fontSize(15).fontWeight(FontWeight.Bold).fontColor(theme.accent) } }.width('100%')
              Text(theme.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
            }.width('100%').height('100%').padding(13).backgroundColor('#25FFFFFF')
            }.width('100%').height('100%').borderRadius(21).clip(true)
              .border({width:this.palette.id===theme.id?1.6:1,color:this.palette.id===theme.id?theme.accent:'#F2FFFFFF'})
              .onClick(() => { this.setAppearance(theme.id,this.appearance.clearGlass,this.appearance.reduceMotion); }).id('theme-'+theme.id).accessibilityText(theme.name+(this.palette.id===theme.id?'，已选择':''))
          }
        })
      }.columnsTemplate('1fr 1fr 1fr').rowsTemplate('1fr 1fr').columnsGap(10).rowsGap(10).height(212).width('100%').scrollBar(BarState.Off)
      Column({space:0}) {
        Row({space:16}) {
          Column({space:6}) { Text('清晰模式').fontSize(16).fontColor(INK); Text('降低透明度，关闭背景模糊').fontSize(12).fontColor(SECONDARY) }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({type:ToggleType.Switch,isOn:this.appearance.clearGlass}).selectedColor(this.palette.accent).onChange((v: boolean) => { this.setAppearance(this.appearance.themeId,v,this.appearance.reduceMotion); }).id('clear-glass')
        }.width('100%').padding({top:18,bottom:18})
        Divider().color('#12637086')
        Row({space:16}) {
          Column({space:6}) { Text('减少动态效果').fontSize(16).fontColor(INK); Text('减少页面切换和主题变化的过渡').fontSize(12).fontColor(SECONDARY) }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({type:ToggleType.Switch,isOn:this.appearance.reduceMotion}).selectedColor(this.palette.accent).onChange((v: boolean) => { this.setAppearance(this.appearance.themeId,this.appearance.clearGlass,v); }).id('reduce-motion')
        }.width('100%').padding({top:18,bottom:18})
      }.width('100%').padding({left:20,right:20}).paperSurface()
      Column({space:13}) {
        Row({space:10}) { this.glyph('shield',20); Text('你的数据，留在本机。').fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK) }.width('100%')
        Text('无需账号，不上传图片。事项、原文和关联历史保存在本机。').fontSize(13).fontColor(SECONDARY).lineHeight(22)
        Text(this.taskList.length+' 个事项 · '+this.sources.length+' 份来源').fontSize(12).fontColor(this.palette.accent)
        this.smallButton('清空事项与来源',() => { this.clearAll(); })
      }.width('100%').padding(20).alignItems(HorizontalAlign.Start).paperSurface()
      Column({space:8}) {
        Text('截图成事  0.8.0').fontSize(13).fontColor(SECONDARY)
        Text('第 8 周整合版 · 关联与来源管理').fontSize(11).fontColor(SECONDARY)
        Text('中文输入可使用系统拼音选词；电脑键盘也可先复制中文，再在模拟器中粘贴。').fontSize(11).fontColor(SECONDARY).lineHeight(19)
      }.width('100%').alignItems(HorizontalAlign.Start).padding({top:6,bottom:10})
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  preview() {
    if (this.active.path) {
      Column({space:13}) {
        Row() {
          Text(this.sourceCaption(this.active)).fontSize(11).fontColor(SECONDARY).layoutWeight(1)
          Button(this.showOriginal?'收起原图':'查看原图').height(34).fontSize(12).fontColor(this.palette.accent).backgroundColor(this.palette.soft).borderRadius(12).onClick(() => { this.showOriginal = !this.showOriginal; })
        }.width('100%')
        if (this.showOriginal) {
          Stack({alignContent:Alignment.TopStart}) {
            Image('file://'+this.active.path).width('100%').aspectRatio(this.active.width/Math.max(1,this.active.height)).objectFit(ImageFit.Contain).draggable(false)
            ForEach(this.boxes,(box: Box) => { Rect().width(scaledBox(box,this.active.width,this.previewWidth).width).height(scaledBox(box,this.active.width,this.previewWidth).height).fill('#18BA3E4D').stroke(DANGER).strokeWidth(2).position({x:scaledBox(box,this.active.width,this.previewWidth).x,y:scaledBox(box,this.active.width,this.previewWidth).y}).hitTestBehavior(HitTestMode.None) })
          }.width('100%').aspectRatio(this.active.width/Math.max(1,this.active.height)).backgroundColor('#FFFFFF').borderRadius(12).clip(true).onAreaChange((_old: Area,next: Area) => { this.previewWidth=Number(next.width); })
        }
        if (this.active.error) { Text(this.active.error).fontSize(12).fontColor(DANGER).lineHeight(21) }
        this.smallButton('重新识别图片',() => { this.recognizeAgain(); })
      }.width('100%').padding(17).paperSurface().alignItems(HorizontalAlign.Start)
    }
  }
  @Builder
  editor(key: string,label: string) {
    Column({space:9}) {
      Row({space:8}) {
        if (this.targetId) {
          Checkbox({name:key}).select(this.selectedKeys.includes(key)).selectedColor(this.palette.accent).width(19).height(19).onChange((checked: boolean) => { this.selectedKeys=checked?[...this.selectedKeys.filter((v: string) => v!==key),key]:this.selectedKeys.filter((v: string) => v!==key); })
        }
        Text(label).fontSize(13).fontColor(this.focusKey===key?this.palette.accent:SECONDARY).onClick(() => { this.selectField(key); })
        Blank()
        if (this.candidates.some((f: FieldCandidate) => f.key===key)) { Text('定位原文 ↗').fontSize(11).fontColor(this.palette.accent).onClick(() => { this.selectField(key); }) }
      }.width('100%')
      if (key==='notes') {
        TextArea({text:fieldValue(this.draft,key),placeholder:'补充提交要求或备注'}).id('field-notes').fontSize(15).fontColor(INK).height(132).maxLength(500).backgroundColor('#78EDF1F5').borderRadius(14).type(TextAreaType.NORMAL).enablePreviewText(true).onFocus(() => { if (this.sheetOpen) { this.sheetDetent=Math.round(this.sheetBaseHeight*0.92); } }).onChange((v: string,p?: PreviewText) => { if (canCommitText(p?.value)) { this.updateField(key,v); } })
      } else {
        TextInput({text:fieldValue(this.draft,key),placeholder:key==='title'?'给这件事一个名字':key==='date'?'YYYY-MM-DD；缺年可留 MM-DD':key==='deadline'?'YYYY-MM-DD HH:mm':key==='startTime'||key==='endTime'?'HH:mm':key==='context'?'例如：移动应用开发':'可手动填写'}).id('field-'+key).fontSize(15).fontColor(INK).height(46).maxLength(120).backgroundColor('#78EDF1F5').borderRadius(14).type(InputType.Normal).enablePreviewText(true).onFocus(() => { if (this.sheetOpen) { this.sheetDetent=Math.round(this.sheetBaseHeight*0.92); } }).onChange((v: string,p?: PreviewText) => { if (canCommitText(p?.value)) { this.updateField(key,v); } })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  associationChoices() {
    if (this.active.id && this.matches.length && !this.draft.id) {
      Column({space:15}) {
        Row({space:8}) { this.glyph('link',18); Text('关联建议').fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK); Blank(); Text('由你决定').fontSize(11).fontColor(SECONDARY) }.width('100%')
        Text('相同标题也可能是不同安排。请核对课程、日期与来源后再选择。').fontSize(12).fontColor(SECONDARY).lineHeight(21)
        Row({space:10}) {
          Text(!this.targetId?'●':'○').fontSize(21).fontColor(this.palette.accent)
          Column({space:4}) { Text('保存为新事项').fontSize(15).fontColor(INK); Text('保持独立，不修改已有安排').fontSize(11).fontColor(SECONDARY) }.alignItems(HorizontalAlign.Start)
        }.width('100%').padding(14).backgroundColor(!this.targetId?this.palette.soft:'#50FFFFFF').borderRadius(16).onClick(() => { this.targetId=''; }).id('save-as-new')
        ForEach(this.matches,(m: MatchCandidate) => {
          Column({space:9}) {
            Row({space:8}) {
              if (!m.alreadyLinked) { Text(this.targetId===m.task.id?'●':'○').fontSize(20).fontColor(this.palette.accent) }
              Text(m.task.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK).maxLines(2).layoutWeight(1)
              Text(m.level).fontSize(10).fontColor(m.conflicts.length?DANGER:this.palette.accent)
            }.width('100%')
            Text((m.task.context?m.task.context+' · ':'')+(m.task.deadline||m.task.date||'日期待补充')+(m.task.startTime?' '+m.task.startTime:'')).fontSize(12).fontColor(SECONDARY)
            Text(m.reasons.join(' · ')).fontSize(11).fontColor(this.palette.accent).lineHeight(18)
            if (m.conflicts.length) { Text(m.conflicts.join('；')).fontSize(11).fontColor(DANGER).lineHeight(19) }
            if (m.alreadyLinked) { this.smallButton('查看已关联事项',() => { this.openDetail(m.task); }) }
          }.width('100%').alignItems(HorizontalAlign.Start).padding(14).backgroundColor(this.targetId===m.task.id?this.palette.soft:'#66FFFFFF').border({width:this.targetId===m.task.id?1:0,color:this.palette.accent}).borderRadius(17)
            .onClick(() => { if (!m.alreadyLinked) { this.targetId=m.task.id; } }).id('match-'+m.task.id)
        },(m: MatchCandidate) => m.task.id+'_'+m.score+'_'+m.level)
        if (this.targetId) { Text('仅采用勾选的字段。保存前会展示新旧值，请逐项确认。').fontSize(12).fontColor(this.palette.accent).lineHeight(21) }
      }.width('100%').padding(18).alignItems(HorizontalAlign.Start).paperSurface()
    }
  }
  @Builder
  transcriptEditor() {
    if ((this.active.path || !this.draft.id) && this.active.mode!=='example') {
      Column({space:12}) {
        Row() {
          Text('识别原文').fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK); Blank()
          Button(this.showTranscript?'收起':'展开 / 修正').fontSize(12).fontColor(this.palette.accent).height(32).backgroundColor(this.palette.soft).borderRadius(11).onClick(() => { this.showTranscript=!this.showTranscript; })
        }.width('100%')
        if (this.showTranscript || !this.active.lines.length) {
          TextArea({text:this.manualText,placeholder:'可输入或粘贴原文，每行一段'}).id('manual-original-text').height(152).fontSize(14).fontColor(INK).backgroundColor('#78EDF1F5').borderRadius(14).type(TextAreaType.NORMAL).enablePreviewText(true).onFocus(() => { if (this.sheetOpen) { this.sheetDetent=Math.round(this.sheetBaseHeight*0.92); } }).onChange((v: string,p?: PreviewText) => { if (canCommitText(p?.value)) { this.manualText=v; this.reviewDirty=true; } })
          Text('按文字重新整理后，会标记为手工补充；原始图像坐标不再作为修改后文字的依据。').fontSize(11).fontColor(SECONDARY).lineHeight(18)
          this.smallButton('按补充文字整理字段',() => { this.extractManual(); })
        } else { Text(this.active.lines.length+' 段文字 · 可对照原图核对').fontSize(12).fontColor(SECONDARY) }
      }.width('100%').padding(18).alignItems(HorizontalAlign.Start).paperSurface()
    }
  }
  @Builder
  reviewPage() {
    Column({space:20}) {
      if (this.active.error) { Text(this.active.error).fontSize(12).fontColor(DANGER).lineHeight(21); this.smallButton('重新识别图片',() => { this.recognizeAgain(); }) }
      this.transcriptEditor()
      ForEach(this.warnings,(warning: string) => { Text(warning).fontSize(12).fontColor(DANGER).lineHeight(21) })
      this.associationChoices()
      Column({space:22}) {
        Text('事项信息').fontSize(18).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
        this.editor('title','标题')
        this.editor('context','所属课程 / 项目')
        ForEach(FIELD_KEYS.slice(1,8),(key: string,i: number) => { this.editor(key,FIELD_LABELS[i+1]) })
        Row({space:8}) {
          Text('状态').fontSize(13).fontColor(SECONDARY)
          Select([{value:'待办'},{value:'已完成'},{value:'已取消'}]).value(this.draft.status).font({size:13}).fontColor(INK).backgroundColor('#78EDF1F5').borderRadius(12).onSelect((_i: number,v: string) => { this.updateField('status',v); })
          Blank()
          Select([{value:'普通事项'},{value:'出行'},{value:'活动'},{value:'作业'}]).value(this.draft.type).font({size:13}).fontColor(INK).backgroundColor('#78EDF1F5').borderRadius(12).onSelect((_i: number,v: string) => { this.updateField('type',v); })
        }.width('100%')
        if (this.targetId) {
          Flex({wrap:FlexWrap.Wrap}) {
            Row({space:5}) { Checkbox({name:'status-update'}).select(this.selectedKeys.includes('status')).selectedColor(this.palette.accent).onChange((v: boolean) => { this.selectedKeys=v?[...this.selectedKeys.filter((k: string) => k!=='status'),'status']:this.selectedKeys.filter((k: string) => k!=='status'); }); Text('采用状态').fontSize(12).fontColor(SECONDARY) }.margin({right:14})
            Row({space:5}) { Checkbox({name:'type-update'}).select(this.selectedKeys.includes('type')).selectedColor(this.palette.accent).onChange((v: boolean) => { this.selectedKeys=v?[...this.selectedKeys.filter((k: string) => k!=='type'),'type']:this.selectedKeys.filter((k: string) => k!=='type'); }); Text('采用类型').fontSize(12).fontColor(SECONDARY) }
          }
        }
      }.width('100%').padding(20).alignItems(HorizontalAlign.Start).paperSurface()
      Text('保存即确认本页信息。来源与历次修改会分别保留。').fontSize(11).fontColor(SECONDARY).lineHeight(19)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  reviewDock() {
    Row({space:12}) {
      Column({space:5}) {
        Text(this.targetId?'关联并更新':'待你确认').fontSize(13).fontWeight(FontWeight.Medium).fontColor(INK)
        Text(this.targetId?this.selectedKeys.length+' 个字段被选中':'原文依据一直保留').fontSize(10).fontColor(SECONDARY)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button(this.targetId?'确认关联更新':'确认并保存').height(46).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#FFFFFF').backgroundColor(this.palette.accent).borderRadius(17).padding({left:20,right:20}).enabled(!this.busy).onClick(() => { this.saveReview(); }).id('save-review')
    }.width('100%').padding({left:22,right:22,top:12,bottom:16}).backgroundColor(this.appearance.clearGlass?'#FFFFFF':'#28FFFFFF').border({width:{top:1},color:'#90FFFFFF'})
  }
  @Builder
  detailPage() {
    Column({space:20}) {
      Column({space:15}) {
        Row() { Text(this.detail.type).fontSize(12).fontColor(this.palette.accent); Blank(); Text(this.detail.status).fontSize(12).fontColor(SECONDARY) }.width('100%')
        Text(this.detail.title).fontSize(27).fontWeight(FontWeight.Bold).fontColor(INK).lineHeight(36)
        if (this.detail.context) { Text(this.detail.context).fontSize(13).fontColor(SECONDARY) }
        Flex({wrap:FlexWrap.Wrap}) {
          this.smallButton('编辑',() => { this.editDetail(); })
          Button(this.detail.status==='已完成'?'恢复待办':'标记完成').fontSize(14).fontColor(this.palette.accent).backgroundColor('#D9FFFFFF').borderRadius(16).height(44).padding({left:16,right:16}).margin({right:8,bottom:8}).enabled(!this.busy).onClick(() => { this.changeStatus(this.detail.status==='已完成'?'待办':'已完成'); })
          this.smallButton('取消事项',() => { this.changeStatus('已取消'); })
        }
      }.padding(22).width('100%').alignItems(HorizontalAlign.Start).glassSurface()
      Column({space:18}) {
        ForEach(FIELD_KEYS.slice(1,8),(key: string,i: number) => {
          if (fieldValue(this.detail,key)) {
            Column({space:7}) { Text(FIELD_LABELS[i+1]).fontSize(12).fontColor(SECONDARY); Text(fieldValue(this.detail,key)).fontSize(16).fontColor(INK).lineHeight(25).copyOption(CopyOptions.LocalDevice) }.width('100%').alignItems(HorizontalAlign.Start)
          }
        })
        if (!this.detail.date && !this.detail.deadline && !this.detail.notes && !this.detail.location) { Text('可以编辑补充日期、地点和备注。').fontSize(14).fontColor(SECONDARY) }
      }.padding(20).width('100%').alignItems(HorizontalAlign.Start).paperSurface()
      Column({space:14}) {
        Row() { Text('来源依据').fontSize(18).fontWeight(FontWeight.Medium).fontColor(INK); Blank(); Text(this.detail.sourceIds.length+' 份').fontSize(12).fontColor(SECONDARY) }.width('100%')
        if (!this.detail.sourceIds.length) { Text('此事项暂未关联截图，可从来源档案中补充。').fontSize(13).fontColor(SECONDARY).lineHeight(22) }
        ForEach(this.sources.filter((s: SourceRecord) => this.detail.sourceIds.includes(s.id)),(s: SourceRecord) => {
          Column({space:9}) {
            Row({space:12}) {
              Image('file://'+s.path).width(48).height(62).objectFit(ImageFit.Contain).backgroundColor('#F2FFFFFF').borderRadius(10)
              Column({space:5}) { Text(s.name).fontSize(14).fontColor(INK).maxLines(2); Text((s.archived?'已归档 · ':'')+'查看原图与关联事项').fontSize(11).fontColor(this.palette.accent) }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              this.glyph('chevron',14)
            }.width('100%').onClick(() => { this.openSource(s,'detail'); })
            Button('解除当前关联').fontSize(12).fontColor(SECONDARY).height(44).backgroundColor('#00FFFFFF').padding({left:0,right:14}).borderRadius(12).onClick(() => { this.detachFromDetail(s); }).id('detach-'+s.id)
          }.width('100%').alignItems(HorizontalAlign.Start).padding({bottom:8})
        },(s: SourceRecord) => s.id+'_'+s.name+'_'+s.archived)
        this.smallButton('前往来源管理',() => { this.navigate('home'); this.tab='来源'; })
      }.padding(20).width('100%').alignItems(HorizontalAlign.Start).paperSurface()
      Column({space:15}) {
        Row({space:9}) { this.glyph('clock',19); Text('系统提醒').fontSize(18).fontWeight(FontWeight.Medium).fontColor(INK) }.width('100%')
        Text(this.detail.reminderId>=0?'已设置 · '+displayAt(this.detail.reminderAt):'尚未设置提醒').fontSize(13).fontColor(this.detail.reminderId>=0?this.palette.accent:SECONDARY)
        if (this.detail.reminderId>=0) { this.smallButton('取消已设置的提醒',() => { this.cancelReminder(); }) }
        else if (this.detail.status==='待办') {
          Row({space:10}) {
            TextInput({text:this.reminderDate,placeholder:'YYYY-MM-DD'}).layoutWeight(1).height(46).fontSize(14).fontColor(INK).backgroundColor('#78EDF1F5').borderRadius(14).onChange((v: string) => { this.reminderDate=v; })
            TextInput({text:this.reminderTime,placeholder:'HH:mm'}).width(100).height(46).fontSize(14).fontColor(INK).backgroundColor('#78EDF1F5').borderRadius(14).onChange((v: string) => { this.reminderTime=v; })
          }.width('100%')
          Flex({wrap:FlexWrap.Wrap}) { this.smallButton('设置提醒',() => { this.setReminder(); },true); this.smallButton('1分钟测试提醒',() => { this.setReminder(true); }) }
        }
      }.padding(20).width('100%').alignItems(HorizontalAlign.Start).paperSurface()
      Column({space:16}) {
        Text('变更历史').fontSize(18).fontWeight(FontWeight.Medium).fontColor(INK)
        ForEach(this.historyList,(h: HistoryRecord) => {
          Column({space:7}) {
            Text(h.action).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette.accent)
            Text(displayAt(h.at)).fontSize(10).fontColor(SECONDARY)
            ForEach(h.changes,(change: string) => { Text(change).fontSize(12).fontColor(SECONDARY).lineHeight(20) })
            if (!h.changes.length) { Text('保留原事项信息').fontSize(12).fontColor(SECONDARY) }
          }.width('100%').alignItems(HorizontalAlign.Start).padding({bottom:14}).border({width:{bottom:1},color:'#12637086'})
        },(h: HistoryRecord) => h.id)
      }.padding(20).width('100%').alignItems(HorizontalAlign.Start).paperSurface()
      Button('删除事项').fontSize(13).fontColor(DANGER).backgroundColor('#BFFFFFFF').borderRadius(16).height(44).padding({left:18,right:18}).onClick(() => { this.changeStatus('已删除'); }).enabled(!this.busy)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  sourcePage() {
    Column({space:20}) {
      this.sectionTitle('一份原文，多处可查。','命名、标签与关联，只整理关系，不改写原图。')
      this.preview()
      Column({space:16}) {
        Text('来源信息').fontSize(18).fontWeight(FontWeight.Medium).fontColor(INK)
        Column({space:7}) {
          Text('名称').fontSize(12).fontColor(SECONDARY)
          TextInput({text:this.sourceName,placeholder:'给这份来源起个名字'}).id('source-name').height(46).maxLength(80).fontSize(15).fontColor(INK).backgroundColor('#78EDF1F5').borderRadius(14).enablePreviewText(true).onChange((v: string,p?: PreviewText) => { if (canCommitText(p?.value)) { this.sourceName=v; this.sourceDirty=true; } })
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column({space:7}) {
          Text('标签').fontSize(12).fontColor(SECONDARY)
          TextInput({text:this.sourceTags,placeholder:'例如：课程，作业（用逗号分隔）'}).id('source-tags').height(46).maxLength(120).fontSize(14).fontColor(INK).backgroundColor('#78EDF1F5').borderRadius(14).enablePreviewText(true).onChange((v: string,p?: PreviewText) => { if (canCommitText(p?.value)) { this.sourceTags=v; this.sourceDirty=true; } })
          Text('最多 6 个标签，每个 16 字。').fontSize(10).fontColor(SECONDARY)
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column({space:7}) {
          Text('来源备注').fontSize(12).fontColor(SECONDARY)
          TextArea({text:this.sourceNote,placeholder:'记录这份截图的背景信息'}).id('source-note').height(88).maxLength(300).fontSize(14).fontColor(INK).backgroundColor('#78EDF1F5').borderRadius(14).enablePreviewText(true).onChange((v: string,p?: PreviewText) => { if (canCommitText(p?.value)) { this.sourceNote=v; this.sourceDirty=true; } })
        }.width('100%').alignItems(HorizontalAlign.Start)
        this.smallButton('保存来源信息',() => { this.saveSourceMeta(); },true)
      }.width('100%').padding(20).alignItems(HorizontalAlign.Start).paperSurface()
      Column({space:15}) {
        Row() { Text('已关联事项').fontSize(18).fontWeight(FontWeight.Medium).fontColor(INK); Blank(); Text(this.sourceTasks(this.active.id).length+' 个').fontSize(12).fontColor(SECONDARY) }.width('100%')
        if (!this.sourceTasks(this.active.id).length) { Text('暂未关联。可以核对字段创建事项，也可以只把原图补充到已有事项。').fontSize(13).fontColor(SECONDARY).lineHeight(22) }
        ForEach(this.sourceTasks(this.active.id),(task: TaskRecord) => {
          Row({space:12}) {
            Column({space:5}) { Text(task.title).fontSize(15).fontColor(INK).maxLines(2); Text((task.context?task.context+' · ':'')+(task.deadline||task.date||'日期待补充')).fontSize(11).fontColor(SECONDARY) }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            this.glyph('chevron',15)
          }.width('100%').padding({top:8,bottom:12}).onClick(() => { this.openDetail(task,'source'); })
        },(task: TaskRecord) => task.id+'_'+task.revision)
        Flex({wrap:FlexWrap.Wrap}) {
          this.smallButton('核对字段 / 创建事项',() => { this.openReview(this.active,'source'); })
          this.smallButton('仅补充来源到已有事项',() => { this.openAttach(); })
        }
        if (this.historyRefs.length) { Text('在 '+this.historyRefs.length+' 个事项的历史中保留依据。解除当前关联后，原图仍受历史保护。').fontSize(11).fontColor(SECONDARY).lineHeight(19) }
      }.width('100%').padding(20).alignItems(HorizontalAlign.Start).paperSurface()
      Column({space:14}) {
        Text('识别原文').fontSize(18).fontWeight(FontWeight.Medium).fontColor(INK)
        if (this.active.lines.length) { Text(this.active.lines.map((l: OcrLine) => l.text).join(String.fromCharCode(10))).fontSize(13).fontColor(SECONDARY).lineHeight(23).copyOption(CopyOptions.LocalDevice) }
        else { Text('尚无转写文字，可重新识别图片。').fontSize(13).fontColor(SECONDARY) }
      }.width('100%').padding(20).alignItems(HorizontalAlign.Start).paperSurface()
      Row({space:10}) {
        Button(this.active.archived?'移回在用来源':'归档来源').height(44).fontSize(13).fontColor(this.palette.accent).backgroundColor('#CFFFFFFF').borderRadius(16).padding({left:17,right:17}).onClick(() => { this.toggleArchive(); }).enabled(!this.busy)
        Blank()
        Button('永久删除').height(44).fontSize(12).fontColor(DANGER).backgroundColor('#AFFFFFFF').borderRadius(16).padding({left:17,right:17}).onClick(() => { this.deleteSource(this.active); }).enabled(!this.busy)
      }.width('100%')
      Text('归档可以恢复；被事项或历史引用的来源不会被永久删除。').fontSize(11).fontColor(SECONDARY).lineHeight(19)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  attachPage() {
    List({space:13}) {
      ListItem() {
        Column({space:17}) {
          this.sectionTitle('只补充依据。','为已有事项增加这份截图，保留原有标题、时间和地点。')
          Text(this.active.name).fontSize(13).fontColor(this.palette.accent).maxLines(2)
          Search({value:this.attachQuery,placeholder:'搜索事项或课程'}).height(46).fontColor(INK).backgroundColor('#BFFFFFFF').borderRadius(16).enablePreviewText(true).onChange((v: string,p?: PreviewText) => { if (canCommitText(p?.value)) { this.attachQuery=v; this.refreshAttach(); } }).id('attach-search')
        }.width('100%')
      }
      LazyForEach(this.attachData,(task: TaskRecord) => {
        ListItem() {
          Row({space:12}) {
            Column({space:7}) { Text(task.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK).maxLines(2); Text((task.context?task.context+' · ':'')+(task.deadline||task.date||'日期待补充')).fontSize(12).fontColor(SECONDARY); Text(task.sourceIds.includes(this.active.id)?'已经关联':task.sourceIds.length+' 份已有来源').fontSize(11).fontColor(this.palette.accent) }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            this.glyph(task.sourceIds.includes(this.active.id)?'shield':'plus',19)
          }.width('100%').padding(20).paperSurface().onClick(() => { this.attachTo(task); }).id('attach-'+task.id)
        }
      },(task: TaskRecord) => task.id+'_'+task.revision)
      if (!this.attachData.totalCount()) { ListItem() { Text('没有匹配事项，可返回后先创建。').fontSize(14).fontColor(SECONDARY).padding(24).width('100%') } }
      ListItem() { Row().height(32) }
    }.width('100%').height('100%').padding({left:22,right:22,top:16}).cachedCount(3).scrollBar(BarState.Off)
  }
  private wallpaper(id: string): Resource {
    switch (id) {
      case 'rose-gold': return $r('app.media.silk_rose');
      case 'matcha': return $r('app.media.silk_matcha');
      case 'mist-purple': return $r('app.media.silk_purple');
      case 'moon-silver': return $r('app.media.silk_silver');
      case 'apricot': return $r('app.media.silk_apricot');
      default: return $r('app.media.silk_blue');
    }
  }
  private evidenceFields(): FieldCandidate[] {
    const order=['deadline','startTime','endTime','location','date','destination','title','context','notes'];
    return this.candidates.filter((field: FieldCandidate) => field.boxes.length>0).slice().sort((a: FieldCandidate,b: FieldCandidate) => order.indexOf(a.key)-order.indexOf(b.key));
  }
  private compactSheet(): boolean { return this.sheetMode==='review' && this.sheetDetent<this.sheetBaseHeight*0.36; }
  @Builder
  ambientBackground() {
    Image(this.wallpaper(this.palette.id)).width('100%').height('100%').objectFit(ImageFit.Cover).draggable(false).hitTestBehavior(HitTestMode.None)
  }
  @Builder
  originalCanvas() {
    if (this.active.path) {
      Scroll(this.imageScroller) {
        Column({space:14}) {
          Row({space:8}) { Text(this.sourceCaption(this.active)).fontSize(11).fontColor(SECONDARY).layoutWeight(1); Text(this.focusKey?FIELD_LABELS[FIELD_KEYS.indexOf(this.focusKey)]+' · 红框核对':'点抽屉里的字段，定位原文').fontSize(10).fontColor(this.focusKey?DANGER:SECONDARY) }.width('100%')
          Stack({alignContent:Alignment.TopStart}) {
            Image('file://'+this.active.path).width('100%').aspectRatio(this.active.width/Math.max(1,this.active.height)).objectFit(ImageFit.Contain).draggable(false)
            ForEach(this.boxes,(box: Box) => { Rect().width(scaledBox(box,this.active.width,this.previewWidth).width).height(scaledBox(box,this.active.width,this.previewWidth).height).fill('#18BA3E4D').stroke(DANGER).strokeWidth(2).position({x:scaledBox(box,this.active.width,this.previewWidth).x,y:scaledBox(box,this.active.width,this.previewWidth).y}).hitTestBehavior(HitTestMode.None) })
          }.width('100%').aspectRatio(this.active.width/Math.max(1,this.active.height)).backgroundColor('#FFFFFF').borderRadius(18).clip(true).onAreaChange((_before: Area,after: Area) => { this.previewWidth=Number(after.width); }).shadow({radius:18,offsetY:6,color:'#122A384A'}).id('original-evidence')
          Text('原图保留在下方 · 抽屉可上滑、下拉').fontSize(11).fontColor(SECONDARY)
          Row().height(560)
        }.width('100%').padding({left:22,right:22,top:12,bottom:32})
      }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    } else {
      Column({space:14}) { Image($r('app.media.screen_mark')).width(68).height(68).borderRadius(22); Text(this.draft.id?'让安排更准确。':'把重要的事，轻轻记下。').fontSize(23).fontWeight(FontWeight.Medium).fontColor(INK); Text('写下文字，整理成一份清楚的安排。').fontSize(12).fontColor(SECONDARY) }.width('100%').height('54%').justifyContent(FlexAlign.Center)
    }
  }
  @Builder
  createChoice(title: string, subtitle: string, icon: string, action: () => void) {
    Button() {
      Row({space:15}) {
        Row() { this.glyph(icon,22) }.width(48).height(48).borderRadius(17).backgroundColor('#60FFFFFF').justifyContent(FlexAlign.Center)
        Column({space:6}) { Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK); Text(subtitle).fontSize(11).fontColor(SECONDARY) }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        this.glyph('chevron',15)
      }.width('100%').padding(15)
    }.width('100%').backgroundColor('#50FFFFFF').border({width:1,color:'#A0FFFFFF'}).borderRadius(23).enabled(!this.busy).onClick(action).accessibilityText(title)
  }
  @Builder
  bottomSheet() {
    Column({space:0}) {
      Row({space:12}) {
        Column({space:5}) {
          Text(this.sheetMode==='create'?'从哪里开始？':this.draft.id?'编辑安排':'核对，让信息成事').fontSize(20).fontWeight(FontWeight.Medium).fontColor(INK)
          Text(this.sheetMode==='create'?'一张截图，也可以是一段文字。':'上滑编辑 · 下拉看原图').fontSize(11).fontColor(SECONDARY)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('×').width(34).height(34).fontSize(23).fontColor(SECONDARY).backgroundColor('#60FFFFFF').borderRadius(17).enabled(!this.busy).onClick(() => { this.goBack(); }).id('sheet-close').accessibilityText('关闭抽屉')
      }.width('100%').padding({left:22,right:22,top:7,bottom:12})
      if (this.activityLabel) { Row() { this.activityCapsule() }.width('100%').justifyContent(FlexAlign.Center).padding({bottom:10}) }
      if (this.sheetMode==='review' && this.active.path && !this.reviewWorking) {
        Scroll() {
          Row({space:7}) {
            Button('看原图 ↓').height(31).fontSize(11).fontColor(this.palette.accent).backgroundColor('#60FFFFFF').borderRadius(15).onClick(() => { this.sheetDetent=Math.round(this.sheetBaseHeight*0.24); }).id('sheet-peek')
            Button('展开 ↑').height(31).fontSize(11).fontColor(this.palette.accent).backgroundColor('#50FFFFFF').borderRadius(15).onClick(() => { this.sheetDetent=Math.round(this.sheetBaseHeight*0.92); }).id('sheet-expand')
            ForEach(this.evidenceFields(),(field: FieldCandidate) => {
              Button(fieldValue(this.draft,field.key).slice(0,24)||field.label).height(31).fontSize(11).fontColor(this.focusKey===field.key?DANGER:this.palette.accent).backgroundColor(this.focusKey===field.key?'#F5FFFFFF':'#50FFFFFF').borderRadius(15).padding({left:12,right:12}).onClick(() => { this.selectField(field.key); }).id('evidence-'+field.key)
            })
          }.padding({left:22,right:22})
        }.width('100%').height(38).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      if (this.compactSheet()) {
        Row({space:12}) {
          Text(this.boxes.length?'红框已定位 · 可滑动原图查看':'向上轻滑，继续核对字段').fontSize(11).fontColor(this.boxes.length?DANGER:SECONDARY).layoutWeight(1)
          Button('继续核对 ↑').height(34).fontSize(12).fontColor(this.palette.accent).backgroundColor('#90FFFFFF').borderRadius(17).onClick(() => { this.sheetDetent=Math.round(this.sheetBaseHeight*0.56); }).id('sheet-half')
        }.width('100%').layoutWeight(1).padding({left:22,right:22,bottom:18})
      } else {
      Scroll(this.reviewScroller) {
        Column({space:12}) {
          if (this.sheetMode==='create') {
            this.createChoice('导入截图','在本机识别文字，保留原文依据','scan',() => { this.importPicture(); })
            this.createChoice('输入文字','粘贴通知，或手动新建一件事','plus',() => { this.newTask(); })
            Text('图片和文字留在本机，无需账号。').fontSize(11).fontColor(SECONDARY).width('100%').textAlign(TextAlign.Center).padding({top:12})
          } else if (this.reviewWorking) {
            Column({space:16}) { LoadingProgress().width(30).height(30).color(this.palette.accent); Text('正在从原图整理信息').fontSize(17).fontColor(INK); Text('处理完成后，请核对字段再保存。').fontSize(12).fontColor(SECONDARY) }.width('100%').padding({top:35,bottom:45})
          } else { this.reviewPage() }
        }.width('100%').constraintSize({maxWidth:720}).padding({left:22,right:22,top:12,bottom:24})
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).nestedScroll({scrollForward:NestedScrollMode.SELF_FIRST,scrollBackward:NestedScrollMode.PARENT_FIRST})
      if (this.sheetMode==='review' && !this.reviewWorking) { this.reviewDock() }
      }
    }.width('100%').height('100%')
      .backgroundEffect({radius:this.appearance.clearGlass?0:24,saturation:1.25,brightness:1.05,color:this.appearance.clearGlass?'#F8FAFC':'#35FFFFFF'})
      .linearGradient({angle:135,colors:[['#40FFFFFF',0],['#08FFFFFF',0.5],['#30FFFFFF',1]]})
  }
  build() {
    Stack({alignContent:Alignment.Top}) {
      this.ambientBackground()
      Column() {
        this.appHeader()
        if (!this.ready) {
          Column({space:17}) { LoadingProgress().width(30).height(30).color(this.palette.accent); Text(this.statusMessage||'正在整理本机记录…').fontSize(13).fontColor(SECONDARY) }.layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Stack({alignContent:Alignment.Bottom}) {
            Swiper(this.swiper) {
              Column() { this.tasksPage() }.width('100%').height('100%').id('page-tasks')
              Column() { this.sourcesPage() }.width('100%').height('100%').id('page-sources')
              Scroll(this.settingsScroller) { Column() { this.settingsPage() }.width('100%').constraintSize({maxWidth:760}).padding({left:22,right:22,top:18,bottom:120}) }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).id('page-appearance')
            }.width('100%').height('100%').index(this.currentTab).indicator(false).loop(false).cachedCount(2).duration(this.appearance.reduceMotion?0:260).curve(Curve.EaseOut)
              .onChange((index: number) => { this.currentTab=index; this.tab=['事项','来源','外观'][index]; this.dockProgress=index; })
              .onContentDidScroll((_selected: number,index: number,position: number,_length: number) => { this.dockProgress=clampPage(index-position); })
              .visibility(this.screen==='home'?Visibility.Visible:Visibility.Hidden)
            if (this.screen==='review') { this.originalCanvas() }
            else if (this.screen==='attach') { this.attachPage() }
            else if (this.screen!=='home') {
              Scroll(this.scroller) {
                Column() { if (this.screen==='detail') { this.detailPage() } else if (this.screen==='source') { this.sourcePage() } }.width('100%').constraintSize({maxWidth:760}).padding({left:22,right:22,top:18,bottom:36})
              }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
                .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({y:12})))
            }
            if (this.screen==='home') {
              GlassDock({progress:$dockProgress,selected:this.currentTab,palette:this.palette,clearGlass:this.appearance.clearGlass,reduceMotion:this.appearance.reduceMotion,disabled:this.busy,onSelect:(index: number) => { this.selectTab(index); },onCreate:() => { this.openCreate(); }}).margin({bottom:12})
            }
            if (this.activityLabel && !this.sheetOpen) { Row() { this.activityCapsule() }.align(Alignment.Top).width('100%').justifyContent(FlexAlign.Center).padding({top:8}).hitTestBehavior(HitTestMode.None) }
          }.layoutWeight(1).width('100%')
        }
      }.width('100%').height('100%')
    }.width('100%').height('100%').backgroundColor(this.palette.background)
      .onAreaChange((_before: Area,after: Area) => { if (!this.sheetOpen && Number(after.height)>500) { this.sheetBaseHeight=Number(after.height); } })
      .bindSheet($$this.sheetOpen,this.bottomSheet(),{
        detents:[Math.round(this.sheetBaseHeight*0.24),Math.round(this.sheetBaseHeight*0.56),Math.round(this.sheetBaseHeight*0.92)],detentSelection:this.sheetDetent,
        preferType:SheetType.BOTTOM,dragBar:true,showClose:false,maskColor:'#080F2030',
        backgroundColor:this.appearance.clearGlass?'#F8FAFC':'#10F5F8FC',blurStyle:BlurStyle.NONE,
        systemMaterial:glassMaterial(this.appearance.clearGlass,true),
        borderWidth:1,borderColor:'#BFFFFFFF',radius:{topLeft:32,topRight:32},
        shadow:{radius:28,offsetY:-4,color:'#13243850'},scrollSizeMode:ScrollSizeMode.CONTINUOUS,
        enableOutsideInteractive:this.sheetMode==='review',keyboardAvoidMode:deviceInfo.sdkApiVersion>=13?SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE:undefined,
        onDetentsDidChange:(height: number) => { console.info('ScreenshotToTask sheet settled px='+height); this.sheetDetent=[0.24,0.56,0.92].map((fraction: number) => Math.round(this.sheetBaseHeight*fraction)).sort((a: number,b: number) => Math.abs(a-this.getUIContext().px2vp(height))-Math.abs(b-this.getUIContext().px2vp(height)))[0]; },
        onWillDismiss:(action: DismissSheetAction) => { this.dismissSheet(action); },
        onDisappear:() => { this.sheetDidDisappear(); }
      })
  }
}
