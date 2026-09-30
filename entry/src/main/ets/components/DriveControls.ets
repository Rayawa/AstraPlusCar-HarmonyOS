import { hdsEffect } from '@kit.UIDesignKit';
import { PathShape } from '@kit.ArkUI';
import { Haptics } from '../services/Haptics';

/** The visible control shapes and the hit zones share the same geometry. */
@Component
export struct DriveControls {
  @Prop connected: boolean = false;
  @Prop activeKey: string = '';
  @Prop sliderSpeed: number = 40;
  @State private touchingKey: string = '';
  @State private rowWidth: number = 352;
  canStart: (key: string) => boolean = () => true;
  onStart: (key: string) => void = () => {};
  onEnd: (key: string) => void = () => {};
  onCapture: () => void = () => {};
  onSpeedChange: (value: number) => void = () => {};
  onUnavailable: () => void = () => {};

  private trackingId: number = -1;
  private heldZone: string = '';
  private pendingZone: string = '';
  private switchTimer: number = -1;
  private lastSliderVibration: number = 0;

  private point(radius: number, angle: number): string {
    return `${this.px(118 + radius * Math.cos(angle))} ${this.px(118 + radius * Math.sin(angle))}`;
  }

  private px(value: number): string { return this.getUIContext().vp2px(value).toFixed(2); }

  private sectorPath(index: number): string {
    const outer: number = 113;
    const inner: number = 40;
    const corner: number = 7;
    const mid: number = (index - 1) * Math.PI / 2;
    const start: number = mid - Math.PI / 4;
    const end: number = mid + Math.PI / 4;
    const os: number = start + corner / outer;
    const oe: number = end - corner / outer;
    const is: number = start + corner / inner;
    const ie: number = end - corner / inner;
    return `M ${this.point(outer, os)} A ${this.px(outer)} ${this.px(outer)} 0 0 1 ${this.point(outer, oe)} ` +
      `Q ${this.point(outer, end)} ${this.point(outer - corner, end)} ` +
      `L ${this.point(inner + corner, end)} Q ${this.point(inner, end)} ${this.point(inner, ie)} ` +
      `A ${this.px(inner)} ${this.px(inner)} 0 0 0 ${this.point(inner, is)} ` +
      `Q ${this.point(inner, start)} ${this.point(inner + corner, start)} ` +
      `L ${this.point(outer - corner, start)} Q ${this.point(outer, start)} ${this.point(outer, os)} Z`;
  }

  private cornerPath(key: string): string {
    const center: number = this.rowWidth / 2;
    const radius: number = 126;
    const topX: number = center - Math.sqrt(radius * radius - 114 * 114);
    const sideX: number = center - Math.sqrt(radius * radius - 12 * 12);
    const rightTop: number = this.rowWidth - topX;
    const rightSide: number = this.rowWidth - sideX;
    const far: number = this.rowWidth - 8;
    const p = (value: number): string => this.px(value);
    const arc: string = `${p(126)} ${p(126)}`;
    if (key === 'q') {
      return `M ${p(18)} ${p(8)} L ${p(topX)} ${p(8)} A ${arc} 0 0 0 ${p(sideX)} ${p(110)} ` +
        `L ${p(8)} ${p(110)} L ${p(8)} ${p(18)} Q ${p(8)} ${p(8)} ${p(18)} ${p(8)} Z`;
    }
    if (key === 'e') {
      return `M ${p(rightTop)} ${p(8)} L ${p(far - 10)} ${p(8)} ` +
        `Q ${p(far)} ${p(8)} ${p(far)} ${p(18)} L ${p(far)} ${p(110)} ` +
        `L ${p(rightSide)} ${p(110)} A ${arc} 0 0 0 ${p(rightTop)} ${p(8)} Z`;
    }
    if (key === 'left') {
      return `M ${p(8)} ${p(134)} L ${p(sideX)} ${p(134)} A ${arc} 0 0 0 ${p(topX)} ${p(236)} ` +
        `L ${p(18)} ${p(236)} Q ${p(8)} ${p(236)} ${p(8)} ${p(226)} Z`;
    }
    return `M ${p(rightSide)} ${p(134)} L ${p(far)} ${p(134)} L ${p(far)} ${p(226)} ` +
      `Q ${p(far)} ${p(236)} ${p(far - 10)} ${p(236)} L ${p(rightTop)} ${p(236)} ` +
      `A ${arc} 0 0 0 ${p(rightSide)} ${p(134)} Z`;
  }

