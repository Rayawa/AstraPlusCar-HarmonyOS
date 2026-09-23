import {
  BlurStrategy,
  hdsEffect,
  hdsMaterial,
  HdsTabs,
  HdsTabsController
} from '@kit.UIDesignKit';
import { AppColors, CarLimits } from '../constants/AppConstants';
import { CarAction } from '../models/CarModels';
import { GameJoystick } from './GameJoystick';

@Component
export struct GameControlScreen {
  @Prop connected: boolean = false;
  @Prop cameraReady: boolean = false;
  @Prop frameUrl: string = '';
  @Prop speed: number = CarLimits.SPEED_MIN;
  @Prop activeAction: CarAction = CarAction.NONE;
  @Prop statusText: string = '';
  @Prop captureBusy: boolean = false;
  @Prop verticalAngle: number = 90;
  @Prop horizontalAngle: number = 65;
  onMoveStart: (action: CarAction) => void = () => {};
  onMoveEnd: (action: CarAction) => void = () => {};
  onEmergencyStop: () => void = () => {};
  onSpeedChange: (value: number) => void = () => {};
  onServoStep: (verticalDelta: number, horizontalDelta: number) => void = () => {};
  onResetServo: () => void = () => {};
  onCapture: () => void = () => {};
  onOpenGallery: () => void = () => {};
  onDisconnect: () => void = () => {};

