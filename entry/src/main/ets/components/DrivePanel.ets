import { AppColors, CarLimits } from '../constants/AppConstants';
import { CarAction } from '../models/CarModels';

@Component
export struct DrivePanel {
  @Prop connected: boolean = false;
  @Prop speed: number = CarLimits.SPEED_MIN;
  @Prop activeAction: CarAction = CarAction.NONE;
  onMoveStart: (action: CarAction) => void = () => {};
  onMoveEnd: (action: CarAction) => void = () => {};
  onEmergencyStop: () => void = () => {};
  onSpeedChange: (value: number) => void = () => {};

  @Builder
  DriveButton(label: string, action: CarAction, size: number = 66) {
    Button(label)
      .width(size)
      .height(size)
      .fontSize(label.length > 1 ? 14 : 27)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.activeAction === action ? AppColors.BACKGROUND : AppColors.TEXT)
      .backgroundColor(this.activeAction === action ? AppColors.PRIMARY : AppColors.PANEL_SOFT)
      .borderRadius(18)
      .border({ width: 1, color: this.activeAction === action ? AppColors.PRIMARY : AppColors.BORDER })
      .enabled(this.connected)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.onMoveStart(action);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.onMoveEnd(action);
        }
      })
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('方向控制')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT)
          Text('按住移动 · 松手停车')
            .fontSize(12)
            .fontColor(AppColors.TEXT_MUTED)
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(`${this.speed}`)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.PRIMARY)
        Text(' 速度')
          .fontSize(12)
          .fontColor(AppColors.TEXT_MUTED)
      }
      .width('100%')

      Column({ space: 10 }) {
        this.DriveButton('↑', CarAction.FORWARD)
        Row({ space: 10 }) {
          this.DriveButton('←', CarAction.LEFT)
          Button('STOP')
            .width(76)
            .height(66)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT)
            .backgroundColor(AppColors.STOP_BACKGROUND)
            .borderRadius(18)
            .border({ width: 1, color: AppColors.DANGER })
            .onClick(() => this.onEmergencyStop())
          this.DriveButton('→', CarAction.RIGHT)
        }
        this.DriveButton('↓', CarAction.BACKWARD)
      }
      .width('100%')
      .margin({ top: 18, bottom: 20 })

      Row() {
        Text('速度')
          .width(44)
          .fontSize(13)
          .fontColor(AppColors.TEXT_MUTED)
        Slider({
          value: this.speed,
          min: CarLimits.SPEED_MIN,
          max: CarLimits.SPEED_MAX,
          step: CarLimits.SPEED_STEP,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .selectedColor(AppColors.PRIMARY)
          .blockColor(AppColors.TEXT)
          .trackColor(AppColors.BORDER)
          .onChange((value: number) => this.onSpeedChange(Math.round(value)))
        Text(`${this.speed}`)
          .width(36)
          .textAlign(TextAlign.End)
          .fontSize(14)
          .fontColor(AppColors.TEXT)
      }
      .width('100%')

      Text('全向移动')
        .width('100%')
        .fontSize(13)
        .fontColor(AppColors.TEXT_MUTED)
        .margin({ top: 18, bottom: 10 })
      Row({ space: 8 }) {
        this.DriveButton('左移', CarAction.SHIFT_LEFT, 58)
        this.DriveButton('逆旋', CarAction.SPIN_LEFT, 58)
        this.DriveButton('顺旋', CarAction.SPIN_RIGHT, 58)
        this.DriveButton('右移', CarAction.SHIFT_RIGHT, 58)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(AppColors.PANEL)
    .borderRadius(20)
    .border({ width: 1, color: AppColors.BORDER })
  }
}