  private zoneAt(x: number, y: number): string {
    const dx: number = x - this.rowWidth / 2;
    const dy: number = y - 122;
    const radius: number = Math.sqrt(dx * dx + dy * dy);
    if (radius <= 35) { return 'capture'; }
    if (radius >= 44 && radius <= 113) {
      if (Math.abs(Math.abs(dx) - Math.abs(dy)) / Math.SQRT2 <= 5) { return ''; }
      if (Math.abs(dx) > Math.abs(dy)) { return dx > 0 ? 'd' : 'a'; }
      return dy > 0 ? 's' : 'w';
    }
    if (x < 8 || x > this.rowWidth - 8 || y < 8 || y > 236 || radius < 126) { return ''; }
    if (y <= 110) { return dx < 0 ? 'q' : 'e'; }
    if (y >= 134) { return dx < 0 ? 'left' : 'right'; }
    return '';
  }

  private clearPending(): void {
    if (this.switchTimer >= 0) { clearTimeout(this.switchTimer); this.switchTimer = -1; }
    this.pendingZone = '';
  }

  private enterZone(next: string): void {
    if (this.connected && !this.canStart(next)) { return; }
    this.heldZone = next;
    this.touchingKey = next;
    Haptics.soft();
    if (!this.connected) { this.onUnavailable(); return; }
    if (next === 'capture') { this.onCapture(); } else { this.onStart(next); }
  }

  private releaseTouch(): void {
    this.clearPending();
    if (this.connected && this.heldZone.length > 0 && this.heldZone !== 'capture') {
      this.onEnd(this.heldZone);
    }
    this.heldZone = '';
    this.touchingKey = '';
    this.trackingId = -1;
  }

