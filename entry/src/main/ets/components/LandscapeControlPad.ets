import { PathShape } from '@kit.ArkUI';

/** A scaled version of the portrait circular control, drawn over the camera feed. */
@Component
export struct LandscapeControlPad {
  @Prop padDiameter: number = 180;
  @Prop drive: boolean = true;
  @Prop activeKey: string = '';
  @Prop captureBusy: boolean = false;
  onStart: (key: string) => void = () => {};
  onEnd: (key: string) => void = () => {};
  onStop: () => void = () => {};
  onCapture: () => void = () => {};

  @State private touchingKey: string = '';
  private trackingId: number = -1;
  private heldZone: string = '';
  private pendingZone: string = '';
  private switchTimer: number = -1;

  aboutToDisappear(): void {
    this.clearPending();
    if (this.heldZone.length > 0 && this.heldZone !== 'center') { this.onEnd(this.heldZone); }
    this.heldZone = '';
    this.trackingId = -1;
  }

  private px(value: number): string { return this.getUIContext().vp2px(value).toFixed(2); }

  private point(radius: number, angle: number): string {
    const center: number = this.padDiameter / 2;
    return `${this.px(center + radius * Math.cos(angle))} ${this.px(center + radius * Math.sin(angle))}`;
  }

  private sectorPath(index: number): string {
    const outer: number = this.padDiameter / 2 - 4;
    const inner: number = this.padDiameter * 0.18;
    const corner: number = this.padDiameter * 0.028;
    const mid: number = (index - 1) * Math.PI / 2;
    const start: number = mid - Math.PI / 4;
    const end: number = mid + Math.PI / 4;
    const os: number = start + corner / outer;
    const oe: number = end - corner / outer;
    return `M ${this.point(outer, os)} A ${this.px(outer)} ${this.px(outer)} 0 0 1 ${this.point(outer, oe)} ` +
      `Q ${this.point(outer, end)} ${this.point(outer - corner, end)} ` +
      `L ${this.point(inner, end)} ` +
      `A ${this.px(inner)} ${this.px(inner)} 0 0 0 ${this.point(inner, start)} ` +
      `L ${this.point(outer - corner, start)} Q ${this.point(outer, start)} ${this.point(outer, os)} Z`;
  }

  private zoneAt(x: number, y: number): string {
    const dx: number = x - this.padDiameter / 2;
    const dy: number = y - this.padDiameter / 2;
    const radius: number = Math.sqrt(dx * dx + dy * dy);
    if (radius <= this.padDiameter * 0.165) { return 'center'; }
    if (radius < this.padDiameter * 0.195 || radius > this.padDiameter / 2 - 5) { return ''; }
    if (Math.abs(Math.abs(dx) - Math.abs(dy)) / Math.SQRT2 <= this.padDiameter * 0.022) { return ''; }
    if (Math.abs(dx) > Math.abs(dy)) {
      return dx < 0 ? (this.drive ? 'a' : 'left') : (this.drive ? 'd' : 'right');
    }
    return dy < 0 ? (this.drive ? 'w' : 'q') : (this.drive ? 's' : 'e');
  }

  private clearPending(): void {
    if (this.switchTimer >= 0) { clearTimeout(this.switchTimer); this.switchTimer = -1; }
    this.pendingZone = '';
  }

  private enterZone(next: string, fromDown: boolean): void {
    this.heldZone = next;
    this.touchingKey = next;
    if (next === 'center') {
      if (this.drive) { this.onStop(); }
      else if (fromDown && !this.captureBusy) { this.onCapture(); }
    } else {
      this.onStart(next);
    }
  }

