import { hdsEffect } from '@kit.UIDesignKit';
import { Haptics } from '../services/Haptics';

@Component
struct ConnectionChip {
  @Prop label: string = '';
  @Prop ready: boolean = false;
  @Prop car: boolean = false;
  onOpen: () => void = () => {};
  @State pressed: boolean = false;

  build() {
    Row({ space: 4 }) {
      Text('●').fontSize(this.car ? 10 : 8)
        .fontColor(this.ready ? $r('app.color.accent_green') : $r('app.color.danger'))
      Text(`${this.label} ${this.ready ? (this.car ? '已连接' : '在线') :
        (this.car ? '未连接' : '离线')}`).fontSize(this.car ? 11 : 10).fontWeight(FontWeight.Medium)
        .fontColor(this.ready ? $r('app.color.accent_green_text') : $r('app.color.danger_text'))
        .maxLines(1)
    }
    .width('100%').justifyContent(FlexAlign.Center).height(this.car ? 44 : 20)
    .backgroundColor(this.ready ? $r('app.color.accent_green_soft') : $r('app.color.danger_soft'))
    .borderRadius(this.car ? 12 : 9).border({ width: 0.5, color: this.ready ?
      $r('app.color.accent_green_border') : $r('app.color.danger_border') })
    .scale({ x: this.pressed ? 0.97 : 1, y: this.pressed ? 0.97 : 1 })
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pressShadow(this.pressed ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE)
      .pointLight({ sourceType: this.pressed ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: { color: '#FFFFFF', intensity: 7, height: 100 } }).buildEffect())
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) { this.pressed = true; Haptics.hard(); }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.pressed = false; }
    })
    .onClick(() => this.onOpen())
  }
}

/** Vehicle connection is the prerequisite for the four dependent capabilities. */
@Component
export struct ConnectionIndicators {
  @Prop connected: boolean = false;
  @Prop cameraReady: boolean = false;
  @Prop lidarReady: boolean = false;
  onOpen: () => void = () => {};

  build() {
    Row({ space: 5 }) {
      Row() {
        ConnectionChip({ label: '小车', ready: this.connected, car: true, onOpen: () => this.onOpen() })
      }.layoutWeight(1)
      Text('›').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_secondary'))
      Column({ space: 4 }) {
        Row({ space: 4 }) {
          Row() {
            ConnectionChip({ label: '视频', ready: this.connected && this.cameraReady,
              onOpen: () => this.onOpen() })
          }.layoutWeight(1)
          Row() {
            ConnectionChip({ label: '雷达', ready: this.connected && this.lidarReady,
              onOpen: () => this.onOpen() })
          }.layoutWeight(1)
        }.width('100%')
        Row({ space: 4 }) {
          Row() {
            ConnectionChip({ label: '语音', ready: false, onOpen: () => this.onOpen() })
          }.layoutWeight(1)
          Row() {
            ConnectionChip({ label: '模型', ready: false, onOpen: () => this.onOpen() })
          }.layoutWeight(1)
        }.width('100%')
      }.layoutWeight(2)
    }.width('100%')
  }
}
