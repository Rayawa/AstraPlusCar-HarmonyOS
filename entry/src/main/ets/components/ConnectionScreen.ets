import { hdsEffect } from '@kit.UIDesignKit';
import { AppColors } from '../constants/AppConstants';

@Component
export struct ConnectionScreen {
  @Prop endpoint: string = '';
  @Prop connecting: boolean = false;
  @Prop statusText: string = '等待连接';
  @Prop logs: string[] = [];
  onEndpointChange: (value: string) => void = () => {};
  onConnect: () => void = () => {};

  @State contentVisible: boolean = false;
  @State connectPressed: boolean = false;
  private enterTimer: number = -1;

  aboutToAppear(): void {
    this.enterTimer = setTimeout(() => {
      this.contentVisible = true;
      this.enterTimer = -1;
    }, 40);
  }

  aboutToDisappear(): void {
    if (this.enterTimer >= 0) {
      clearTimeout(this.enterTimer);
      this.enterTimer = -1;
    }
    this.contentVisible = false;
    this.connectPressed = false;
  }

  build() {
    Column() {
      Column({ space: 7 }) {
        Row({ space: 8 }) {
          Circle()
            .width(10)
            .height(10)
            .backgroundColor(AppColors.PRIMARY_BLUE)
            .shadow({ radius: 7, color: '#700A84FF' })
          Text('ASTRA DRIVE')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.PRIMARY_BLUE)
            .letterSpacing(2.4)
        }
        Text('连接你的小车')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Text('手机与小车连接同一个 Wi-Fi，输入车端地址即可开始操控。')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .lineHeight(21)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .margin({ top: 30, bottom: 24 })

      Column({ space: 13 }) {
        Text('车端连接')
          .width('100%')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))

        TextInput({ text: this.endpoint, placeholder: '例如 http://192.168.8.204:8080' })
          .width('100%')
          .height(50)
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .placeholderColor($r('sys.color.font_secondary'))
          .backgroundColor($r('sys.color.ohos_toggle_bg_transparent'))
          .border({ width: 0.5, color: $r('sys.color.toast_border_color') })
          .borderRadius(15)
          .enabled(!this.connecting)
          .onChange((value: string) => this.onEndpointChange(value))

        Button(this.connecting ? '正在连接…' : '连接并进入操控')
          .width('100%')
          .height(50)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor(AppColors.PRIMARY_BLUE)
          .borderRadius(15)
          .enabled(!this.connecting)
          .scale({ x: this.connectPressed ? 0.98 : 1, y: this.connectPressed ? 0.98 : 1 })
          .animation({ duration: 150, curve: Curve.EaseOut })
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pointLight({
              sourceType: this.connectPressed ? hdsEffect.PointLightSourceType.BRIGHT :
                hdsEffect.PointLightSourceType.NONE,
              illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
              options: { color: '#D8EEFF', intensity: 8, height: 120 }
            })
            .pressShadow(this.connectPressed ? hdsEffect.PressShadowType.BLEND_WHITE :
              hdsEffect.PressShadowType.NONE)
            .buildEffect())
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.connectPressed = true;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.connectPressed = false;
            }
          })
          .onClick(() => this.onConnect())

        Row({ space: 8 }) {
          Circle()
            .width(8)
            .height(8)
            .backgroundColor(this.connecting ? AppColors.WARNING : $r('sys.color.icon_secondary'))
          Text(this.statusText)
            .fontSize(12)
            .fontColor(this.statusText.includes('失败') || this.statusText.includes('无效') ?
              AppColors.DANGER : $r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        Column({ space: 8 }) {
          Row() {
            Text('连接日志')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Text(`${this.logs.length} 条`)
              .fontSize(11)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')

          Scroll() {
            Column({ space: 6 }) {
              ForEach(this.logs, (line: string) => {
                Text(line)
                  .width('100%')
                  .fontSize(10)
                  .fontFamily('monospace')
                  .fontColor(line.includes('[ERR]') ? AppColors.DANGER :
                    (line.includes('[WARN]') ? AppColors.WARNING : $r('sys.color.font_secondary')))
              }, (line: string) => line)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .scrollBar(BarState.Off)
          .width('100%')
          .height(122)
        }
        .width('100%')
        .padding(13)
        .backgroundColor($r('sys.color.ohos_toggle_bg_transparent'))
        .borderRadius(15)
      }
      .width('100%')
      .padding(18)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .border({ width: 0.5, color: $r('sys.color.toast_border_color') })
      .borderRadius(22)
      .shadow({ radius: 16, color: '#18000000', offsetX: 0, offsetY: 5 })

      Blank()

      Row({ space: 8 }) {
        Text('同一 Wi-Fi')
          .fontSize(10)
          .fontColor($r('sys.color.font_secondary'))
        Circle().width(3).height(3).backgroundColor($r('sys.color.icon_secondary'))
        Text('车端服务已启动')
          .fontSize(10)
          .fontColor($r('sys.color.font_secondary'))
        Circle().width(3).height(3).backgroundColor($r('sys.color.icon_secondary'))
        Text('松手即停车')
          .fontSize(10)
          .fontColor($r('sys.color.font_secondary'))
      }
      .margin({ bottom: 18 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 22, right: 22 })
    .backgroundColor($r('sys.color.ohos_id_color_background'))
    .opacity(this.contentVisible ? 1 : 0)
    .translate({ y: this.contentVisible ? 0 : 16 })
    .animation({ duration: 420, curve: Curve.EaseOut })
  }
}
