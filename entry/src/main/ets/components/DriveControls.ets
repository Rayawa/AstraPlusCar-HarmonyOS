import { hdsEffect } from '@kit.UIDesignKit';

@Component
export struct DriveControls {
  @Prop connected: boolean = false;
  @Prop @Watch('drawPad') activeKey: string = '';
  onStart: (key: string) => void = () => {};
  onEnd: (key: string) => void = () => {};
  onStop: () => void = () => {};

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private trackingId: number = -1;
  private heldZone: string = '';

  private drawPad(): void {
    const center: number = 104;
    const outer: number = 101;
    const inner: number = 38;
    const corner: number = 8;
    this.context.clearRect(0, 0, 208, 208);
    const keys: string[] = ['w', 'd', 's', 'a'];
    for (let index: number = 0; index < keys.length; index++) {
      const centerAngle: number = (index - 1) * Math.PI / 2;
      const start: number = centerAngle - Math.PI / 4;
      const end: number = centerAngle + Math.PI / 4;
      const outerStart: number = start + corner / outer;
      const outerEnd: number = end - corner / outer;
      const innerStart: number = start + corner / inner;
      const innerEnd: number = end - corner / inner;
      this.context.beginPath();
      this.context.moveTo(center + outer * Math.cos(outerStart), center + outer * Math.sin(outerStart));
      this.context.arc(center, center, outer, outerStart, outerEnd);
      this.context.quadraticCurveTo(center + outer * Math.cos(end), center + outer * Math.sin(end),
        center + (outer - corner) * Math.cos(end), center + (outer - corner) * Math.sin(end));
      this.context.lineTo(center + (inner + corner) * Math.cos(end),
        center + (inner + corner) * Math.sin(end));
      this.context.quadraticCurveTo(center + inner * Math.cos(end), center + inner * Math.sin(end),
        center + inner * Math.cos(innerEnd), center + inner * Math.sin(innerEnd));
      this.context.arc(center, center, inner, innerEnd, innerStart, true);
      this.context.quadraticCurveTo(center + inner * Math.cos(start), center + inner * Math.sin(start),
        center + (inner + corner) * Math.cos(start), center + (inner + corner) * Math.sin(start));
      this.context.lineTo(center + (outer - corner) * Math.cos(start),
        center + (outer - corner) * Math.sin(start));
      this.context.quadraticCurveTo(center + outer * Math.cos(start), center + outer * Math.sin(start),
        center + outer * Math.cos(outerStart), center + outer * Math.sin(outerStart));
      this.context.closePath();
      this.context.fillStyle = this.activeKey === keys[index] ? '#41BA41' : '#E4EDF5';
      this.context.fill();
      this.context.strokeStyle = '#FFFFFF';
      this.context.lineWidth = 6;
      this.context.lineJoin = 'round';
      this.context.stroke();
    }
  }

  private zoneAt(x: number, y: number): string {
    const dx: number = x - 104;
    const dy: number = y - 104;
    const radius: number = Math.sqrt(dx * dx + dy * dy);
    if (radius <= 35) { return 'stop'; }
    if (radius < 41 || radius > 98) { return ''; }
    if (Math.abs(Math.abs(dx) - Math.abs(dy)) / Math.SQRT2 <= 5) { return ''; }
    if (Math.abs(dx) > Math.abs(dy)) { return dx > 0 ? 'd' : 'a'; }
    return dy > 0 ? 's' : 'w';
  }

  private touchPad(event: TouchEvent): void {
    if (!this.connected || event.changedTouches.length === 0) { return; }
    const point: TouchObject = event.changedTouches[0];
    if (event.type === TouchType.Down) {
      if (this.trackingId >= 0) { return; }
      this.trackingId = point.id;
    } else if (point.id !== this.trackingId) {
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.heldZone.length > 0 && this.heldZone !== 'stop') { this.onEnd(this.heldZone); }
      this.heldZone = '';
      this.trackingId = -1;
      return;
    }
    const next: string = this.zoneAt(point.x, point.y);
    if (next === this.heldZone) { return; }
    if (this.heldZone.length > 0 && this.heldZone !== 'stop') { this.onEnd(this.heldZone); }
    this.heldZone = next;
    if (next === 'stop') { this.onStop(); }
    else if (next.length > 0) { this.onStart(next); }
  }

  @Builder
  private SideKey(label: string, key: string) {
    Column() {
      Text(label).fontSize(12).fontWeight(FontWeight.Bold)
        .fontColor(this.activeKey === key ? '#FFFFFF' : '#364B60')
        .textAlign(TextAlign.Center).maxLines(2).width(52)
    }
      .width(54).height(82).justifyContent(FlexAlign.Center)
      .backgroundColor(this.activeKey === key ? '#41BA41' : Color.Transparent)
      .borderRadius(20)
      .scale({ x: this.activeKey === key ? 0.95 : 1, y: this.activeKey === key ? 0.95 : 1 })
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pressShadow(this.activeKey === key ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE)
        .pointLight({ sourceType: this.activeKey === key ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
          options: { color: '#D7FFD8', intensity: 8, height: 110 } }).buildEffect())
      .onTouch((event: TouchEvent) => {
        if (!this.connected) { return; }
        if (event.type === TouchType.Down) { this.onStart(key); }
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.onEnd(key); }
      })
  }

  @Builder
  private Direction(label: string, key: string, x: number, y: number) {
    Text(label).width(52).height(26).textAlign(TextAlign.Center)
      .fontSize(13).fontWeight(FontWeight.Bold)
      .fontColor(this.activeKey === key ? '#FFFFFF' : '#364B60')
      .position({ x: x, y: y }).hitTestBehavior(HitTestMode.None)
  }

  build() {
    Row() {
      Column({ space: 10 }) {
        this.SideKey('左旋转', 'q')
        this.SideKey('左平移', 'left')
      }.width(54).height(208).justifyContent(FlexAlign.Center)
      Stack({ alignContent: Alignment.Center }) {
        Column().width(208).height(208).borderRadius(104)
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 12, color: '#162D714B', offsetY: 3 })
        Canvas(this.context).width(208).height(208)
          .onReady(() => this.drawPad())
          .onTouch((event: TouchEvent) => this.touchPad(event))
        this.Direction('前进', 'w', 78, 17)
        this.Direction('左转', 'a', 4, 91)
        this.Direction('右转', 'd', 152, 91)
        this.Direction('后退', 's', 78, 165)
        Button('停车').width(70).height(70).fontSize(13).fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF').backgroundColor('#FF3B30').borderRadius(35)
          .shadow({ radius: 8, color: '#45C64343', offsetY: 3 })
          .position({ x: 69, y: 69 })
          .enabled(this.connected)
          .onTouch((event: TouchEvent) => {
            event.stopPropagation();
            if (event.type === TouchType.Down) { this.onStop(); }
          })
      }.width(208).height(208)
      Column({ space: 10 }) {
        this.SideKey('右旋转', 'e')
        this.SideKey('右平移', 'right')
      }.width(54).height(208).justifyContent(FlexAlign.Center)
    }.width('100%').height(220).justifyContent(FlexAlign.Center)
      .backgroundColor('#EAF1F8').borderRadius(22)
  }
}
