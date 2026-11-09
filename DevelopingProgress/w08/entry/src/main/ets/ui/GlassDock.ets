import { ThemePalette, themeById } from './Appearance';
import { clampPage, dockDestination } from './Motion';
import { glassMaterial } from './GlassMaterial';

@Component
export struct GlassDock {
  @Link progress: number;
  @Prop selected: number = 0;
  @Prop palette: ThemePalette = themeById('morandi-blue');
  @Prop clearGlass: boolean = false;
  @Prop reduceMotion: boolean = false;
  @Prop disabled: boolean = false;
  onSelect: (index: number) => void = () => {};
  onCreate: () => void = () => {};
  @State railWidth: number = 240;
  @State dragging: boolean = false;
  private dragStart: number = 0;
  private startPage: number = 0;
  private icon(index: number): Resource {
    return index===0?$r('app.media.ui_home'):index===1?$r('app.media.ui_sources'):$r('app.media.ui_appearance');
  }
  build() {
    Row({space:12}) {
      Stack({alignContent:Alignment.Start}) {
        Row().width((this.railWidth-12)/3).height(54).borderRadius(27)
          .linearGradient({angle:145,colors:[['#D9FFFFFF',0],['#44FFFFFF',0.46],['#92FFFFFF',1]]})
          .border({width:1,color:'#E8FFFFFF'}).shadow({radius:6,offsetY:2,color:'#10243B4C'})
          .translate({x:6+clampPage(this.progress)*(this.railWidth-12)/3})
          .scale({x:this.dragging?1.03:1,y:this.dragging?1.06:1}).hitTestBehavior(HitTestMode.None)
        Row() {
          ForEach(['事项','来源','外观'],(label: string,index: number) => {
            Column({space:3}) {
              Image(this.icon(index)).width(20).height(20).draggable(false)
              Text(label).fontSize(10).fontWeight(this.selected===index?FontWeight.Medium:FontWeight.Normal).fontColor(this.selected===index?this.palette.accent:'#526274')
            }.layoutWeight(1).height(54).justifyContent(FlexAlign.Center).borderRadius(27)
              .onClick(() => { if (!this.disabled) { this.onSelect(index); } }).id('tab-'+index).accessibilityText(label)
          })
        }.width('100%').padding(6)
      }.layoutWeight(1).height(66).borderRadius(33)
        .backgroundEffect({radius:this.clearGlass?0:26,saturation:1.35,brightness:1.06,color:this.clearGlass?'#F8FAFC':'#18FFFFFF'})
        .linearGradient({angle:120,colors:[['#4DFFFFFF',0],['#0AFFFFFF',0.48],['#38FFFFFF',1]]})
        .border({width:1,color:'#BFFFFFFF'}).shadow({radius:22,offsetY:8,color:'#182E4156'})
        .systemMaterial(glassMaterial(this.clearGlass))
        .onAreaChange((_before: Area,after: Area) => { this.railWidth=Number(after.width); })
        .gesture(PanGesture({direction:PanDirection.Horizontal,distance:8})
          .onActionStart(() => { this.dragStart=this.progress; this.startPage=this.selected; this.dragging=true; })
          .onActionUpdate((event: GestureEvent) => { if (!this.disabled) { this.progress=clampPage(this.dragStart+event.offsetX/((this.railWidth-12)/3)); } })
          .onActionEnd((event: GestureEvent) => { this.dragging=false; if (!this.disabled) { this.onSelect(dockDestination(this.progress,this.startPage,event.velocityX)); } })
          .onActionCancel(() => { this.dragging=false; this.onSelect(this.selected); }))
      Button() { Image($r('app.media.ui_plus')).width(24).height(24).draggable(false) }
        .width(62).height(62).borderRadius(31).backgroundColor(this.clearGlass?'#FFFFFF':'#30FFFFFF')
        .backgroundEffect({radius:this.clearGlass?0:22,saturation:1.3,color:this.clearGlass?'#FFFFFF':'#10FFFFFF'})
        .linearGradient({angle:140,colors:[['#B0FFFFFF',0],['#15FFFFFF',0.6],['#70FFFFFF',1]]})
        .border({width:1,color:'#E8FFFFFF'}).shadow({radius:18,offsetY:6,color:'#182E4156'})
        .systemMaterial(glassMaterial(this.clearGlass)).stateEffect(true).enabled(!this.disabled)
        .onClick(this.onCreate).id('dock-create').accessibilityText('添加截图或事项')
    }.width('100%').constraintSize({maxWidth:480}).padding({left:22,right:22}).height(82)
  }
}
