import { AppColors, CarDefaults } from '../constants/AppConstants';

@Component
export struct ConnectionPanel {
  @Prop endpoint: string = CarDefaults.ENDPOINT;
  @Prop connected: boolean = false;
  @Prop connecting: boolean = false;
  onEndpointChange: (value: string) => void = () => {};
  onToggleConnection: () => void = () => {};

  build() {
    Row({ space: 10 }) {
      TextInput({ text: this.endpoint, placeholder: CarDefaults.ENDPOINT })
        .layoutWeight(1)
        .height(44)
        .fontSize(14)
        .fontColor(AppColors.TEXT)
        .placeholderColor(AppColors.TEXT_MUTED)
        .backgroundColor(AppColors.PANEL_SOFT)
        .borderRadius(12)
        .enabled(!this.connected && !this.connecting)
        .onChange((value: string) => this.onEndpointChange(value))
      Button(this.connected ? '断开' : (this.connecting ? '连接中' : '连接'))
        .height(44)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.connected ? AppColors.TEXT : AppColors.BACKGROUND)
        .backgroundColor(this.connected ? AppColors.PANEL_SOFT : AppColors.PRIMARY)
        .enabled(!this.connecting)
        .onClick(() => this.onToggleConnection())
    }
    .width('100%')
    .margin({ top: 18 })
  }
}