  private touchPad(event: TouchEvent): void {
    if (event.changedTouches.length === 0) { return; }
    const point: TouchObject = event.changedTouches[0];
    if (event.type === TouchType.Down) {
      if (this.trackingId >= 0) { return; }
      this.trackingId = point.id;
    } else if (point.id !== this.trackingId) { return; }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.clearPending();
      if (this.heldZone.length > 0 && this.heldZone !== 'center') { this.onEnd(this.heldZone); }
      this.heldZone = '';
      this.touchingKey = '';
      this.trackingId = -1;
      return;
    }
    const next: string = this.zoneAt(point.x, point.y);
    if (next === this.heldZone) { this.clearPending(); return; }
    if (this.heldZone.length > 0 && this.heldZone !== 'center') { this.onEnd(this.heldZone); }
    this.heldZone = '';
    this.touchingKey = '';
    if (next.length === 0) { this.clearPending(); return; }
    if (event.type === TouchType.Down || (this.drive && next === 'center')) {
      this.clearPending();
      this.enterZone(next, event.type === TouchType.Down);
      return;
    }
    if (this.pendingZone === next) { return; }
    this.clearPending();
    this.pendingZone = next;
    const fingerId: number = this.trackingId;
    this.switchTimer = setTimeout(() => {
      this.switchTimer = -1;
      if (this.trackingId === fingerId && this.pendingZone === next && !this.heldZone) {
        this.pendingZone = '';
        this.enterZone(next, false);
      }
    }, 120);
  }

  @Builder
  private DirectionLabel(label: string, x: number, y: number, width: number) {
    Text(label)
      .width(width).height(24)
      .textAlign(TextAlign.Center).fontSize(this.drive ? 13 : 10)
      .fontWeight(FontWeight.Bold).fontColor(Color.White)
      .position({ x: x, y: y }).hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      ForEach([0, 1, 2, 3], (index: number) => {
        Stack() {
          Column().width(this.padDiameter).height(this.padDiameter)
            .backgroundColor(this.touchingKey === (this.drive ? ['w', 'd', 's', 'a'][index] :
              ['q', 'right', 'e', 'left'][index]) || this.activeKey === (this.drive ?
              ['w', 'd', 's', 'a'][index] : ['q', 'right', 'e', 'left'][index]) ?
              '#B862E6A7' : '#880B1B28')
            .clipShape(new PathShape({ commands: this.sectorPath(index) }))
          Path({ width: this.padDiameter, height: this.padDiameter, commands: this.sectorPath(index) })
            .fill(Color.Transparent).stroke('#AAFFFFFF').strokeWidth(1.4)
            .width(this.padDiameter).height(this.padDiameter)
        }.width(this.padDiameter).height(this.padDiameter).hitTestBehavior(HitTestMode.None)
      }, (index: number) => index.toString())
      this.DirectionLabel(this.drive ? '前进 W' : '左旋转', this.padDiameter * 0.29,
        this.padDiameter * 0.10, this.padDiameter * 0.42)
      this.DirectionLabel(this.drive ? '左转 A' : '左平移', 0,
        this.padDiameter * 0.43, this.padDiameter * 0.34)
      this.DirectionLabel(this.drive ? '右转 D' : '右平移', this.padDiameter * 0.66,
        this.padDiameter * 0.43, this.padDiameter * 0.34)
      this.DirectionLabel(this.drive ? '后退 S' : '右旋转', this.padDiameter * 0.29,
        this.padDiameter * 0.75, this.padDiameter * 0.42)
      Column().width(this.padDiameter * 0.34).height(this.padDiameter * 0.34)
        .backgroundColor(this.drive ? '#D9D94040' : '#C70A84FF')
        .borderRadius(this.padDiameter * 0.17)
        .border({ width: 1.5, color: '#E8FFFFFF' })
        .hitTestBehavior(HitTestMode.None)
      Text(this.drive ? '停车\nSTOP' : (this.captureBusy ? '保存中' : '截图'))
        .textAlign(TextAlign.Center).fontSize(this.drive ? 10 : 11).fontWeight(FontWeight.Bold)
        .fontColor(Color.White).hitTestBehavior(HitTestMode.None)
    }
    .width(this.padDiameter).height(this.padDiameter)
    .onTouch((event: TouchEvent) => this.touchPad(event))
  }
}
