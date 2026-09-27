import { hdsEffect } from '@kit.UIDesignKit';

@Component
export struct DriveControls {
  @Prop connected: boolean = false;
  @Prop @Watch('drawPad') activeKey: string = '';
  @Prop sliderSpeed: number = 40;
  onStart: (key: string) => void = () => {};
  onEnd: (key: string) => void = () => {};
  onStop: () => void = () => {};
  onSpeedChange: (value: number) => void = () => {};

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private trackingId: number = -1;
  private heldZone: string = '';
  private pendingZone: string = '';
  private switchTimer: number = -1;
  private rowWidth: number = 316;

  private drawPad(): void {
    const center: number = 92;
    const outer: number = 89;
    const inner: number = 33;
    const corner: number = 7;
    this.context.clearRect(0, 0, 184, 184);
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

  private discZoneAt(x: number, y: number): string {
    const dx: number = x - 92;
    const dy: number = y - 92;
    const radius: number = Math.sqrt(dx * dx + dy * dy);
    if (radius <= 30) { return 'stop'; }
    if (radius < 36 || radius > 86) { return ''; }
    if (Math.abs(Math.abs(dx) - Math.abs(dy)) / Math.SQRT2 <= 5) { return ''; }
    if (Math.abs(dx) > Math.abs(dy)) { return dx > 0 ? 'd' : 'a'; }
    return dy > 0 ? 's' : 'w';
  }

  private zoneAt(x: number, y: number): string {
    const gap: number = Math.max(0, (this.rowWidth - 284) / 4);
    const discLeft: number = gap * 2 + 50;
    const rightLeft: number = discLeft + 184 + gap;
    if (x >= gap && x <= gap + 50) {
      if (y >= 19 && y <= 91) { return 'q'; }
      if (y >= 109 && y <= 181) { return 'left'; }
      return '';
    }
    if (x >= rightLeft && x <= rightLeft + 50) {
      if (y >= 19 && y <= 91) { return 'e'; }
      if (y >= 109 && y <= 181) { return 'right'; }
      return '';
    }
    if (x < discLeft || x > discLeft + 184 || y < 8 || y > 192) { return ''; }
    return this.discZoneAt(x - discLeft, y - 8);
  }

  private clearPending(): void {
    if (this.switchTimer >= 0) { clearTimeout(this.switchTimer); this.switchTimer = -1; }
    this.pendingZone = '';
  }

  private touchPad(event: TouchEvent): void {
    if (event.changedTouches.length === 0) { return; }
    if (!this.connected) {
      this.clearPending();
      this.heldZone = '';
      this.trackingId = -1;
      return;
    }
    const point: TouchObject = event.changedTouches[0];
    if (event.type === TouchType.Down) {
      if (this.trackingId >= 0) { return; }
      this.trackingId = point.id;
    } else if (point.id !== this.trackingId) {
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.clearPending();
      if (this.heldZone.length > 0 && this.heldZone !== 'stop') { this.onEnd(this.heldZone); }
      this.heldZone = '';
      this.trackingId = -1;
      return;
    }
    const next: string = this.zoneAt(point.x, point.y);
    if (next === this.heldZone) { this.clearPending(); return; }
    if (this.heldZone.length > 0 && this.heldZone !== 'stop') { this.onEnd(this.heldZone); }
    this.heldZone = '';
    if (next === 'stop') {
      this.clearPending();
      this.heldZone = 'stop';
      this.onStop();
      return;
    }
    if (next.length === 0) { this.clearPending(); return; }
    if (event.type === TouchType.Down) {
      this.clearPending();
      this.heldZone = next;
      this.onStart(next);
      return;
    }
    if (this.pendingZone === next) { return; }
    this.clearPending();
    this.pendingZone = next;
    const fingerId: number = this.trackingId;
    this.switchTimer = setTimeout(() => {
      this.switchTimer = -1;
      if (this.connected && this.trackingId === fingerId && this.pendingZone === next && !this.heldZone) {
        this.pendingZone = '';
        this.heldZone = next;
        this.onStart(next);
      }
    }, 120);
  }

  @Builder
  private SideKey(label: string, key: string) {
    Column() {
      Text(label).fontSize(11).fontWeight(FontWeight.Bold)
        .fontColor(this.activeKey === key ? '#FFFFFF' : '#364B60')
        .textAlign(TextAlign.Center).maxLines(2).width(48)
    }
      .width(50).height(72).justifyContent(FlexAlign.Center)
      .backgroundColor(this.activeKey === key ? '#41BA41' : '#F8FBFF')
      .border({ width: 1, color: this.activeKey === key ? '#41BA41' : '#D9E5F0' })
      .borderRadius(18)
      .scale({ x: this.activeKey === key ? 0.95 : 1, y: this.activeKey === key ? 0.95 : 1 })
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pressShadow(this.activeKey === key ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE)
        .pointLight({ sourceType: this.activeKey === key ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
          options: { color: '#D7FFD8', intensity: 8, height: 110 } }).buildEffect())
  }

  @Builder
  private Direction(label: string, key: string, x: number, y: number) {
    Text(label).width(48).height(24).textAlign(TextAlign.Center)
      .fontSize(12).fontWeight(FontWeight.Bold)
      .fontColor(this.activeKey === key ? '#FFFFFF' : '#364B60')
      .position({ x: x, y: y }).hitTestBehavior(HitTestMode.None)
  }

  build() {
    Column({ space: 4 }) {
      Row() {
        Column() {
          this.SideKey('左旋转', 'q')
          this.SideKey('左平移', 'left')
        }.width(50).height(200).justifyContent(FlexAlign.SpaceEvenly)
          .hitTestBehavior(HitTestMode.None)
        Stack({ alignContent: Alignment.Center }) {
          Column().width(184).height(184).borderRadius(92)
            .backgroundColor('#FFFFFF')
            .shadow({ radius: 10, color: '#162D714B', offsetY: 3 })
          Canvas(this.context).width(184).height(184)
            .onReady(() => this.drawPad())
          this.Direction('前进', 'w', 68, 16)
          this.Direction('左转', 'a', 6, 80)
          this.Direction('右转', 'd', 130, 80)
          this.Direction('后退', 's', 68, 144)
          Button('停车').width(60).height(60).fontSize(12).fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF').backgroundColor('#FF3B30').borderRadius(30)
            .shadow({ radius: 8, color: '#45C64343', offsetY: 3 })
            .position({ x: 62, y: 62 })
        }.width(184).height(184).hitTestBehavior(HitTestMode.None)
        Column() {
          this.SideKey('右旋转', 'e')
          this.SideKey('右平移', 'right')
        }.width(50).height(200).justifyContent(FlexAlign.SpaceEvenly)
          .hitTestBehavior(HitTestMode.None)
      }.width('100%').height(200).justifyContent(FlexAlign.SpaceEvenly)
        .onAreaChange((oldValue: Area, newValue: Area) => {
          const width: number = Number(newValue.width);
          if (Number.isFinite(width) && width > 0) { this.rowWidth = width; }
        })
        .onTouch((event: TouchEvent) => this.touchPad(event))
      Row({ space: 8 }) {
        Text(`速度 ${this.sliderSpeed}`).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#364B60')
        Slider({ value: this.sliderSpeed, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
          .layoutWeight(1).selectedColor('#41BA41')
          .enabled(this.connected).onChange((value: number) => this.onSpeedChange(value))
      }.width('100%').height(39).padding({ left: 14, right: 14 })
    }.width('100%').padding({ bottom: 8 })
      .backgroundColor('#EAF1F8').borderRadius(22)
  }
}