  private readonly tabsController: HdsTabsController = new HdsTabsController();
  @State currentTabIndex: number = 0;
  @State pressedControl: string = '';
  @State contentVisible: boolean = false;
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
    this.pressedControl = '';
  }

  private setPressed(key: string, pressed: boolean): void {
    this.pressedControl = pressed ? key : '';
  }

  @Builder
  private HoldButton(label: string, action: CarAction) {
    Button(label)
      .width('48%')
      .height(42)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.activeAction === action ? Color.White : $r('sys.color.font_primary'))
      .backgroundColor(this.activeAction === action ? AppColors.PRIMARY_BLUE :
        $r('sys.color.ohos_toggle_bg_transparent'))
      .border({
        width: 0.5,
        color: this.activeAction === action ? AppColors.PRIMARY_BLUE : $r('sys.color.toast_border_color')
      })
      .borderRadius(14)
      .scale({
        x: this.activeAction === action ? 0.96 : 1,
        y: this.activeAction === action ? 0.96 : 1
      })
      .animation({ duration: 150, curve: Curve.EaseOut })
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pointLight({
          sourceType: this.activeAction === action ? hdsEffect.PointLightSourceType.BRIGHT :
            hdsEffect.PointLightSourceType.NONE,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
          options: { color: '#8CC8FF', intensity: 8, height: 120 }
        })
        .pressShadow(this.activeAction === action ? hdsEffect.PressShadowType.BLEND_WHITE :
          hdsEffect.PressShadowType.NONE)
        .buildEffect())
      .enabled(this.connected)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.onMoveStart(action);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.onMoveEnd(action);
        }
      })
  }

  @Builder
  private ControlButton(key: string, label: string, onClick: () => void, danger: boolean = false) {
    Button(label)
      .height(42)
      .layoutWeight(1)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(danger ? AppColors.DANGER : $r('sys.color.font_primary'))
      .backgroundColor(danger ? '#16FF3B30' : $r('sys.color.ohos_toggle_bg_transparent'))
      .border({
        width: 0.5,
        color: danger ? AppColors.DANGER : $r('sys.color.toast_border_color')
      })
      .borderRadius(14)
      .scale({ x: this.pressedControl === key ? 0.96 : 1, y: this.pressedControl === key ? 0.96 : 1 })
      .animation({ duration: 150, curve: Curve.EaseOut })
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pointLight({
          sourceType: this.pressedControl === key ? hdsEffect.PointLightSourceType.BRIGHT :
            hdsEffect.PointLightSourceType.NONE,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
          options: {
            color: danger ? '#FF8A84' : '#8CC8FF',
            intensity: 8,
            height: 120
          }
        })
        .pressShadow(this.pressedControl === key ? hdsEffect.PressShadowType.BLEND_WHITE :
          hdsEffect.PressShadowType.NONE)
        .buildEffect())
      .enabled(this.connected)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.setPressed(key, true);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.setPressed(key, false);
        }
      })
      .onClick(onClick)
  }

  @Builder
  private StatusHeader() {
    Row({ space: 10 }) {
      Row({ space: 7 }) {
        Circle()
          .width(9)
          .height(9)
          .backgroundColor(this.connected ? AppColors.SUCCESS : AppColors.DANGER)
          .shadow({ radius: 5, color: this.connected ? '#7066D69E' : '#70FF3B30' })
        Column({ space: 1 }) {
          Text(this.connected ? '车辆在线' : '车辆离线')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
          Text(this.statusText)
            .fontSize(10)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .layoutWeight(1)

      Button('相册')
        .height(36)
        .fontSize(12)
        .fontColor($r('sys.color.font_primary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .onClick(() => this.onOpenGallery())
      Button('断开')
        .height(36)
        .fontSize(12)
        .fontColor(AppColors.DANGER)
        .backgroundColor('#12FF3B30')
        .borderRadius(12)
        .onClick(() => this.onDisconnect())
    }
    .width('100%')
    .height(48)
  }

  @Builder
  private CameraPreview() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.cameraReady && this.frameUrl.length > 0) {
        Image(this.frameUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Column({ space: 7 }) {
          SymbolGlyph($r('sys.symbol.camera_slash'))
            .fontSize(32)
            .fontColor([$r('sys.color.icon_secondary')])
          Text('摄像头暂不可用')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Text('底盘控制仍然可用，请检查车端摄像头状态')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
        }
      }

      Row({ space: 6 }) {
        Circle().width(7).height(7).backgroundColor(this.cameraReady ? '#FF453A' : '#8E8E93')
        Text(this.cameraReady ? 'LIVE' : 'OFFLINE')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor('#99000000')
      .borderRadius(12)
      .position({ x: 12, y: 12 })
    }
    .width('100%')
    .height(220)
    .backgroundColor('#101214')
    .borderRadius(20)
    .clip(true)
    .border({ width: 0.5, color: $r('sys.color.toast_border_color') })
    .shadow({ radius: 16, color: '#22000000', offsetX: 0, offsetY: 5 })
  }

  @Builder
  private DriveMode() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 2 }) {
          Text('驾驶控制')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
          Text('拖动摇杆行驶，松手立即停车')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Text(`速度 ${this.speed}`)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.PRIMARY_BLUE)
      }
      .width('100%')

      Row({ space: 12 }) {
        GameJoystick({
          connected: this.connected,
          activeAction: this.activeAction,
          onMoveStart: (action: CarAction) => this.onMoveStart(action),
          onMoveEnd: (action: CarAction) => this.onMoveEnd(action)
        })

        Column({ space: 8 }) {
          Row({ space: 8 }) {
            this.HoldButton('逆时针', CarAction.SPIN_LEFT)
            this.HoldButton('顺时针', CarAction.SPIN_RIGHT)
          }
          Text('速度')
            .width('100%')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
          Slider({
            value: this.speed,
            min: CarLimits.SPEED_MIN,
            max: CarLimits.SPEED_MAX,
            step: CarLimits.SPEED_STEP,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .selectedColor(AppColors.PRIMARY_BLUE)
            .blockColor(Color.White)
            .trackColor('#24007DFF')
            .onChange((value: number) => this.onSpeedChange(Math.round(value)))
          this.ControlButton('stop', 'STOP 紧急停车', () => this.onEmergencyStop(), true)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 88 })
  }

  @Builder
  private ServoMode() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 2 }) {
          Text('云台与影像')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
          Text('微调镜头方向，随时截图保存')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Button(this.captureBusy ? '保存中…' : '截图')
          .height(38)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(AppColors.PRIMARY_BLUE)
          .borderRadius(13)
          .enabled(this.connected && !this.captureBusy)
          .onClick(() => this.onCapture())
      }
      .width('100%')

      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text('俯仰')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
          Text(`${this.verticalAngle}°`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(16)
        Column({ space: 4 }) {
          Text('水平')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
          Text(`${this.horizontalAngle}°`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(16)
      }
      .width('100%')

      Row({ space: 10 }) {
        this.ControlButton('up', '镜头 ↑', () => this.onServoStep(-5, 0))
        this.ControlButton('down', '镜头 ↓', () => this.onServoStep(5, 0))
      }
      .width('100%')
      Row({ space: 10 }) {
        this.ControlButton('left', '镜头 ←', () => this.onServoStep(0, -5))
        this.ControlButton('right', '镜头 →', () => this.onServoStep(0, 5))
      }
      .width('100%')
      Row({ space: 10 }) {
        this.ControlButton('reset', '云台复位', () => this.onResetServo())
        this.ControlButton('gallery', '打开相册', () => this.onOpenGallery())
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 88 })
  }

  build() {
    Column({ space: 10 }) {
      this.StatusHeader()
      this.CameraPreview()

      HdsTabs({ controller: this.tabsController }) {
        TabContent() {
          this.DriveMode()
        }
        .tabBar(new BottomTabBarStyle($r('sys.media.car_fill'), '驾驶模式'))

        TabContent() {
          this.ServoMode()
        }
        .tabBar(new BottomTabBarStyle($r('sys.media.wifi_router_fill'), '云台模式'))
      }
      .layoutWeight(1)
      .width('100%')
      .onChange((index: number) => {
        if (this.activeAction !== CarAction.NONE) {
          this.onMoveEnd(this.activeAction);
        }
        this.currentTabIndex = index;
      })
      .blurStrategy(BlurStrategy.ENABLE)
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .scrollable(false)
      .barFloatingStyle({
        barBottomMargin: 18,
        barSideMargin: 20,
        lightColor: '#D8EEFF',
        gradientMask: {
          maskColor: $r('sys.color.ohos_id_color_background'),
          maskHeight: 64
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14, top: 8 })
    .backgroundColor($r('sys.color.ohos_id_color_background'))
    .opacity(this.contentVisible ? 1 : 0)
    .translate({ y: this.contentVisible ? 0 : 16 })
    .animation({ duration: 420, curve: Curve.EaseOut })
  }
}
