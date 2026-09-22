import { AppColors } from '../constants/AppConstants';

@Component
export struct CameraPanel {
  @Prop connected: boolean = false;
  @Prop cameraEnabled: boolean = false;
  @Prop frameUrl: string = '';
  @Prop captureBusy: boolean = false;
  onToggleCamera: () => void = () => {};
  onCapture: () => void = () => {};
  onResetServo: () => void = () => {};

  build() {
    Column() {
      Row() {
        Column() {
          Text('实时视野')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT)
          Text(this.cameraEnabled ? '720P · 约 3 FPS 预览' : '摄像头预览已停止')
            .fontSize(12)
            .fontColor(AppColors.TEXT_MUTED)
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button(this.cameraEnabled ? '暂停' : '预览')
          .height(36)
          .fontSize(13)
          .fontColor(AppColors.TEXT)
          .backgroundColor(AppColors.PANEL_SOFT)
          .enabled(this.connected)
          .onClick(() => this.onToggleCamera())
      }
      .width('100%')
      .margin({ bottom: 14 })

      Stack({ alignContent: Alignment.Center }) {
        if (this.cameraEnabled && this.frameUrl.length > 0) {
          Image(this.frameUrl)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column({ space: 12 }) {
            Text('◉')
              .fontSize(52)
              .fontColor(AppColors.TEXT_MUTED)
            Text(this.connected ? '点击“预览”开启画面' : '连接后显示智能摄像头画面')
              .fontSize(14)
              .fontColor(AppColors.TEXT_MUTED)
          }
        }
        Row() {
          Text('● LIVE')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.cameraEnabled ? AppColors.DANGER : AppColors.TEXT_MUTED)
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .backgroundColor(AppColors.LIVE_BADGE)
            .borderRadius(12)
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Top)
        .padding(12)
      }
      .width('100%')
      .aspectRatio(16 / 9)
      .backgroundColor(AppColors.CAMERA_BACKGROUND)
      .borderRadius(16)
      .clip(true)

      Row({ space: 10 }) {
        Button(this.captureBusy ? '保存中…' : '截图')
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.BACKGROUND)
          .backgroundColor(AppColors.PRIMARY)
          .enabled(this.connected && !this.captureBusy)
          .onClick(() => this.onCapture())
        Button('镜头复位')
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .fontColor(AppColors.TEXT)
          .backgroundColor(AppColors.PANEL_SOFT)
          .enabled(this.connected)
          .onClick(() => this.onResetServo())
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(AppColors.PANEL)
    .borderRadius(20)
    .border({ width: 1, color: AppColors.BORDER })
  }
}
