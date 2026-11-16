import {
  KeyboardAvoidMode
}
from '@kit.ArkUI';
import {
  common, ConfigurationConstant
}
from '@kit.AbilityKit';
import {
  BusinessError, deviceInfo
}
from '@kit.BasicServicesKit';
import {
  webview
}
from '@kit.ArkWeb';
import {
  GlassDock
}
from '../ui/GlassDock';
import {
  PdfHost
}
from '../ui/PdfHost';
import {
  CameraCapture
}
from '../ui/CameraCapture';
import {
  TaskListData
}
from '../ui/ListData';
import {
  canCommitText
}
from '../domain/TextEntry';
import {
  ThemePalette, THEMES, themeById
}
from '../ui/Appearance';
import {
  Repository
}
from '../data/Repository';
import {
  Images
}
from '../platform/Images';
import {
  AppearanceStore
}
from '../platform/AppearanceStore';
import {
  Documents
}
from '../platform/Documents';
import {
  Recognition
}
from '../platform/Recognition';
import {
  Reminders
}
from '../platform/Reminders';
import {
  Permissions, PermissionState
}
from '../platform/Permissions';
import {
  loadModels
}
from '../platform/ModelLoader';
import {
  analyzeAsync
}
from '../platform/Semantics';
import {
  TaskRecord, SourceRecord, OcrLine, HistoryRecord, cloneTask, setField, fieldValue, FIELD_KEYS, FIELD_LABELS
}
from '../domain/Models';
import {
  validateTask
}
from '../domain/Rules';
import {
  rankMatches
}
from '../domain/Association';
import {
  Profile, Preferences, CompanionState, Drink, Fortune, fortune, dayKey, waterTotal, addDrink, completionReward, waterTimes
}
from '../domain/Companion';
import {
  TASK_TYPES, eventAt, timeConflicts, mergeUpdate, updateIntent, Course
}
from '../domain/Timeline';
import {
  SemanticEngine
}
from '../domain/Neural';
import {
  CAMPUS_JW, CAMPUS_LMS, campusUrlAllowed, inspectCampusPage, parseIcs
}
from '../domain/Campus';
@Entry
@Component
struct Index {
  @State ready: boolean=false;
  @State busy: boolean=false;
  @State launch: boolean=true;
  @State launchOpacity: number=0;
  @State launchCover: number=1;
  @State currentTab: number=0;
  @State dockProgress: number=0;
  @State screen: string='home';
  @State @Watch('refreshAgenda') selectedDay: string=dayKey();
  @State query: string='';
  @State @Watch('refreshAgenda') tasks: TaskRecord[]=[];
  @State deleted: TaskRecord[]=[];
  @State courses: Course[]=[];
  @State preferences: Preferences=new Preferences();
  @State profile: Profile=new Profile();
  @State companion: CompanionState=new CompanionState();
  @State palette: ThemePalette=themeById('morandi-blue');
  @State permission: PermissionState=new PermissionState();
  @State daily: Fortune=fortune('guest');
  @State revealed: boolean=false;
  @State drawRotation: number=0;
  @State petScale: number=1;
  @State message: string='';
  @State sheetOpen: boolean=false;
  @State sheetMode: string='import';
  @State sheetHeight: number=420;
  @State baseHeight: number=800;
  @State draft: TaskRecord=new TaskRecord();
  @State active: SourceRecord=new SourceRecord();
  @State original: TaskRecord=new TaskRecord();
  @State transcript: string='';
  @State pending: TaskRecord[]=[];
  @State pendingIndex: number=0;
  @State warnings: string[]=[];
  @State history: HistoryRecord[]=[];
  @State selectedKeys: string[]=[];
  @State matched: TaskRecord[]=[];
  @State campusUrl: string=CAMPUS_JW;
  @State campusStatus: string='在校方页面登录，打开个人信息、课表或作业页';
  @State campusText: string='';
  @State campusStudent: string='';
  @State campusName: string='';
  @State customWater: string='250';
  @StorageLink('systemDark') systemDark: boolean=false;
  private context: common.UIAbilityContext|null=null;
  private repo: Repository=new Repository();
  private recognition: Recognition=new Recognition();
  private reminders: Reminders=new Reminders();
  private permissions: Permissions=new Permissions();
  private engine: SemanticEngine=new SemanticEngine();
  private images: Images|null=null;
  private documents: Documents|null=null;
  private taskData: TaskListData=new TaskListData();
  private queryTimer: number=-1;
  private swiper: SwiperController=new SwiperController();
  private web: webview.WebviewController=new webview.WebviewController();
  private dirty: boolean=false;
  private confirmOpen: boolean=false;
  private dateTimer: number=-1;
  private fortuneDay: string=dayKey();
  private owner: string='guest';
  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.initialize();
  }
  aboutToDisappear(): void {
    clearInterval(this.dateTimer);
    clearTimeout(this.queryTimer);
  }
  onPageShow(): void {
    if(this.ready) {
      this.refreshPermissions();
    }
  }
  onBackPress(): boolean {
    if(this.sheetOpen){
      this.closeSheet();
      return true;
    }
    if(this.screen!=='home'){
      this.screen='home';
      return true;
    }
    return false;
  }
  private dark(): boolean {
    return this.preferences.mode==='night'||(this.preferences.mode==='system'&&this.systemDark);
  }
  private ink(): string {
    return this.dark()?'#EBE7DD':'#292E2A';
  }
  private secondary(): string {
    return this.dark()?'#B5B3A9':'#72766D';
  }
  private card(): string {
    return this.dark()?'#D92D302B':'#D9FFFDF6';
  }
  private lineColor(): string {
    return this.dark()?'#454940':'#DDDCD1';
  }
  private accent(): string {
    return this.dark()?this.palette.glow:this.palette.accent;
  }
  private toast(value: string): void {
    this.message=value;
    this.getUIContext().getPromptAction().showToast({
      message:value,duration:3000
    });
  }
  private fail(e: Object): void {
    this.toast((e as BusinessError).message||String(e));
  }
  private async initialize(): Promise<void> {
    try {
      this.context=this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.images=new Images(this.context);
      this.documents=new Documents(this.context);
      this.recognition.setContext(this.context);
      this.reminders.setContext(this.context);
      await this.repo.open(this.context);
      const remembered=await this.repo.deviceValue('activeOwner');
      if(remembered){
        this.owner=remembered;
        this.repo.setOwner(remembered);
      }
      await this.loadAccount();
      try{
        this.engine=await loadModels(this.context);
      }
      catch(e){
        this.fail(e);
      }
      await this.refreshPermissions();
      await this.reload();
      this.ready=true;
      this.getUIContext().animateTo({
        duration:this.preferences.reduceMotion?0:350,curve:Curve.EaseOut
      },()=>{
        this.launchOpacity=1;
      });
      setTimeout(()=>{
        this.getUIContext().animateTo({
          duration:this.preferences.reduceMotion?0:280
        },()=>{
          this.launchCover=0;
        });
        setTimeout(()=>{
          this.launch=false;
        },300);
      },650);
      this.dateTimer=setInterval(()=>{
        const today=dayKey();
        if(today!==this.fortuneDay){
          this.fortuneDay=today;
          this.daily=fortune(this.owner);
          this.revealed=false;
        }
      },60000);
    }
    catch(e){
      this.launch=false;
      this.fail(e);
    }
  }
  private async loadAccount(): Promise<void> {
    const p=await this.repo.readValue('profile'),s=await this.repo.readValue('settings'),f=await this.repo.readValue('fun'),c=await this.repo.readValue('courses');
    this.profile=p?JSON.parse(p) as Profile:new Profile();
    this.profile.ownerId=this.owner;
    this.preferences=s?JSON.parse(s) as Preferences:new Preferences();
    this.companion=f?JSON.parse(f) as CompanionState:new CompanionState();
    this.courses=c?JSON.parse(c) as Course[]:[];
    if(!s && this.owner==='guest' && this.context){
      const legacy=await new AppearanceStore().open(this.context);
      this.preferences.themeId=legacy.themeId;
      this.preferences.clearGlass=legacy.clearGlass;
      this.preferences.reduceMotion=legacy.reduceMotion;
    }
    this.palette=themeById(this.preferences.themeId);
    this.daily=fortune(this.owner);
    this.revealed=(await this.repo.readValue('fortune'))===dayKey();
    this.applyMode();
  }
  private async reload(): Promise<void> {
    const all=await this.repo.tasks(true);
    this.tasks=all.filter((t:TaskRecord)=>t.status!=='已删除');
    this.deleted=all.filter((t:TaskRecord)=>t.status==='已删除');
  }
  private async refreshPermissions(): Promise<void> {
    try{
      this.permission=await this.permissions.read();
    }
    catch(e){
      this.fail(e);
    }
  }
  private applyMode(): void {
    if(this.context){
      this.context.getApplicationContext().setColorMode(this.preferences.mode==='system'?ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET:this.preferences.mode==='night'?ConfigurationConstant.ColorMode.COLOR_MODE_DARK:ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    }
  }
  private async saveSettings(): Promise<void> {
    this.palette=themeById(this.preferences.themeId);
    this.applyMode();
    try{
      await this.repo.writeValue('settings',JSON.stringify(this.preferences));
    }
    catch(e){
      this.fail(e);
    }
  }
  private changeMode(mode: string): void {
    const p=JSON.parse(JSON.stringify(this.preferences)) as Preferences;
    p.mode=mode;
    this.preferences=p;
    this.saveSettings();
  }
  private async saveFun(): Promise<void> {
    await this.repo.writeValue('fun',JSON.stringify(this.companion));
  }
  private selectTab(index: number): void {
    this.getUIContext().animateTo({
      duration:this.preferences.reduceMotion?0:220,curve:Curve.EaseOut
    },()=>{
      this.currentTab=index;
      this.dockProgress=index;
    });
    this.swiper.changeIndex(index,true);
  }
  private days(): string[] {
    const d=new Date(this.selectedDay+'T12:00:00');
    d.setDate(d.getDate()-(d.getDay()+6)%7);
    const out:string[]=[];
    for(let i=0;
    i<7;
    i++){
      out.push(dayKey(d.getTime()));
      d.setDate(d.getDate()+1);
    }
    return out;
  }
  private pickDate(): void {
    DatePickerDialog.show({
      selected:new Date(this.selectedDay+'T12:00:00'),onDateAccept:(date:Date)=>{
        this.selectedDay=dayKey(date.getTime());
      }
    });
  }
  private moveWeek(delta: number): void {
    const d=new Date(this.selectedDay+'T12:00:00');
    d.setDate(d.getDate()+delta*7);
    this.selectedDay=dayKey(d.getTime());
  }
  private refreshAgenda(): void {
    this.taskData.replace(this.dayTasks());
  }
  private search(value:string): void {
    this.query=value;
    clearTimeout(this.queryTimer);
    this.queryTimer=setTimeout(()=>{
      this.refreshAgenda();
    },150);
  }
  private dayTasks(): TaskRecord[] {
    const q=this.query.toLowerCase();
    return this.tasks.filter((t:TaskRecord)=>(t.date===this.selectedDay||t.deadline.startsWith(this.selectedDay)||((!t.date||t.date.length<10)&&(!t.deadline||t.deadline.length<16)))&&(!q||[t.title,t.location,t.type,t.notes].join(' ').toLowerCase().includes(q))).sort((a:TaskRecord,b:TaskRecord)=>(eventAt(a)||Number.MAX_SAFE_INTEGER)-(eventAt(b)||Number.MAX_SAFE_INTEGER));
  }
  private openSheet(mode: string,full: boolean=false): void {
    this.sheetMode=mode;
    this.sheetHeight=Math.round(this.baseHeight*(full?0.92:0.56));
    this.sheetOpen=true;
  }
  private closeSheet(): void {
    if(this.busy){
      this.toast('正在处理，请稍候');
      return;
    }
    if(!this.dirty){
      this.sheetOpen=false;
      return;
    }
    if(this.confirmOpen){
      return;
    }
    this.confirmOpen=true;
    this.getUIContext().getPromptAction().showDialog({
      title:'放弃未保存的修改？',message:'已保存的日程不受影响。',buttons:[{
        text:'继续编辑',color:this.accent()
      },{
        text:'放弃',color:'#A74F47'
      }]
    }).then((r)=>{
      if(r.index===1){
        this.discardSheet();
      }
    }).finally(()=>{
      this.confirmOpen=false;
    });
  }
  private async discardSheet(): Promise<void> {
    if(this.sheetMode==='profile'||this.sheetMode==='water'){
      await this.loadAccount();
    }
    this.dirty=false;
    this.sheetOpen=false;
  }
  private edit(t: TaskRecord): void {
    this.draft=cloneTask(t);
    this.active=new SourceRecord();
    this.original=new TaskRecord();
    this.warnings=[];
    this.pending=[];
    this.history=[];
    this.transcript='';
    this.dirty=false;
    this.openSheet('edit',true);
  }
  private newSchedule(): void {
    this.edit(new TaskRecord());
    this.draft.date=this.selectedDay;
    this.draft.reminderMinutes=this.preferences.reminderMinutes;
  }
  private update(key: string,value: string): void {
    const t=cloneTask(this.draft);
    setField(t,key,value);
    this.draft=t;
    this.dirty=true;
  }
  private async importFrom(kind: string): Promise<void> {
    if(this.busy||!this.images||!this.documents){
      return;
    }
    if(kind==='camera'){
      if(!this.context){
        return;
      }
      try{
        await this.permissions.camera(this.context);
        this.sheetOpen=false;
        this.screen='camera';
      }
      catch(e){
        this.fail(e);
      }
      return;
    }
    this.busy=true;
    try{
      const uri=kind==='album'?await this.images.choose():await this.documents.choose();
      if(uri){
        await this.consume(uri,kind);
      }
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
      await this.refreshPermissions();
    }
  }
  private async consume(uri: string, kind: string='camera'): Promise<void> {
    if(!this.images||!this.documents){
      return;
    }
    this.busy=true;
    this.sheetOpen=false;
    this.screen='home';
    this.message='正在读取文件';
    try{
      let source=kind==='file'?await this.documents.read(uri):await this.images.importUri(uri);
      const old=await this.repo.byHash(source.hash);
      if(old){
        this.images.remove(source);
        source=old;
        const linked=this.tasks.filter((t:TaskRecord)=>t.sourceIds.includes(old.id));
        if(linked.length){
          this.matched=linked;
          this.dirty=false;
          this.openSheet('duplicates',true);
          this.toast('这份文件已经录入，请打开已有日程');
          return;
        }
        if(this.deleted.some((t:TaskRecord)=>t.sourceIds.includes(old.id))){
          this.screen='recycle';
          this.toast('这份文件对应的日程在回收站');
          return;
        }
      }
      if(source.ocrState!=='recognized'){
        await this.recognition.run(source,(stage:string)=>{
          this.message=stage;
        });
      }
      await this.repo.putSource(source);
      this.active=source;
      this.transcript=source.lines.map((l:OcrLine)=>l.text).join('\n');
      if(this.transcript.includes('BEGIN:VCALENDAR')){
        this.courses=parseIcs(this.transcript);
        await this.repo.writeValue('courses',JSON.stringify(this.courses));
        this.screen='courses';
        this.toast('已导入 '+this.courses.length+' 节课');
      }
      else{
        await this.analyze();
        if(source.error){
          this.warnings=[source.error,...this.warnings];
        }
      }
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
    }
  }
  private async analyze(): Promise<void> {
    this.busy=true;
    try{
      if(!this.active.id && this.documents && this.transcript.trim()){
        const source=await this.documents.fromText(this.transcript);
        const old=await this.repo.byHash(source.hash);
        if(old && this.images){
          this.images.remove(source);
          this.active=old;
          const linked=this.tasks.filter((t:TaskRecord)=>t.sourceIds.includes(old.id));
          if(linked.length){
            this.matched=linked;
            this.dirty=false;
            this.openSheet('duplicates',true);
            return;
          }
        }
        else{
          this.active=source;
          await this.repo.putSource(source);
        }
      }
      const r=await analyzeAsync(this.engine,this.transcript);
      this.pending=r.tasks;
      this.pendingIndex=0;
      this.warnings=r.warnings;
      this.original=new TaskRecord();
      this.draft=cloneTask(r.tasks[0]);
      this.draft.reminderMinutes=this.preferences.reminderMinutes;
      const evidence=new SourceRecord();
      evidence.id=this.active.id;
      evidence.lines=this.transcript.split('\n').map((v:string,i:number)=>new OcrLine('input_'+i,v));
      this.matched=rankMatches(this.draft,this.tasks,evidence).filter((m)=>!m.alreadyLinked).slice(0,3).map((m)=>m.task);
      this.dirty=true;
      this.openSheet('edit',true);
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
    }
  }
  private chooseUpdate(t: TaskRecord): void {
    this.original=cloneTask(t);
    this.selectedKeys=FIELD_KEYS.filter((k:string)=>!!fieldValue(this.draft,k)&&fieldValue(this.draft,k)!==fieldValue(t,k)&&k!=='context'&&k!=='status');
    if(updateIntent(this.transcript)==='取消'){
      this.draft.status='已取消';
      this.selectedKeys.push('status');
    }
    this.openSheet('merge',true);
  }
  private async saveDraft(confirmed: boolean=false): Promise<void> {
    if(this.busy||!this.context){
      return;
    }
    let t=this.original.id?mergeUpdate(this.original,this.draft,this.selectedKeys):cloneTask(this.draft);
    const errors=validateTask(t);
    if(errors.length){
      this.warnings=errors;
      return;
    }
    const conflicts=timeConflicts(t,this.tasks);
    if(conflicts.length&&!confirmed){
      const r=await this.getUIContext().getPromptAction().showDialog({
        title:'时间重叠',message:conflicts.map((v:TaskRecord)=>v.title+' '+v.startTime+'–'+v.endTime).join('\n'),buttons:[{
          text:'继续编辑',color:this.accent()
        },{
          text:'仍然保存',color:this.accent()
        }]
      });
      if(r.index===1){
        this.saveDraft(true);
      }
      return;
    }
    this.busy=true;
    try{
      t=await this.repo.saveTask(t,this.original.id?'按通知'+updateIntent(this.transcript):t.id?'编辑日程':'新建日程',this.active.id?this.active:null);
      t=await this.syncReminder(t);
      const date=t.deadline.slice(0,10)||t.date;
      if(date.length===10){this.selectedDay=date;}
      this.companion=completionReward(this.companion,t);
      await this.saveFun();
      await this.reload();
      if(this.pendingIndex+1<this.pending.length){
        this.pendingIndex++;
        this.draft=cloneTask(this.pending[this.pendingIndex]);
        this.original=new TaskRecord();
        this.matched=[];
        this.warnings=[];
        this.toast('已保存，继续下一条');
      }
      else{
        this.dirty=false;
        this.sheetOpen=false;
        this.toast('已保存');
      }
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
    }
  }
  private async syncReminder(t: TaskRecord): Promise<TaskRecord> {
    if(!this.context){
      return t;
    }
    const old=t.reminderId,at=eventAt(t)-(t.reminderMinutes===undefined?this.preferences.reminderMinutes:t.reminderMinutes)*60000;
    let next=cloneTask(t);
    next.reminderId=-1;
    next.reminderAt=0;
    if(!this.preferences.notifications||t.status!=='待办'||!eventAt(t)||at<Date.now()+10000){
      try{
        await this.reminders.cancel(old);
        next.reminderState=this.preferences.notifications&&t.status==='待办'&&eventAt(t)?'提前时间已过，未登记':'未设置';
      }
      catch(e){
        next.reminderId=old;
        next.reminderAt=t.reminderAt;
        next.reminderState='取消失败：'+(e as Error).message;
      }
      return await this.repo.saveTask(next,'更新系统提醒状态');
    }
    let id=-1;
    try{
      id=await this.reminders.publish(t,at,this.context);
      next.reminderId=id;
      next.reminderAt=at;
      next.reminderState=id<=-2?'已登记至系统日历':'已登记';
      next=await this.repo.saveTask(next,'登记系统提醒');
    }
    catch(e){
      if(id!==-1){
        try{
          await this.reminders.cancel(id);
        }
        catch(_){
        }
      }
      next=cloneTask(t);
      next.reminderState='登记失败：'+(e as Error).message;
      next=await this.repo.saveTask(next,'提醒登记失败');
      this.toast(next.reminderState);
      return next;
    }
    if(old!==-1&&old!==id){
      try{
        await this.reminders.cancel(old);
      }
      catch(e){
        next.reminderState='新提醒已登记，旧提醒取消失败：'+old;
        next=await this.repo.saveTask(next,'旧提醒取消失败');
        this.toast('请检查系统旧提醒 '+old);
      }
    }
    return next;
  }
  private async status(t: TaskRecord,value: string): Promise<void> {
    if(this.busy){
      return;
    }
    this.busy=true;
    try{
      const n=cloneTask(t);
      n.status=value;
      const saved=await this.syncReminder(await this.repo.saveTask(n,value));
      this.companion=completionReward(this.companion,saved);
      await this.saveFun();
      await this.reload();
      this.dirty=false;
      this.sheetOpen=false;
      this.toast(value==='已删除'?'已移入回收站':'已更新');
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
    }
  }
  private async showHistory(): Promise<void> {
    try{
      this.history=(await this.repo.history(this.draft.id)).filter((h:HistoryRecord)=>!['更新系统提醒状态','登记系统提醒','提醒登记失败','旧提醒取消失败'].includes(h.action));
      this.sheetMode='history';
    }
    catch(e){
      this.fail(e);
    }
  }
  private async restore(h: HistoryRecord): Promise<void> {
    if(this.busy){
      return;
    }
    this.busy=true;
    try{
      const t=this.tasks.find((v:TaskRecord)=>v.id===h.taskId)||this.deleted.find((v:TaskRecord)=>v.id===h.taskId);
      if(!t){
        return;
      }
      const saved=await this.repo.restore(t,h.id);
      this.draft=await this.syncReminder(saved);
      await this.reload();
      this.sheetMode='edit';
      this.dirty=false;
      this.toast('已恢复，恢复操作也保留在历史中');
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
    }
  }
  private async recover(t: TaskRecord): Promise<void> {
    if(this.busy){
      return;
    }
    this.busy=true;
    try{
      await this.syncReminder(await this.repo.recover(t));
      await this.reload();
      this.toast('已恢复');
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
    }
  }
  private async draw(): Promise<void> {
    if(this.revealed){
      return;
    }
    this.getUIContext().animateTo({
      duration:this.preferences.reduceMotion?0:360,curve:Curve.EaseInOut
    },()=>{
      this.drawRotation+=360;
      this.revealed=true;
    });
    await this.repo.writeValue('fortune',dayKey());
  }
  private async drink(ml: number): Promise<void> {
    if(this.busy){
      return;
    }
    this.busy=true;
    try{
      this.companion=addDrink(this.companion,ml);
      await this.saveFun();
      this.toast('已记录 '+ml+' mL');
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
    }
  }
  private async removeDrink(id: string): Promise<void> {
    this.companion.drinks=this.companion.drinks.filter((d:Drink)=>d.id!==id);
    this.companion=JSON.parse(JSON.stringify(this.companion)) as CompanionState;
    await this.saveFun();
  }
  private async stroke(): Promise<void> {
    const key=dayKey();
    if(!this.companion.strokes.includes(key)){
      this.companion.strokes.push(key);
      await this.saveFun();
    }
    this.getUIContext().animateTo({
      duration:130
    },()=>{
      this.petScale=1.06;
    });
    setTimeout(()=>{
      this.getUIContext().animateTo({
        duration:220,curve:Curve.EaseOut
      },()=>{
        this.petScale=1;
      });
    },150);
  }
  private pastDay(days: number): string {
    const d=new Date();
    d.setDate(d.getDate()-days);
    return dayKey(d.getTime());
  }
  private async waterReminders(): Promise<void> {
    if(!this.context||this.busy){
      return;
    }
    this.busy=true;
    try{
      const times=waterTimes(this.companion,Date.now());
      for(const id of this.companion.waterReminderIds){
        await this.reminders.cancel(id);
      }
      this.companion.waterReminderIds=[];
      for(const at of times){
        const t=new TaskRecord();
        t.title='喝点水，休息一下';
        t.location='记录今天的饮水量';
        this.companion.waterReminderIds.push(await this.reminders.publish(t,at,this.context));
      }
      await this.saveFun();
      this.toast('已登记 '+this.companion.waterReminderIds.length+' 条喝水提醒，打开应用可续订');
    }
    catch(e){
      await this.saveFun();
      this.fail(e);
    }
    finally{
      this.busy=false;
      await this.refreshPermissions();
    }
  }
  private async notificationToggle(value: boolean): Promise<void> {
    if(!this.context||this.busy){
      return;
    }
    this.busy=true;
    try{
      if(value&&!await this.permissions.notifications(this.context)){
        throw new Error('系统通知尚未允许');
      }
      this.preferences.notifications=value;
      this.preferences=JSON.parse(JSON.stringify(this.preferences)) as Preferences;
      await this.saveSettings();
      for(const t of this.tasks.filter((v:TaskRecord)=>v.status==='待办')){
        await this.syncReminder(t);
      }
      await this.reload();
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
      await this.refreshPermissions();
    }
  }
  private async logout(): Promise<void> {
    if(this.busy){
      return;
    }
    this.busy=true;
    try{
      for(const t of this.tasks){
        await this.reminders.cancel(t.reminderId);
      }
      for(const id of this.companion.waterReminderIds){
        await this.reminders.cancel(id);
      }
      const test=await this.repo.readValue('testReminder');
      if(test){
        await this.reminders.cancel(Number(test));
        await this.repo.writeValue('testReminder','');
      }
      webview.WebCookieManager.clearAllCookiesSync();
      this.owner='guest';
      this.repo.setOwner('guest');
      await this.repo.setDeviceValue('activeOwner','guest');
      await this.loadAccount();
      await this.reload();
      this.screen='home';
      this.toast('已退出，原账号数据保留并隔离');
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
    }
  }
  private async reparseOriginal(): Promise<void> {
    const previous=cloneTask(this.draft);await this.analyze();
    if(previous.id){this.original=previous;this.selectedKeys=FIELD_KEYS.filter((k:string)=>k!=='status'&&k!=='context'&&fieldValue(this.draft,k)!==fieldValue(previous,k)&&!!fieldValue(this.draft,k));if(this.warnings.some((w:string)=>w.includes('候选截止'))){this.selectedKeys.push('startTime','endTime');}this.sheetMode='merge';}
  }
  private async showOriginal(): Promise<void> {
    try{
      if(!this.active.id&&this.draft.sourceIds.length){
        const source=(await this.repo.sources()).find((s:SourceRecord)=>s.id===this.draft.sourceIds[0]);
        if(source){
          this.active=source;
          this.transcript=source.lines.map((l:OcrLine)=>l.text).join('\n');
        }
      }
      this.sheetMode='original';
    }
    catch(e){
      this.fail(e);
    }
  }
  private async testReminder(): Promise<void> {
    if(!this.context||this.busy){
      return;
    }
    this.busy=true;
    try{
      const task=new TaskRecord();
      task.title='后台提醒测试';
      task.notes='这是一条你手动发送的测试提醒';
      const at=Math.ceil((Date.now()+65000)/60000)*60000;
      const id=await this.reminders.publish(task,at,this.context);
      await this.repo.writeValue('testReminder',String(id));
      this.toast('已登记 '+new Date(at).toLocaleTimeString()+' 的测试提醒，可回桌面等待');
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
    }
  }
  private async chooseAvatar(): Promise<void> {
    if(!this.images||this.busy){
      return;
    }
    this.busy=true;
    try{
      const uri=await this.images.choose();
      if(uri){
        let source=await this.images.importUri(uri);
        const old=await this.repo.byHash(source.hash);
        if(old){
          this.images.remove(source);
          source=old;
        }
        else{
          await this.repo.putSource(source);
        }
        this.profile.avatarPath=source.path;
        this.dirty=true;
      }
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
    }
  }
  private openCampus(url: string): void {
    if(!this.preferences.campusConsent){
      this.toast('请先在设置中允许读取校园页面');
      return;
    }
    this.campusUrl=url;
    this.screen='campus';
    this.campusStatus='请在校方页面内登录，密码不交给应用保存';
  }
  private async readCampus(): Promise<void> {
    if(this.busy){
      return;
    }
    this.busy=true;
    try{
      const url=this.web.getUrl();
      if(!campusUrlAllowed(url)){
        throw new Error('只能读取西安交通大学正式页面');
      }
      const raw=await this.web.runJavaScript('JSON.stringify(document.body ? document.body.innerText.slice(0,100000) : "")');
      const p=inspectCampusPage(JSON.parse(raw) as string,url);
      this.campusText=p.text;
      this.campusStudent=p.authenticated?p.studentId:'';
      this.campusName=p.name;
      this.campusStatus=p.authenticated?'已读到账号标识，请确认后切换个人空间':'请打开显示学号的个人信息页验证账号。课表 / 作业正文可以先预览导入。';
      this.openSheet('campus',true);
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
    }
  }
  private async confirmCampus(): Promise<void> {
    if(!this.campusStudent||this.busy){
      return;
    }
    this.busy=true;
    try{
      for(const t of this.tasks){
        await this.reminders.cancel(t.reminderId);
      }
      for(const id of this.companion.waterReminderIds){
        await this.reminders.cancel(id);
      }
      const test=await this.repo.readValue('testReminder');
      if(test){
        await this.reminders.cancel(Number(test));
        await this.repo.writeValue('testReminder','');
      }
      this.owner='xjtu:'+this.campusStudent;
      this.repo.setOwner(this.owner);
      await this.repo.setDeviceValue('activeOwner',this.owner);
      await this.loadAccount();
      this.profile.studentId=this.campusStudent;
      this.profile.name=this.campusName||this.profile.name;
      this.profile.ownerId=this.owner;
      this.preferences.campusConsent=true;
      await this.repo.writeValue('profile',JSON.stringify(this.profile));
      await this.saveSettings();
      await this.reload();
      this.sheetOpen=false;
      this.toast('已切换到账号对应的本地空间');
    }
    catch(e){
      this.fail(e);
    }
    finally{
      this.busy=false;
    }
  }
  private campusImport(): void {
    this.transcript=this.campusText;
    this.active=new SourceRecord();
    this.screen='home';
    this.analyze();
  }
  @Styles surface() {
    .width('100%').padding(18).borderRadius(20).backgroundColor(this.card()).border({
      width:0.5,color:this.lineColor()
    })
  }
  @Builder
  smallButton(label: string,action: ()=>void) {
    Button(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.accent()).backgroundColor(this.dark()?'#42483F':this.palette.soft).borderRadius(14).height(42).onClick(action)
  }
  @Builder
  pageTitle(title: string) {
    Row(){
      Button('‹ 返回').fontColor(this.accent()).backgroundColor(Color.Transparent).padding(0).onClick(()=>{
        this.screen='home';
      });
      Blank();
      Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.ink());
      Blank();
    }.height(48).width('100%')
  }
  @Builder
  dateStrip() {
    Row(){
      Button('‹').backgroundColor(Color.Transparent).fontColor(this.accent()).width(30).onClick(()=>{
        this.moveWeek(-1);
      });
      ForEach(this.days(),(date:string,index:number)=>{
        Column({
          space:8
        }){
          Text(['一','二','三','四','五','六','日'][index]).fontSize(11).fontColor(this.secondary());
          Text(date.slice(8)).fontSize(17).fontWeight(date===this.selectedDay?FontWeight.Bold:FontWeight.Normal).fontColor(date===this.selectedDay?this.accent():this.ink());
          Row().width(4).height(4).borderRadius(2).backgroundColor(date===dayKey()?this.accent():Color.Transparent);
        }.layoutWeight(1).padding({
          top:10,bottom:6
        }).borderRadius(14).backgroundColor(date===this.selectedDay?this.card():Color.Transparent).onClick(()=>{
          this.selectedDay=date;
        }).id('day-'+index);
      },(date:string)=>date);
      Button('›').backgroundColor(Color.Transparent).fontColor(this.accent()).width(30).onClick(()=>{
        this.moveWeek(1);
      });
    }.width('100%').margin({
      bottom:12
    })
  }
  @Builder
  taskRow(t: TaskRecord) {
    Row({
      space:13
    }){
      Button(t.status==='已完成'?'✓':'').width(23).height(23).borderRadius(12).backgroundColor(t.status==='已完成'?this.palette.soft:Color.Transparent).border({
        width:1,color:this.secondary()
      }).fontColor(this.accent()).fontSize(14).onClick(()=>{
        this.status(t,t.status==='已完成'?'待办':'已完成');
      }).accessibilityText('完成 '+t.title);
      Column({
        space:7
      }){
        Text(t.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(t.status==='已取消'?this.secondary():this.ink()).maxLines(2);
        Text([t.type,t.deadline?t.deadline.slice(11)+' 截止':(t.startTime?t.startTime+(t.endTime?'–'+t.endTime:''):'未定时间'),t.location].filter((v:string)=>!!v).join(' · ')).fontSize(12).fontColor(this.secondary()).maxLines(2);
        if(t.status==='已取消'){
          Text('已取消').fontSize(11).fontColor('#AE6E5C');
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(()=>{
        this.edit(t);
      });
      Image($r('app.media.ui_chevron')).width(14).height(14).opacity(0.6).onClick(()=>{
        this.edit(t);
      });
    }.width('100%').padding({
      top:17,bottom:17
    }).border({
      width:{
        bottom:0.5
      },color:this.lineColor()
    }).id('task-'+t.id)
  }
  @Builder
  agenda() {
    if(this.dayTasks().length){
      ForEach(this.dayTasks(),(t:TaskRecord)=>{
        this.taskRow(t);
      },(t:TaskRecord)=>t.id+'-'+t.revision);
    }
    else{
      Column({
        space:12
      }){
        Text('这一天还没有安排').fontSize(16).fontColor(this.secondary());
        this.smallButton('添加日程',()=>{
          this.newSchedule();
        });
      }.width('100%').padding({
        top:36,bottom:36
      });
    }
  }
  @Builder
  fortuneCard() {
    Column({
      space:13
    }){
      Row(){
        Text('今日签').fontSize(14).fontColor(this.secondary());
        Blank();
        Text('仅供娱乐').fontSize(10).fontColor(this.secondary());
      }.width('100%');
      if(!this.revealed){
        Row(){
          Text('抽一枚签，给今天一点小灵感').fontSize(15).fontColor(this.ink()).layoutWeight(1);
          Button('抽签').backgroundColor(this.palette.soft).fontColor(this.palette.accent).borderRadius(22).onClick(()=>{
            this.draw();
          }).rotate({
            angle:this.drawRotation
          });
        }.width('100%');
      }
      else{
        Row({
          space:18
        }){
          Text(this.daily.level).fontSize(30).fontWeight(FontWeight.Medium).fontColor(this.accent());
          Column({
            space:8
          }){
            Text('宜  '+this.daily.good.join('、')).fontSize(12).fontColor(this.ink());
            Text('忌  '+this.daily.avoid.join('、')).fontSize(12).fontColor(this.secondary());
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        }.width('100%');
      }
    }.surface()
  }
  @Builder
  shortcut(label: string,icon: Resource,action: ()=>void) {
    Column({
      space:10
    }){
      Image(icon).width(22).height(22);
      Text(label).fontSize(14).fontColor(this.ink());
    }.layoutWeight(1).padding(18).borderRadius(18).backgroundColor(this.card()).border({
      width:0.5,color:this.lineColor()
    }).onClick(action)
  }
  @Builder
  agendaItems() {
    if(this.dayTasks().length){
      LazyForEach(this.taskData,(t:TaskRecord)=>{
        ListItem(){
          this.taskRow(t);
        }
      },(t:TaskRecord)=>t.id+'-'+t.revision);
    }
    else{
      ListItem(){
        Column({
          space:12
        }){
          Text('这一天还没有安排').fontSize(16).fontColor(this.secondary());
          this.smallButton('添加日程',()=>{
            this.newSchedule();
          });
        }.width('100%').padding({
          top:36,bottom:36
        });
      }
    }
  }
  @Builder
  home() {
    List({
      space:18
    }) {
      ListItem(){
        Column({
          space:18
        }){
          Row(){
            Column({
              space:6
            }){
              Text(new Date().toLocaleDateString('zh-CN',{
                month:'long',day:'numeric',weekday:'long'
              })).fontSize(13).fontColor(this.secondary());
              Text(this.profile.nickname||this.profile.name?'你好，'+(this.profile.nickname||this.profile.name):'今天').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.ink());
            }.alignItems(HorizontalAlign.Start);
            Blank();
            Button('今').width(38).height(38).fontColor(this.accent()).backgroundColor(this.card()).onClick(()=>{
              this.selectedDay=dayKey();
            });
          }.width('100%');
          this.fortuneCard();
          Row({
            space:10
          }){
            this.shortcut('课表',$r('app.media.ui_clock'),()=>{
              this.screen='courses';
            });
            this.shortcut('日程',$r('app.media.ui_home'),()=>{
              this.screen='schedule';
            });
            this.shortcut('录入',$r('app.media.ui_scan'),()=>{
              this.dirty=false;
              this.openSheet('import');
            });
          }.width('100%');
          Row(){
            Text('安排').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.ink());
            Blank();
            Text(this.selectedDay+' ▾').fontSize(12).fontColor(this.secondary()).onClick(()=>{
              this.pickDate();
            });
          }.width('100%');
          this.dateStrip();
        }.width('100%').padding({
          top:22
        }).alignItems(HorizontalAlign.Start);
      }
      this.agendaItems();
      ListItem(){
        Text(this.busy?this.message:'').fontSize(12).fontColor(this.secondary()).width('100%').height(110);
      }
    }.width('100%').height('100%').padding({
      left:24,right:24
    }).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).id('page-tasks')
  }
  @Builder
  schedule() {
    List({
      space:14
    }) {
      ListItem(){
        Column({
          space:14
        }){
          this.pageTitle('日程');
          Row(){
            Text(this.selectedDay.slice(0,7)+' ▾').fontSize(25).fontColor(this.ink()).onClick(()=>{
              this.pickDate();
            });
            Blank();
            this.smallButton('今天',()=>{
              this.selectedDay=dayKey();
            });
          }.width('100%');
          this.dateStrip();
          Search({
            value:this.query,placeholder:'查找这一天的日程'
          }).enablePreviewText(true).onChange((v:string,p?:PreviewText)=>{
            if(canCommitText(p?.value)){
              this.search(v);
            }
          }).fontColor(this.ink()).backgroundColor(this.card());
        }.width('100%');
      }
      this.agendaItems();
      ListItem(){
        this.smallButton('回收站 · '+this.deleted.length,()=>{
          this.screen='recycle';
        });
      }.padding({
        bottom:50
      });
    }.width('100%').height('100%').padding({
      left:24,right:24
    }).scrollBar(BarState.Off)
  }
  @Builder
  coursePage() {
    Scroll(){
      Column({
        space:18
      }){
        this.pageTitle('课表');
        this.dateStrip();
        if(!this.courses.length){
          Text('尚未同步课表').fontSize(23).fontColor(this.ink());
          Text('校园接口待本人登录验证。可打开教务系统查看课表，或导入学校导出的 ICS 文件；重复课程请先在导出端展开日期。').fontSize(14).lineHeight(23).fontColor(this.secondary());
        }
        ForEach(this.courses.filter((c:Course)=>c.date===this.selectedDay),(c:Course)=>{
          Column({
            space:8
          }){
            Text(c.name).fontSize(18).fontColor(this.ink());
            Text(c.start+'–'+c.end+'  '+c.location).fontSize(14).fontColor(this.secondary());
          }.surface();
        });
        this.smallButton('打开校方教务系统',()=>{
          this.openCampus(CAMPUS_JW);
        });
        this.smallButton('导入课表文件',()=>{
          this.importFrom('file');
        });
      }.width('100%').padding({
        left:24,right:24,bottom:40
      }).alignItems(HorizontalAlign.Start)
    }.height('100%').width('100%')
  }
  @Builder
  fun() {
    Scroll(){
      Column({
        space:18
      }){
        Text('小憩').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.ink()).width('100%');
        Text('喝水、看树，也看看小墨。').fontSize(14).fontColor(this.secondary()).width('100%');
        Column({
          space:17
        }){
          Row(){
            Text('今天喝了').fontSize(15).fontColor(this.secondary());
            Blank();
            Button('设置').backgroundColor(Color.Transparent).fontColor(this.accent()).padding(0).onClick(()=>{
              this.dirty=false;
              this.openSheet('water',true);
            });
          }.width('100%');
          Row({
            space:6
          }){
            Text(String(waterTotal(this.companion))).fontSize(38).fontColor(this.ink());
            Text('/ '+this.companion.goal+' mL').fontSize(14).fontColor(this.secondary()).margin({
              top:16
            });
          }.width('100%');
          Progress({
            value:Math.min(100,waterTotal(this.companion)/this.companion.goal*100),total:100,type:ProgressType.Linear
          }).width('100%').color(this.accent()).backgroundColor(this.lineColor());
          Row({
            space:8
          }){
            this.smallButton('+ 150 mL',()=>{
              this.drink(150);
            });
            this.smallButton('+ '+this.companion.cup+' mL',()=>{
              this.drink(this.companion.cup);
            });
            this.smallButton('记录',()=>{
              this.dirty=false;
              this.openSheet('water',true);
            });
          }.width('100%');
        }.surface();
        Column({
          space:12
        }){
          Row(){
            Text(this.companion.petName+' · '+this.companion.pet).fontSize(18).fontColor(this.ink());
            Blank();
            Text('Lv.'+(1+Math.floor(this.companion.completedIds.length/5))).fontSize(13).fontColor(this.accent());
          }.width('100%');
          Image($r('app.media.companion_cat')).width(180).height(150).scale({
            x:this.petScale,y:this.petScale
          }).onClick(()=>{
            this.stroke();
          });
          Text('摸摸它').fontSize(12).fontColor(this.secondary());
          Text('完成日程积累成长，不会因为离开而受伤。').fontSize(12).fontColor(this.secondary());
          TextInput({
            text:this.companion.petName,placeholder:'宠物名字'
          }).enablePreviewText(true).onChange((v:string,p?:PreviewText)=>{
            if(canCommitText(p?.value)){
              this.companion.petName=v.slice(0,16);
            }
          }).onBlur(()=>{
            this.saveFun();
          }).backgroundColor(Color.Transparent).fontColor(this.ink());
        }.surface();
        Column({
          space:12
        }){
          Row(){
            Text(this.companion.plantName).fontSize(18).fontColor(this.ink());
            Blank();
            Text(['萌芽','新叶','舒展','繁茂'][Math.min(3,Math.floor(this.companion.drinks.length/8))]).fontSize(13).fontColor(this.accent());
          }.width('100%');
          Image($r('app.media.companion_plant')).width(150+Math.min(50,this.companion.drinks.length*2)).height(160);
          Text('记录喝水，也给它浇一点水。').fontSize(12).fontColor(this.secondary());
          TextInput({
            text:this.companion.plantName,placeholder:'植物名字'
          }).enablePreviewText(true).onChange((v:string,p?:PreviewText)=>{
            if(canCommitText(p?.value)){
              this.companion.plantName=v.slice(0,16);
            }
          }).onBlur(()=>{
            this.saveFun();
          }).backgroundColor(Color.Transparent).fontColor(this.ink());
        }.surface();
        Column({
          space:8
        }){
          Text('近七日').fontSize(18).fontColor(this.ink()).width('100%');
          ForEach([6,5,4,3,2,1,0],(days:number)=>{
            Row(){
              Text(this.pastDay(days).slice(5)).fontSize(12).fontColor(this.secondary()).width(44);
              Progress({
                value:Math.min(100,waterTotal(this.companion,this.pastDay(days))/this.companion.goal*100),total:100,type:ProgressType.Linear
              }).color(this.accent()).layoutWeight(1);
              Text(String(waterTotal(this.companion,this.pastDay(days)))).fontSize(12).fontColor(this.secondary()).width(48).textAlign(TextAlign.End);
            }.width('100%');
          });
        }.surface();
      }.padding({
        left:24,right:24,top:22,bottom:120
      }).width('100%')
    }.width('100%').height('100%').scrollBar(BarState.Off).id('page-fun')
  }
  @Builder
  settingLabel(title: ()=>string,description: ()=>string) {
    Column({
      space:5
    }){
      Text(title()).fontSize(15).fontColor(this.ink());
      if(description()){
        Text(description()).fontSize(11).fontColor(this.secondary()).lineHeight(17);
      }
    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
  }
  @Builder
  settings() {
    Scroll(){
      Column({
        space:18
      }){
        Text('设置').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.ink()).width('100%');
        Column({
          space:16
        }){
          Row({
            space:14
          }){
            if(this.profile.avatarPath){
              Image(this.profile.avatarPath).width(52).height(52).objectFit(ImageFit.Cover).borderRadius(26);
            }
            else{
              Text(this.profile.avatar||'叶').fontSize(25).fontColor(this.accent()).width(52).height(52).textAlign(TextAlign.Center).backgroundColor(this.palette.soft).borderRadius(26);
            }
            this.settingLabel(()=>{
              return this.profile.name||'访客';
            },()=>{
              return this.owner==='guest'?'本地使用，无需登录':this.profile.studentId;
            });
          }.width('100%');
          this.smallButton(this.owner==='guest'?'登录西安交大账号':'打开校园服务',()=>{
            this.openCampus(CAMPUS_JW);
          });
          this.smallButton('完善个人资料',()=>{
            this.dirty=false;
            this.openSheet('profile',true);
          });
        }.surface();
        Column({
          space:16
        }){
          Text('外观').fontSize(18).fontColor(this.ink()).width('100%');
          Row({
            space:6
          }){
            ForEach(THEMES,(t:ThemePalette)=>{
              Column({
                space:6
              }){
                Row().width(31).height(31).borderRadius(16).backgroundColor(t.glow).border({
                  width:2,color:this.preferences.themeId===t.id?this.accent():Color.Transparent
                });
                Text(t.name).fontSize(9).fontColor(this.secondary());
              }.layoutWeight(1).onClick(()=>{
                this.preferences.themeId=t.id;
                this.saveSettings();
              });
            });
          }.width('100%');
          Row(){
            this.settingLabel(()=>{
              return '深浅模式';
            },()=>{
              return this.preferences.mode==='system'?'跟随系统':this.dark()?'夜间 · 深灰纸感':'白天 · 米白纸纹';
            });
            Stack({
              alignContent:Alignment.Start
            }){
              Row().width(32).height(32).borderRadius(16).backgroundColor(this.card()).translate({
                x:this.dark()?37:3
              }).animation({
                duration:this.preferences.reduceMotion?0:220,curve:Curve.EaseInOut
              });
              Row(){
                Image($r('app.media.ui_sun')).width(17).height(17).margin({
                  left:10,right:17
                });
                Image($r('app.media.ui_moon')).width(17).height(17);
              }.width(72).height(38);
            }.width(72).height(38).borderRadius(20).backgroundColor(this.lineColor()).onClick(()=>{
              this.changeMode(this.dark()?'day':'night');
            }).id('mode-toggle');
          }.width('100%');
          this.smallButton('跟随系统',()=>{
            this.changeMode('system');
          });
          Row(){
            this.settingLabel(()=>{
              return '减少动态效果';
            },()=>{
              return '缩短抽签、抽屉与切换动画';
            });
            Toggle({
              type:ToggleType.Switch,isOn:this.preferences.reduceMotion
            }).selectedColor(this.accent()).onChange((v:boolean)=>{
              this.preferences.reduceMotion=v;
              this.saveSettings();
            });
          }.width('100%');
          Row(){
            this.settingLabel(()=>{
              return '降低透明度';
            },()=>{
              return '玻璃 Dock 使用更实的底色';
            });
            Toggle({
              type:ToggleType.Switch,isOn:this.preferences.clearGlass
            }).selectedColor(this.accent()).onChange((v:boolean)=>{
              this.preferences.clearGlass=v;
              this.saveSettings();
            });
          }.width('100%');
        }.surface();
        Column({
          space:16
        }){
          Text('提醒').fontSize(18).fontColor(this.ink()).width('100%');
          Row(){
            this.settingLabel(()=>{
              return '日程通知';
            },()=>{
              return this.permission.notifications?'系统通知已允许':'系统通知尚未允许';
            });
            Toggle({
              type:ToggleType.Switch,isOn:this.preferences.notifications
            }).selectedColor(this.accent()).enabled(!this.busy).onChange((v:boolean)=>{
              this.notificationToggle(v);
            });
          }.width('100%');
          Row(){
            this.settingLabel(()=>{
              return '默认提前时间';
            },()=>{
              return '小时，每条日程也可单独调整';
            });
            TextInput({
              text:String(this.preferences.reminderMinutes/60)
            }).type(InputType.Number).width(78).fontColor(this.ink()).backgroundColor(Color.Transparent).onChange((v:string)=>{
              const n=Number(v);
              if(Number.isFinite(n)&&n>=0&&n<=720){
                this.preferences.reminderMinutes=Math.round(n*60);
              }
            }).onBlur(()=>{
              this.saveSettings();
            });
          }.width('100%');
          Text('已过的提前时间不会补发。系统未接受时会保留失败原因，可重新登记。').fontSize(11).fontColor(this.secondary());
          this.smallButton('重新登记日程提醒',()=>{
            this.notificationToggle(this.preferences.notifications);
          });
          this.smallButton('发送后台测试提醒',()=>{
            this.testReminder();
          });
        }.surface();
        Column({
          space:16
        }){
          Text('权限与校园数据').fontSize(18).fontColor(this.ink()).width('100%');
          Row(){
            this.settingLabel(()=>{
              return '读取校园页面';
            },()=>{
              return '点击读取时才访问正文，不保存密码';
            });
            Toggle({
              type:ToggleType.Switch,isOn:this.preferences.campusConsent
            }).selectedColor(this.accent()).onChange((v:boolean)=>{
              this.preferences.campusConsent=v;
              this.saveSettings();
            });
          }.width('100%');
          Row(){
            this.settingLabel(()=>{
              return '相机';
            },()=>{
              return this.permission.camera?'系统已允许':'使用时请求系统授权';
            });
            this.smallButton('管理',()=>{
              if(this.context){
                this.permissions.camera(this.context).then(()=>this.refreshPermissions()).catch((e:Error)=>this.fail(e));
              }
            });
          }.width('100%');
          Row(){
            this.settingLabel(()=>{
              return '日历提醒';
            },()=>{
              return this.permission.calendar?'系统已允许':'登记后台提醒时请求系统授权';
            });
          }.width('100%');
          Text('相册和文件由系统选择器逐项授权，无需开放整个存储空间。').fontSize(11).fontColor(this.secondary());
          this.smallButton('打开系统权限设置',()=>{
            if(this.context){
              this.permissions.settings(this.context).catch((e:Error)=>this.fail(e));
            }
          });
          this.smallButton('学习平台 · 课表 / 作业',()=>{
            this.openCampus(CAMPUS_LMS);
          });
        }.surface();
        this.smallButton('回收站 · '+this.deleted.length,()=>{
          this.screen='recycle';
        });
        if(this.owner!=='guest'){
          this.smallButton('退出登录',()=>{
            this.logout();
          });
        }
        Text('截图成事 0.9.0 · 数据保存在本机\n校园同步待本人登录验证').fontSize(11).fontColor(this.secondary()).width('100%').lineHeight(19);
      }.padding({
        left:24,right:24,top:22,bottom:120
      }).width('100%')
    }.width('100%').height('100%').scrollBar(BarState.Off).id('page-settings')
  }
  @Builder
  field(label: string,key: string,placeholder: string='') {
    Column({
      space:7
    }){
      Text(label).fontSize(12).fontColor(this.secondary()).width('100%');
      TextInput({
        text:fieldValue(this.draft,key),placeholder:placeholder
      }).fontSize(15).fontColor(this.ink()).placeholderColor(this.secondary()).backgroundColor(this.card()).borderRadius(12).height(46).enablePreviewText(true).onChange((v:string,p?:PreviewText)=>{
        if(canCommitText(p?.value)){
          this.update(key,v);
        }
      }).onFocus(()=>{
        this.sheetHeight=Math.round(this.baseHeight*0.92);
      }).id('field-'+key);
    }.width('100%')
  }
  @Builder
  editor() {
    Column({
      space:15
    }){
      Row(){
        Text(this.original.id?'更新日程':this.draft.id?'编辑日程':'新日程'+(this.pending.length>1?' '+(this.pendingIndex+1)+'/'+this.pending.length:'')).fontSize(23).fontWeight(FontWeight.Medium).fontColor(this.ink());
        Blank();
        Button('保存').fontColor(this.dark()?'#242522':'#FFFFFF').backgroundColor(this.accent()).borderRadius(20).enabled(!this.busy).onClick(()=>{
          this.saveDraft();
        }).id('save-task');
      }.width('100%');
      ForEach(this.warnings,(w:string)=>{
        Text(w).fontSize(12).fontColor('#AC6A50').width('100%');
      });
      this.field('任务','title','需要做什么');
      Scroll(){
        Row({
          space:7
        }){
          ForEach(TASK_TYPES,(type:string)=>{
            Button(type).height(32).fontSize(12).fontColor(this.draft.type===type?this.palette.accent:this.secondary()).backgroundColor(this.draft.type===type?this.palette.soft:Color.Transparent).onClick(()=>{
              this.update('type',type);
            });
          });
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%');
      this.field('日期','date','YYYY-MM-DD');
      Row({
        space:12
      }){
        Column(){
          this.field('开始','startTime','HH:mm');
        }.layoutWeight(1);
        Column(){
          this.field('结束','endTime','HH:mm');
        }.layoutWeight(1);
      }.width('100%');
      this.field('截止时间','deadline','YYYY-MM-DD HH:mm · 可不填');
      this.field('地点','location','在哪里');
      this.field('备注','notes','补充说明');
      Row(){
        this.settingLabel(()=>{
          return '提前提醒';
        },()=>{
          return '分钟；0 表示到点提醒';
        });
        TextInput({
          text:String(this.draft.reminderMinutes===undefined?this.preferences.reminderMinutes:this.draft.reminderMinutes)
        }).type(InputType.Number).fontColor(this.ink()).backgroundColor(this.card()).width(90).onChange((v:string)=>{
          const n=Number(v);
          if(n>=0&&n<=43200){
            this.draft.reminderMinutes=Math.round(n);
            this.dirty=true;
          }
        });
      }.width('100%');
      if(this.draft.reminderState!=='未设置'){
        Text(this.draft.reminderState).fontSize(11).fontColor(this.secondary()).width('100%');
      }
      if(this.transcript&&!this.draft.id){
        this.smallButton('查看 / 修正原文',()=>{
          this.sheetMode='text';
        });
        if(this.matched.length){
          Text('可能与现有日程有关').fontSize(13).fontColor(this.secondary()).width('100%');
          ForEach(this.matched,(t:TaskRecord)=>{
            this.smallButton('更新「'+t.title+'」',()=>{
              this.chooseUpdate(t);
            });
          });
        }
      }
      if(this.active.id||this.draft.sourceIds.length){
        this.smallButton('查看导入原文',()=>{
          this.showOriginal();
        });
      }
      if(this.draft.id){
        Row({
          space:8
        }){
          this.smallButton('变更记录',()=>{
            this.showHistory();
          });
          this.smallButton('取消日程',()=>{
            this.status(this.draft,'已取消');
          });
          this.smallButton('删除',()=>{
            this.status(this.draft,'已删除');
          });
        }.width('100%');
      }
    }.width('100%').padding({
      bottom:32
    })
  }
  @Builder
  profileField(label: string,value: string,change: (v:string)=>void) {
    Column({
      space:6
    }){
      Text(label).fontSize(12).fontColor(this.secondary()).width('100%');
      TextInput({
        text:value
      }).fontColor(this.ink()).backgroundColor(this.card()).enablePreviewText(true).onChange((v:string,p?:PreviewText)=>{
        if(canCommitText(p?.value)){
          this.dirty=true;
          change(v);
        }
      });
    }.width('100%')
  }
  @Builder
  sheet() {
    Scroll(){
      Column({
        space:18
      }){
        if(this.sheetMode==='import'){
          Text('录入日程').fontSize(24).fontColor(this.ink()).width('100%');
          this.smallButton('拍照',()=>{
            this.importFrom('camera');
          });
          this.smallButton('从相册选择',()=>{
            this.importFrom('album');
          });
          this.smallButton('选择文件 · 图片 / PDF / Word / 文本',()=>{
            this.importFrom('file');
          });
          this.smallButton('粘贴文字',()=>{
            this.transcript='';
            this.active=new SourceRecord();
            this.sheetMode='text';
            this.sheetHeight=Math.round(this.baseHeight*0.92);
          });
          this.smallButton('手动添加',()=>{
            this.newSchedule();
          });
        }
        else if(this.sheetMode==='edit'){
          this.editor();
        }
        else if(this.sheetMode==='text'){
          Text('通知原文').fontSize(23).fontColor(this.ink()).width('100%');
          TextArea({
            text:this.transcript,placeholder:'粘贴或输入通知文字。多条通知用空行分开。'
          }).height(260).fontColor(this.ink()).backgroundColor(this.card()).enablePreviewText(true).onChange((v:string,p?:PreviewText)=>{
            if(canCommitText(p?.value)){
              this.transcript=v;
              this.dirty=true;
            }
          });
          this.smallButton('整理日程',()=>{
            this.analyze();
          });
          Text('本机模型判断类型与文字角色，随后校验日期和时间。').fontSize(12).fontColor(this.secondary());
        }
        else if(this.sheetMode==='merge'){
          Text('确认变更').fontSize(23).fontColor(this.ink()).width('100%');
          ForEach(this.warnings,(warning:string)=>{Text(warning).fontSize(12).fontColor('#AC6A50').width('100%');});
          Text(this.original.title).fontSize(15).fontColor(this.secondary()).width('100%');
          ForEach(FIELD_KEYS.filter((k:string)=>fieldValue(this.draft,k)!==fieldValue(this.original,k)&&(!!fieldValue(this.draft,k)||this.selectedKeys.includes(k))),(key:string)=>{
            Row({
              space:10
            }){
              Checkbox({
                name:key,group:'merge'
              }).select(this.selectedKeys.includes(key)).selectedColor(this.accent()).onChange((v:boolean)=>{
                this.selectedKeys=v?[...this.selectedKeys,key]:this.selectedKeys.filter((k:string)=>k!==key);
              });
              Column({
                space:6
              }){
                Text(FIELD_LABELS[FIELD_KEYS.indexOf(key)]).fontSize(12).fontColor(this.secondary());
                Text((fieldValue(this.original,key)||'空')+' → '+(fieldValue(this.draft,key)||'空')).fontSize(14).fontColor(this.ink());
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            }.width('100%');
          });
          this.smallButton('确认更新',()=>{
            this.saveDraft();
          });
          this.smallButton('返回编辑',()=>{
            this.original=new TaskRecord();
            this.sheetMode='edit';
          });
        }
        else if(this.sheetMode==='duplicates'){
          Text('已经录入的日程').fontSize(23).fontColor(this.ink());
          ForEach(this.matched,(t:TaskRecord)=>{
            this.smallButton(t.title,()=>{
              this.edit(t);
            });
          });
        }
        else if(this.sheetMode==='original'){
          Text('导入原文').fontSize(23).fontColor(this.ink());
          if(this.active.path&&['offline','system'].includes(this.active.mode)){
            Image(this.active.path).width('100%').constraintSize({
              maxHeight:400
            }).objectFit(ImageFit.Contain);
          }
          Text(this.transcript||'没有读取到文字').fontSize(14).lineHeight(23).fontColor(this.ink());
          this.smallButton('重新整理原文',()=>{this.reparseOriginal();});
          this.smallButton('返回编辑',()=>{
            this.sheetMode='edit';
          });
        }
        else if(this.sheetMode==='history'){
          Text('变更记录').fontSize(23).fontColor(this.ink()).width('100%');
          ForEach(this.history,(h:HistoryRecord)=>{
            Column({
              space:8
            }){
              Text(h.action).fontSize(16).fontColor(this.ink());
              Text(new Date(h.at).toLocaleString()).fontSize(11).fontColor(this.secondary());
              Text(h.changes.join('\n')||'记录保存').fontSize(12).fontColor(this.secondary());
              if(h.before){
                this.smallButton('恢复此操作之前的版本',()=>{
                  this.restore(h);
                });
              }
            }.surface();
          });
        }
        else if(this.sheetMode==='profile'){
          Text('个人资料').fontSize(23).fontColor(this.ink()).width('100%');
          this.profileField('姓名',this.profile.name,(v:string)=>{
            this.profile.name=v;
            this.dirty=true;
          });
          this.profileField('昵称',this.profile.nickname,(v:string)=>{
            this.profile.nickname=v;
            this.dirty=true;
          });
          this.profileField('学校',this.profile.school,(v:string)=>{
            this.profile.school=v;
            this.dirty=true;
          });
          this.profileField('学号',this.profile.studentId,(v:string)=>{
            this.profile.studentId=v;
            this.dirty=true;
          });
          this.profileField('班级',this.profile.className,(v:string)=>{
            this.profile.className=v;
            this.dirty=true;
          });
          this.profileField('性别',this.profile.gender,(v:string)=>{
            this.profile.gender=v;
            this.dirty=true;
          });
          this.smallButton('从相册选择头像',()=>{
            this.chooseAvatar();
          });
          this.profileField('头像文字 / Emoji',this.profile.avatar,(v:string)=>{
            this.profile.avatar=v.slice(0,4);
            this.profile.avatarPath='';
            this.dirty=true;
          });
          Text('编辑资料不会改变登录账号和数据归属。').fontSize(11).fontColor(this.secondary());
          this.smallButton('保存资料',()=>{
            this.repo.writeValue('profile',JSON.stringify(this.profile)).then(()=>{
              this.dirty=false;
              this.sheetOpen=false;
              this.toast('已保存');
            }).catch((e:Error)=>this.fail(e));
          });
        }
        else if(this.sheetMode==='water'){
          this.waterSheet();
        }
        else if(this.sheetMode==='campus'){
          Text('校园页面').fontSize(23).fontColor(this.ink()).width('100%');
          Text(this.campusStatus).fontSize(13).fontColor(this.secondary());
          if(this.campusStudent){
            Text('学号：'+this.campusStudent+' '+this.campusName).fontSize(15).fontColor(this.ink());
            this.smallButton('确认账号并切换本地空间',()=>{
              this.confirmCampus();
            });
          }
          Text(this.campusText.slice(0,1500)).fontSize(12).fontColor(this.secondary());
          this.smallButton('预览并导入作业 / 日程',()=>{
            this.campusImport();
          });
        }
        Button('关闭').fontColor(this.secondary()).backgroundColor(Color.Transparent).onClick(()=>{
          this.closeSheet();
        });
      }.width('100%').alignItems(HorizontalAlign.Start).padding({
        left:24,right:24,top:16,bottom:36
      })
    }.height('100%').width('100%').scrollBar(BarState.Off)
  }
  @Builder
  waterSheet() {
    Text('喝水记录').fontSize(23).fontColor(this.ink()).width('100%');
    Row({
      space:10
    }){
      TextInput({
        text:this.customWater,placeholder:'mL'
      }).type(InputType.Number).fontColor(this.ink()).backgroundColor(this.card()).layoutWeight(1).onChange((v:string)=>{
        this.customWater=v;
      });
      this.smallButton('记录',()=>{
        this.drink(Number(this.customWater));
      });
    }.width('100%');
    this.profileField('每日目标 mL',String(this.companion.goal),(v:string)=>{
      const n=Number(v);
      if(n>=250&&n<=6000){
        this.companion.goal=n;
      }
    });
    this.profileField('常用杯量 mL',String(this.companion.cup),(v:string)=>{
      const n=Number(v);
      if(n>=10&&n<=2000){
        this.companion.cup=n;
      }
    });
    Row(){
      this.settingLabel(()=>{
        return '喝水系统提醒';
      },()=>{
        return '一次登记未来三天内最多12条，打开后可续订';
      });
      Toggle({
        type:ToggleType.Switch,isOn:this.companion.waterReminder
      }).selectedColor(this.accent()).onChange((v:boolean)=>{
        this.companion.waterReminder=v;
        this.dirty=true;
      });
    }.width('100%');
    this.profileField('开始时刻（0–22 点）',String(this.companion.waterStart),(v:string)=>{
      this.companion.waterStart=Number(v);
    });
    this.profileField('结束时刻（1–23 点）',String(this.companion.waterEnd),(v:string)=>{
      this.companion.waterEnd=Number(v);
    });
    this.profileField('间隔（分钟，至少30）',String(this.companion.waterInterval),(v:string)=>{
      this.companion.waterInterval=Number(v);
    });
    this.smallButton('保存并更新提醒',()=>{
      this.waterReminders();
    });
    Text('今天的记录 · 可撤销').fontSize(14).fontColor(this.secondary());
    ForEach(this.companion.drinks.filter((d:Drink)=>dayKey(d.at)===dayKey()).slice().reverse(),(d:Drink)=>{
      Row(){
        Text(new Date(d.at).toLocaleTimeString()+' '+d.ml+' mL').fontSize(14).fontColor(this.ink());
        Blank();
        Button('撤销').backgroundColor(Color.Transparent).fontColor(this.accent()).onClick(()=>{
          this.removeDrink(d.id);
        });
      }.width('100%');
    },(d:Drink)=>d.id);
  }
  @Builder
  campus() {
    Column(){
      this.pageTitle('校园服务');
      Row({
        space:8
      }){
        this.smallButton('教务',()=>{
          this.web.loadUrl(CAMPUS_JW);
        });
        this.smallButton('作业',()=>{
          this.web.loadUrl(CAMPUS_LMS);
        });
        this.smallButton('读取本页',()=>{
          this.readCampus();
        });
      }.width('100%').padding({
        bottom:8
      });
      Text(this.campusStatus).fontSize(11).fontColor(this.secondary()).width('100%').margin({
        bottom:8
      });
      Web({
        src:this.campusUrl,controller:this.web
      }).javaScriptAccess(true).domStorageAccess(true).fileAccess(false).mixedMode(MixedMode.None).onLoadIntercept((event)=>{
        if(!event){
          return false;
        }
        const url=event.data.getRequestUrl();
        return event.data.isMainFrame()?!campusUrlAllowed(url):!(/^(https:|data:|blob:)/i.test(url));
      }).layoutWeight(1).width('100%');
    }.padding({
      left:16,right:16
    }).width('100%').height('100%')
  }
  @Builder
  recycle() {
    Scroll(){
      Column({
        space:16
      }){
        this.pageTitle('回收站');
        if(!this.deleted.length){
          Text('回收站为空').fontSize(20).fontColor(this.secondary());
        }
        ForEach(this.deleted,(t:TaskRecord)=>{
          Row(){
            Text(t.title).fontSize(16).fontColor(this.ink()).layoutWeight(1);
            this.smallButton('恢复',()=>{
              this.recover(t);
            });
          }.surface();
        });
      }.padding(24).width('100%')
    }.height('100%').width('100%')
  }
  build() {
    Stack({
      alignContent:Alignment.Bottom
    }){
      PdfHost();
      Image(this.dark()?$r('app.media.paper_night'):$r('app.media.paper_day')).width('100%').height('100%').objectFit(ImageFit.Cover).hitTestBehavior(HitTestMode.None);
      Row().width('100%').height('100%').backgroundColor('#'+(this.dark()?'06':'0A')+this.palette.glow.slice(1)).hitTestBehavior(HitTestMode.None);
      if(this.ready){
        if(this.screen==='home'){
          Swiper(this.swiper){
            this.home();
            this.fun();
            this.settings();
          }.index(this.currentTab).cachedCount(3).indicator(false).loop(false).disableSwipe(this.sheetOpen).duration(this.preferences.reduceMotion?0:220).onChange((i:number)=>{
            this.currentTab=i;
            this.dockProgress=i;
          }).onContentDidScroll((_selected:number,index:number,position:number,_length:number)=>{
            this.dockProgress=Math.max(0,Math.min(2,index-position));
          }).width('100%').height('100%');
          GlassDock({
            progress:$dockProgress,selected:this.currentTab,palette:this.palette,dark:this.dark(),clearGlass:this.preferences.clearGlass,reduceMotion:this.preferences.reduceMotion,disabled:this.busy,onSelect:(i:number)=>{
              this.selectTab(i);
            },onCreate:()=>{
              this.dirty=false;
              this.openSheet('import');
            }
          }).margin({
            bottom:12
          });
        }
        else if(this.screen==='schedule'){
          this.schedule();
        }
        else if(this.screen==='courses'){
          this.coursePage();
        }
        else if(this.screen==='campus'){
          this.campus();
        }
        else if(this.screen==='recycle'){
          this.recycle();
        }
        else if(this.screen==='camera'){
          CameraCapture({
            onCapture:(path:string)=>{
              this.consume(path);
            },onCancel:()=>{
              this.screen='home';
            }
          });
        }
      }
      else{
        Column({
          space:18
        }){
          LoadingProgress().width(32).height(32);
          Text(this.message||'正在打开').fontColor(this.secondary());
        }.width('100%').height('100%').justifyContent(FlexAlign.Center);
      }
      if(this.busy&&!this.sheetOpen){
        Row({
          space:12
        }){
          LoadingProgress().width(22).height(22);
          Text(this.message||'正在处理').fontSize(13).fontColor(this.ink());
        }.padding(16).borderRadius(18).backgroundColor(this.card()).margin({
          bottom:110
        }).hitTestBehavior(HitTestMode.Block);
      }
      if(this.launch){
        Stack(){
          Row().width('100%').height('100%').backgroundColor(this.dark()?'#242522':'#FFFFFF');
          Column({
            space:20
          }){
            Image($r('app.media.screen_mark')).width(68).height(68);
            Text('截图成事').fontSize(25).fontWeight(FontWeight.Medium).fontColor(this.ink());
          }.opacity(this.launchOpacity).width('100%').height('100%').justifyContent(FlexAlign.Center);
        }.opacity(this.launchCover).width('100%').height('100%').hitTestBehavior(HitTestMode.Block);
      }
    }.height('100%').width('100%').backgroundColor(this.dark()?'#242522':'#F6F3E9').onAreaChange((_old:Area,area:Area)=>{
      if(!this.sheetOpen){
        this.baseHeight=Number(area.height);
      }
    }).bindSheet($$this.sheetOpen,this.sheet(),{
      detents:[Math.round(this.baseHeight*0.24),Math.round(this.baseHeight*0.56),Math.round(this.baseHeight*0.92)],detentSelection:this.sheetHeight,onDetentsDidChange:(height:number)=>{
        const value=this.getUIContext().px2vp(height);
        this.sheetHeight=[0.24,0.56,0.92].map((f:number)=>Math.round(this.baseHeight*f)).sort((a:number,b:number)=>Math.abs(a-value)-Math.abs(b-value))[0];
      },preferType:SheetType.BOTTOM,dragBar:true,showClose:false,backgroundColor:this.dark()?'#F52D302B':'#F5F9F7EF',maskColor:'#4420241E',radius:{
        topLeft:28,topRight:28
      },scrollSizeMode:ScrollSizeMode.CONTINUOUS,keyboardAvoidMode:deviceInfo.sdkApiVersion>=13?SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE:undefined,onWillDismiss:(action:DismissSheetAction)=>{
        if(!this.busy&&!this.dirty){
          action.dismiss();
        }
        else{
          this.closeSheet();
        }
      },onDisappear:()=>{
        this.dirty=false;
      }
    })
  }
}
