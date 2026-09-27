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
    this.context.clearRect(0, 0, 236, 236);
    const keys: string[] = ['w', 'd', 's', 'a'];
    for (let index: number = 0; index < keys.length; index++) {
      const centerAngle: number = (index - 1) * Math.PI / 2;
      const start: number = centerAngle - Math.PI / 4;
      const end: number = centerAngle + Math.PI / 4;
      this.context.beginPath();
      this.context.arc(118, 118, 115, start, end);
      this.context.arc(118, 118, 38, end, start, true);
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
    const dx: number = x - 118;
    const dy: number = y - 118;
    const radius: number = Math.sqrt(dx * dx + dy * dy);
    if (radius <= 35) { return 'stop'; }
    if (radius < 41 || radius > 112) { return ''; }
    if (Math.abs(Math.abs(dx) - Math.abs(dy)) / Math.SQRT2 <= 3) { return ''; }
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
  private Key(label: string, key: string) {
    Button(label)
      .width(88).height(48).fontSize(16).fontWeight(FontWeight.Bold)
      .fontColor(this.activeKey === key ? '#FFFFFF' : '#364B60')
      .backgroundColor(this.activeKey === key ? '#41BA41' : Color.Transparent)
      .borderRadius(24)
      .scale({ x: this.activeKey === key ? 0.95 : 1, y: this.activeKey === key ? 0.95 : 1 })
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pressShadow(this.activeKey === key ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE)
        .pointLight({ sourceType: this.activeKey === key ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
          options: { color: '#D7FFD8', intensity: 8, height: 110 } }).buildEffect())
      .enabled(this.connected)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.onStart(key); }
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.onEnd(key); }
      })
  }

  @Builder
  private Direction(label: string, key: string, x: number, y: number) {
    Text(label).width(24).height(24).textAlign(TextAlign.Center)
      .fontSize(18).fontWeight(FontWeight.Bold)
      .fontColor(this.activeKey === key ? '#FFFFFF' : '#364B60')
      .position({ x: x, y: y }).hitTestBehavior(HitTestMode.None)
  }

  build() {
    Column({ space: 0 }) {
      Row() {
        this.Key('Q', 'q')
        Blank()
        this.Key('E', 'e')
      }.width(280)

      Stack({ alignContent: Alignment.Center }) {
        Column().width(236).height(236).borderRadius(118)
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 12, color: '#162D714B', offsetY: 3 })
        Canvas(this.context).width(236).height(236)
          .onReady(() => this.drawPad())
          .onTouch((event: TouchEvent) => this.touchPad(event))
        this.Direction('W', 'w', 106, 21)
        this.Direction('A', 'a', 21, 106)
        this.Direction('D', 'd', 191, 106)
        this.Direction('S', 's', 106, 191)
        Button('STOP').width(70).height(70).fontSize(12).fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF').backgroundColor('#FF3B30').borderRadius(35)
          .shadow({ radius: 8, color: '#45C64343', offsetY: 3 })
          .position({ x: 83, y: 83 })
          .enabled(this.connected)
          .onTouch((event: TouchEvent) => {
            event.stopPropagation();
            if (event.type === TouchType.Down) { this.onStop(); }
          })
      }.width(236).height(236)

      Row() {
        this.Key('←', 'left')
        Blank()
        this.Key('→', 'right')
      }.width(280)
    }.width('100%')
  }
}
