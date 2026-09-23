import { AppColors } from '../constants/AppConstants';
import { GalleryItem } from '../models/CarModels';

@Component
export struct GalleryScreen {
  @Prop items: GalleryItem[] = [];
  @Prop loading: boolean = false;
  @Prop captureBusy: boolean = false;
  @Prop message: string = '';
  onBack: () => void = () => {};
  onRefresh: () => void = () => {};
  onCapture: () => void = () => {};

  build() {
    Column() {
      Row({ space: 10 }) {
        Button('返回操控')
          .height(40)
          .fontSize(13)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(12)
          .onClick(() => this.onBack())
        Column() {
          Text('车辆相册')
            .fontSize(23)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
          Text(this.message)
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
      }
      .width('100%')

      Row({ space: 10 }) {
        Blank()
        Button(this.loading ? '刷新中…' : '刷新')
          .height(40)
          .fontSize(13)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(12)
          .enabled(!this.loading)
          .onClick(() => this.onRefresh())
        Button(this.captureBusy ? '保存中…' : '拍一张')
          .height(40)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor(AppColors.PRIMARY_BLUE)
          .borderRadius(12)
          .enabled(!this.captureBusy)
          .onClick(() => this.onCapture())
      }
      .width('100%')
      .margin({ top: 10 })

      if (!this.loading && this.items.length === 0) {
        Column({ space: 8 }) {
          Text('暂无照片')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_secondary'))
          Text('点击右上角“拍一张”，照片会保存到车端并显示在这里。')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.items, (item: GalleryItem) => {
            GridItem() {
              Column() {
                Image(item.url)
                  .width('100%')
                  .height(128)
                  .objectFit(ImageFit.Cover)
                  .borderRadius({ topLeft: 12, topRight: 12 })
                Text(item.name)
                  .width('100%')
                  .fontSize(10)
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding(8)
              }
              .width('100%')
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .borderRadius(12)
              .border({ width: 1, color: AppColors.BORDER })
            }
          }, (item: GalleryItem) => item.name)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(12)
        .rowsGap(12)
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 14 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 14 })
    .backgroundColor($r('sys.color.ohos_id_color_background'))
  }
}
