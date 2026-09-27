import { HdsNavDestination, hdsMaterial, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { CaptureItem } from '../services/CaptureStore';

@Component
export struct CaptureGallery {
  @Prop items: CaptureItem[] = [];
  onBack: () => void = () => {};
  onRemove: (name: string) => void = () => {};

  build() {
    HdsNavDestination() {
      Column() {
        if (this.items.length === 0) {
          Column({ space: 8 }) {
            Text('还没有截图').fontSize(21).fontWeight(FontWeight.Bold).fontColor('#202F42')
            Text('在驾驶页点击监看画面即可保存。').fontSize(13).fontColor('#596A7F')
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Text('长按图片可删除').width('100%').fontSize(11).fontColor('#596A7F')
            .margin({ bottom: 8 })
          Grid() {
            ForEach(this.items, (item: CaptureItem) => {
              GridItem() {
                Column({ space: 6 }) {
                  Image(item.uri).width('100%').height(130).objectFit(ImageFit.Cover)
                    .borderRadius(12)
                  Text(item.time).fontSize(11).fontColor('#596A7F').width('100%')
                }
                .padding(8).backgroundColor('#FFFFFF').borderRadius(16)
                .shadow({ radius: 8, color: '#18000000', offsetY: 2 })

              }
              .priorityGesture(LongPressGesture().onAction(() => this.onRemove(item.name)))
            }, (item: CaptureItem) => item.name)
          }
          .columnsTemplate('1fr 1fr').columnsGap(10).rowsGap(10)
          .width('100%').layoutWeight(1).scrollBar(BarState.Off)
        }
      }
      .width('100%').height('100%').padding({ left: 16, right: 16, bottom: 16 })
      .backgroundColor('#F2F6FA')
    }
    .height(LayoutPolicy.matchParent)
    .background('#F2F6FA')
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .titleBar({
      enableComponentSafeArea: true,
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0), blurEffectiveEndOffset: LengthMetrics.vp(20) },
        systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE },
        originalStyle: { backgroundStyle: { backgroundColor: '#F2F6FA' },
          contentStyle: { titleStyle: { mainTitleColor: '#202F42' },
            backIconStyle: { backgroundColor: '#E1EDFA', iconColor: '#202F42' } } },
        scrollEffectStyle: { backgroundStyle: { backgroundColor: '#F2F6FA' },
          contentStyle: { titleStyle: { mainTitleColor: '#202F42' },
            backIconStyle: { backgroundColor: '#E1EDFA', iconColor: '#202F42' } } }
      },
      content: { title: { mainTitle: '截图图库' }, backIcon: { action: () => this.onBack() } }
    })
  }
}