  private touchPad(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) { this.releaseTouch(); return; }
    if (event.changedTouches.length === 0) { return; }
    let point: TouchObject = event.changedTouches[0];
    if (event.type === TouchType.Down) {
      if (this.trackingId >= 0) { return; }
      this.trackingId = point.id;
    } else {
      let found: boolean = false;
      for (const changed of event.changedTouches) {
        if (changed.id === this.trackingId) { point = changed; found = true; break; }
      }
      if (!found) { return; }
    }
    if (event.type === TouchType.Up) { this.releaseTouch(); return; }
    const next: string = this.zoneAt(point.x, point.y);
    if (next === this.heldZone) { this.clearPending(); return; }
    if (this.connected && this.heldZone.length > 0 && this.heldZone !== 'capture') { this.onEnd(this.heldZone); }
    this.heldZone = '';
    this.touchingKey = '';
    if (next.length === 0) { this.clearPending(); return; }
    if (event.type === TouchType.Down || next === 'capture') {
      this.clearPending();
      this.enterZone(next);
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
        this.enterZone(next);
      }
    }, 120);
  }

  @Builder
  private OuterKey(label: string, key: string, x: number, y: number) {
    // HDS light uses a component's rectangular bounds; clip the fill and light only the label.
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width(this.rowWidth).height(244)
        .backgroundColor(this.touchingKey === key || this.activeKey === key ?
          $r('app.color.accent_green') : $r('app.color.control_side'))
        .clipShape(new PathShape({ commands: this.cornerPath(key) }))
        .hitTestBehavior(HitTestMode.None)
      Path({ width: this.rowWidth, height: 244, commands: this.cornerPath(key) })
        .fill(Color.Transparent)
        .stroke(this.touchingKey === key ? '#D7FFD8' : $r('app.color.control_border')).strokeWidth(1.5)
        .width('100%').height(244).hitTestBehavior(HitTestMode.None)
      Text(label).width(48).height(24).textAlign(TextAlign.Center)
        .fontSize(10).fontWeight(FontWeight.Bold).maxLines(1)
        .fontColor(this.touchingKey === key || this.activeKey === key ?
          $r('app.color.white') : $r('app.color.text_control'))
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({ sourceType: this.touchingKey === key ? hdsEffect.PointLightSourceType.BRIGHT :
            hdsEffect.PointLightSourceType.NONE,
            illuminatedType: hdsEffect.PointLightIlluminatedType.CONTENT,
            options: { color: '#FFFFFF', intensity: 5, height: 60 } }).buildEffect())
        .position({ x: x, y: y }).hitTestBehavior(HitTestMode.None)
    }.width('100%').height(244).hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private Direction(label: string, key: string, x: number, y: number) {
    Text(label).width(58).height(26).textAlign(TextAlign.Center)
      .fontSize(12).fontWeight(FontWeight.Bold)
      .fontColor(this.touchingKey === key || this.activeKey === key ?
        $r('app.color.white') : $r('app.color.text_control'))
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pointLight({ sourceType: this.touchingKey === key ? hdsEffect.PointLightSourceType.BRIGHT :
          hdsEffect.PointLightSourceType.NONE,
          illuminatedType: hdsEffect.PointLightIlluminatedType.CONTENT,
          options: { color: '#FFFFFF', intensity: 5, height: 60 } }).buildEffect())
      .position({ x: x, y: y }).hitTestBehavior(HitTestMode.None)
  }

  build() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        this.OuterKey('左旋转', 'q', 12, 31)
        this.OuterKey('右旋转', 'e', this.rowWidth - 76, 31)
        this.OuterKey('左平移', 'left', 12, 189)
        this.OuterKey('右平移', 'right', this.rowWidth - 76, 189)
        Stack({ alignContent: Alignment.Center }) {
          Column().width(236).height(236).borderRadius(118)
            .backgroundColor($r('app.color.control_separator'))
            .shadow({ radius: 9, color: '#162D714B', offsetY: 3 })
          ForEach([0, 1, 2, 3], (index: number) => {
            Stack() {
              Column().width(236).height(236)
                .backgroundColor(this.touchingKey === ['w', 'd', 's', 'a'][index] ||
                  this.activeKey === ['w', 'd', 's', 'a'][index] ?
                  $r('app.color.accent_green') : $r('app.color.control_idle'))
                .clipShape(new PathShape({ commands: this.sectorPath(index) }))
              Path({ width: 236, height: 236, commands: this.sectorPath(index) })
                .fill(Color.Transparent)
                .stroke($r('app.color.control_separator')).strokeWidth(6)
                .width(236).height(236)
              Path({ width: 236, height: 236, commands: this.sectorPath(index) })
                .fill(Color.Transparent)
                .stroke(this.touchingKey === ['w', 'd', 's', 'a'][index] ? '#D7FFD8' :
                  $r('app.color.control_border')).strokeWidth(1.5)
                .width(236).height(236)
            }.width(236).height(236).hitTestBehavior(HitTestMode.None)
          }, (index: number) => index.toString())
          this.Direction('前进', 'w', 89, 21)
          this.Direction('左转', 'a', 7, 104)
          this.Direction('右转', 'd', 171, 104)
          this.Direction('后退', 's', 89, 188)
          Stack({ alignContent: Alignment.Center }) {
            Column().width(76).height(76).borderRadius(38)
              .backgroundColor($r('app.color.control_separator'))
            Column().width(64).height(64).borderRadius(32)
              .backgroundColor($r('app.color.accent_green'))
              .border({ width: 1.5, color: $r('app.color.control_border') })
              .shadow({ radius: this.touchingKey === 'capture' ? 12 : 0,
                color: '#6662E6A7', offsetY: 2 })
            Text('截图').fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.white'))
          }.width(76).height(76)
            .scale({ x: this.touchingKey === 'capture' ? 0.94 : 1,
              y: this.touchingKey === 'capture' ? 0.94 : 1 })
        }.width(236).height(236).hitTestBehavior(HitTestMode.None)
      }.width('100%').height(244)
        .onAreaChange((oldValue: Area, newValue: Area) => {
          const width: number = Number(newValue.width);
          if (Number.isFinite(width) && width > 0 && Math.abs(this.rowWidth - width) > 1) { this.rowWidth = width; }
        })
        .onTouch((event: TouchEvent) => this.touchPad(event))
      Row({ space: 8 }) {
        Text(`速度 ${this.sliderSpeed}`).fontSize(13).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_control'))
        Slider({ value: this.sliderSpeed, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
          .layoutWeight(1).selectedColor($r('app.color.accent_green'))
          .onChange((value: number) => {
            if (Date.now() - this.lastSliderVibration > 80) {
              Haptics.soft();
              this.lastSliderVibration = Date.now();
            }
            this.onSpeedChange(value);
          })
      }.width('100%').height(48).padding({ left: 8, right: 8 })
        .backgroundColor($r('app.color.control_side')).borderRadius(14)
        .border({ width: 1.5, color: $r('app.color.control_border') })
    }.width('100%').padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor($r('app.color.panel_background')).borderRadius(22)
  }
}
