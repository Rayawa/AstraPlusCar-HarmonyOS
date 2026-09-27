import { hdsEffect } from '@kit.UIDesignKit';

@Component
struct ConnectionChip {
  @Prop label: string = '';
  @Prop ready: boolean = false;
  onOpen: () => void = () => {};
  @State pressed: boolean = false;

  build() {
    Row({ space: 5 }) {
      Text('●').fontSize(10).fontColor(this.ready ? '#41BA41' : '#FF3B30')
      Text(this.label).fontSize(12).fontWeight(FontWeight.Medium)
        .fontColor(this.ready ? '#287328' : '#B53730')
    }
    .layoutWeight(1).justifyContent(FlexAlign.Center).height(38)
    .backgroundColor(this.ready ? '#E8F5E9' : '#FFEBEE')
    .borderRadius(13).border({ width: 0.5, color: this.ready ? '#A6D9AB' : '#F4B7B5' })
    .scale({ x: this.pressed ? 0.96 : 1, y: this.pressed ? 0.96 : 1 })
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pressShadow(this.pressed ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE)
      .pointLight({ sourceType: this.pressed ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: { color: '#FFFFFF', intensity: 7, height: 100 } }).buildEffect())
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) { this.pressed = true; }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.pressed = false; }
    })
    .onClick(() => this.onOpen())
  }
}

@Component
export struct ConnectionIndicators {
  @Prop connected: boolean = false;
  @Prop cameraReady: boolean = false;
  @Prop lidarReady: boolean = false;
  onOpen: () => void = () => {};

  build() {
    Row({ space: 7 }) {
      ConnectionChip({ label: '小车', ready: this.connected, onOpen: () => this.onOpen() })
      ConnectionChip({ label: '视频', ready: this.connected && this.cameraReady, onOpen: () => this.onOpen() })
      ConnectionChip({ label: '雷达', ready: this.connected && this.lidarReady, onOpen: () => this.onOpen() })
    }.width('100%')
  }
}
