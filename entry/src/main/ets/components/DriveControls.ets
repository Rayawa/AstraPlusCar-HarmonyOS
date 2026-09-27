import { hdsEffect } from '@kit.UIDesignKit';
import { Haptics } from '../services/Haptics';

/** The visible control shapes and the hit zones share the same geometry. */
@Component
export struct DriveControls {
  @Prop connected: boolean = false;
  @Prop activeKey: string = '';
  @Prop sliderSpeed: number = 40;
  @State private touchingKey: string = '';
  @State private rowWidth: number = 352;
  onStart: (key: string) => void = () => {};
  onEnd: (key: string) => void = () => {};
  onStop: () => void = () => {};
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
    if (radius <= 35) { return 'stop'; }
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
    this.heldZone = next;
    this.touchingKey = next;
    Haptics.soft();
    if (!this.connected) { this.onUnavailable(); return; }
    if (next === 'stop') { this.onStop(); } else { this.onStart(next); }
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
      if (this.connected && this.heldZone.length > 0 && this.heldZone !== 'stop') { this.onEnd(this.heldZone); }
      this.heldZone = '';
      this.touchingKey = '';
      this.trackingId = -1;
      return;
    }
    const next: string = this.zoneAt(point.x, point.y);
    if (next === this.heldZone) { this.clearPending(); return; }
    if (this.connected && this.heldZone.length > 0 && this.heldZone !== 'stop') { this.onEnd(this.heldZone); }
    this.heldZone = '';
    this.touchingKey = '';
    if (next.length === 0) { this.clearPending(); return; }
    if (event.type === TouchType.Down || next === 'stop') {
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
    Stack({ alignContent: Alignment.TopStart }) {
      Path({ width: this.rowWidth, height: 244, commands: this.cornerPath(key) })
        .fill(this.touchingKey === key || this.activeKey === key ?
          $r('app.color.accent_green') : $r('app.color.control_side'))
        .stroke($r('app.color.control_border')).strokeWidth(1.5)
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pressShadow(this.touchingKey === key ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE)
          .pointLight({ sourceType: this.touchingKey === key ?
            hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
            options: { color: '#D7FFD8', intensity: 8, height: 110 } }).buildEffect())
        .width('100%').height(244).hitTestBehavior(HitTestMode.None)
      Text(label).width(54).height(28).textAlign(TextAlign.Center)
        .fontSize(11).fontWeight(FontWeight.Bold).maxLines(1)
        .fontColor(this.touchingKey === key || this.activeKey === key ?
          $r('app.color.white') : $r('app.color.text_control'))
        .position({ x: x, y: y }).hitTestBehavior(HitTestMode.None)
    }.width('100%').height(244).hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private Direction(label: string, key: string, x: number, y: number) {
    Text(label).width(58).height(26).textAlign(TextAlign.Center)
      .fontSize(12).fontWeight(FontWeight.Bold)
      .fontColor(this.touchingKey === key || this.activeKey === key ?
        $r('app.color.white') : $r('app.color.text_control'))
      .position({ x: x, y: y }).hitTestBehavior(HitTestMode.None)
  }

  build() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        this.OuterKey('左旋转', 'q', 12, 43)
        this.OuterKey('右旋转', 'e', this.rowWidth - 76, 43)
        this.OuterKey('左平移', 'left', 12, 173)
        this.OuterKey('右平移', 'right', this.rowWidth - 76, 173)
        Stack({ alignContent: Alignment.Center }) {
          Column().width(236).height(236).borderRadius(118)
            .backgroundColor($r('app.color.control_separator'))
            .shadow({ radius: 9, color: '#162D714B', offsetY: 3 })
          ForEach([0, 1, 2, 3], (index: number) => {
            Path({ width: 236, height: 236, commands: this.sectorPath(index) })
              .fill(this.touchingKey === ['w', 'd', 's', 'a'][index] ||
                this.activeKey === ['w', 'd', 's', 'a'][index] ?
                $r('app.color.accent_green') : $r('app.color.control_idle'))
              .stroke($r('app.color.control_separator')).strokeWidth(6)
              .visualEffect(new hdsEffect.HdsEffectBuilder()
                .pressShadow(this.touchingKey === ['w', 'd', 's', 'a'][index] ?
                  hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE)
                .pointLight({ sourceType: this.touchingKey === ['w', 'd', 's', 'a'][index] ?
                  hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                  illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
                  options: { color: '#D7FFD8', intensity: 8, height: 110 } }).buildEffect())
              .width(236).height(236).hitTestBehavior(HitTestMode.None)
          }, (index: number) => index.toString())
          this.Direction('前进', 'w', 89, 21)
          this.Direction('左转', 'a', 7, 104)
          this.Direction('右转', 'd', 171, 104)
          this.Direction('后退', 's', 89, 188)
          Stack({ alignContent: Alignment.Center }) {
            Column().width(76).height(76).borderRadius(38)
              .backgroundColor($r('app.color.danger'))
              .border({ width: 6, color: $r('app.color.control_separator') })
            Text('停车').fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.white'))
          }.width(76).height(76)
            .scale({ x: this.touchingKey === 'stop' ? 0.94 : 1,
              y: this.touchingKey === 'stop' ? 0.94 : 1 })
            .visualEffect(new hdsEffect.HdsEffectBuilder()
              .pressShadow(this.touchingKey === 'stop' ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE)
              .pointLight({ sourceType: this.touchingKey === 'stop' ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
                options: { color: '#FFD4D1', intensity: 8, height: 110 } }).buildEffect())
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
    }.width('100%').padding(8)
      .backgroundColor($r('app.color.panel_background')).borderRadius(22)
  }
}
