import { AppColors, CarDefaults, CarLimits } from '../constants/AppConstants';

@Component
export struct ServoPanel {
  @Prop connected: boolean = false;
  @Prop verticalAngle: number = CarDefaults.VERTICAL_ANGLE;
  @Prop horizontalAngle: number = CarDefaults.HORIZONTAL_ANGLE;
  onAnglesChange: (vertical: number, horizontal: number, commit: boolean) => void = () => {};

  build() {
    Column({ space: 16 }) {
      Row() {
        Text('云台控制')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT)
        Blank()
        Text(`${this.verticalAngle}° / ${this.horizontalAngle}°`)
          .fontSize(13)
          .fontColor(AppColors.PRIMARY)
      }
      .width('100%')
      Row() {
        Text('俯仰')
          .width(44)
          .fontSize(13)
          .fontColor(AppColors.TEXT_MUTED)
        Slider({
          value: this.verticalAngle,
          min: CarLimits.VERTICAL_MIN,
          max: CarLimits.VERTICAL_MAX,
          step: CarLimits.SERVO_STEP
        })
          .layoutWeight(1)
          .selectedColor(AppColors.PRIMARY)
          .trackColor(AppColors.BORDER)
          .enabled(this.connected)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.onAnglesChange(Math.round(value), this.horizontalAngle, mode === SliderChangeMode.End);
          })
      }
      .width('100%')
      Row() {
        Text('水平')
          .width(44)
          .fontSize(13)
          .fontColor(AppColors.TEXT_MUTED)
        Slider({
          value: this.horizontalAngle,
          min: CarLimits.HORIZONTAL_MIN,
          max: CarLimits.HORIZONTAL_MAX,
          step: CarLimits.SERVO_STEP
        })
          .layoutWeight(1)
          .selectedColor(AppColors.PRIMARY)
          .trackColor(AppColors.BORDER)
          .enabled(this.connected)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.onAnglesChange(this.verticalAngle, Math.round(value), mode === SliderChangeMode.End);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor(AppColors.PANEL)
    .borderRadius(20)
    .border({ width: 1, color: AppColors.BORDER })
  }
}
