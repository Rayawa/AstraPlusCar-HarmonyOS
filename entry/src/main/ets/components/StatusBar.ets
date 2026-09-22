import { AppColors } from '../constants/AppConstants';

@Component
export struct StatusBar {
  @Prop connected: boolean = false;
  @Prop statusText: string = '';

  build() {
    Row({ space: 8 }) {
      Text(this.connected ? '✓' : '!')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.connected ? AppColors.PRIMARY : AppColors.WARNING)
      Text(this.statusText)
        .fontSize(12)
        .fontColor(AppColors.TEXT_MUTED)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 12, bottom: 4 })
  }
}
