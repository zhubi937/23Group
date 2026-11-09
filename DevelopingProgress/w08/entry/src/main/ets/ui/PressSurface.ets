@Component
export struct PressSurface {
  @BuilderParam content: () => void;
  @Prop reduceMotion: boolean = false;
  onActivate: () => void = () => {};
  @State private scaleValue: number = 1;
  private pressed(down: boolean): void {
    this.getUIContext().animateTo({duration:this.reduceMotion?0:down?75:150,curve:Curve.EaseOut},() => { this.scaleValue=down&&!this.reduceMotion?0.985:1; });
  }
  build() {
    Column() { this.content() }.width('100%').scale({x:this.scaleValue,y:this.scaleValue})
      .onTouch((event: TouchEvent) => { if (event.type===TouchType.Down) { this.pressed(true); } else if (event.type===TouchType.Up || event.type===TouchType.Cancel) { this.pressed(false); } })
      .onClick(this.onActivate)
  }
}
