import { AppColors } from '../constants/AppConstants';

@Component
export struct AppHeader {
  @Prop connected: boolean = false;
  @Prop isWide: boolean = false;

  build() {
    Row() {
      Column() {
        Text('ASTRA DRIVE')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.PRIMARY)
          .letterSpacing(2)
        Text('智能小车控制台')
          .fontSize(this.isWide ? 28 : 24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT)
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Row({ space: 8 }) {
        Text('●')
          .fontSize(10)
          .fontColor(this.connected ? AppColors.PRIMARY : AppColors.TEXT_MUTED)
        Text(this.connected ? '在线' : '离线')
          .fontSize(13)
          .fontColor(this.connected ? AppColors.PRIMARY : AppColors.TEXT_MUTED)
      }
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.connected ? AppColors.PRIMARY_DARK : AppColors.PANEL_SOFT)
      .borderRadius(20)
    }
    .width('100%')
  }
}
