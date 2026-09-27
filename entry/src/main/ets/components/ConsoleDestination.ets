import { HdsNavDestination, hdsEffect, hdsMaterial, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ConsoleLine } from '../models/ConsoleLine';

@Component
export struct ConsoleDestination {
  @Prop @Watch('onLinesChanged') lines: ConsoleLine[] = [];
  onBack: () => void = () => {};
  private scroller: Scroller = new Scroller();

  private onLinesChanged(): void {
    setTimeout((): void => { this.scroller.scrollEdge(Edge.Bottom); }, 30);
  }

  private typeColor(type: string): string {
    if (type === 'ERR') { return '#FF3B30'; }
    if (type === 'RECV') { return '#287328'; }
    if (type === 'SEND') { return '#007DFF'; }
    return '#666666';
  }

  build() {
    HdsNavDestination() {
      Column() {
        List({ scroller: this.scroller, space: 3 }) {
          ForEach(this.lines, (line: ConsoleLine) => {
            ListItem() {
              Row({ space: 5 }) {
                Text(`[${line.time}]`).fontSize(10).fontColor('#666666').flexShrink(0)
                Text(`[${line.type}]`).fontSize(12).fontWeight(FontWeight.Bold)
                  .fontColor(this.typeColor(line.type)).flexShrink(0)
                Text(line.content).fontSize(12).fontColor(this.typeColor(line.type))
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%').padding({ top: 5, bottom: 5 })
              .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
                illuminatedType: hdsEffect.PointLightIlluminatedType.CONTENT
              }).buildEffect())
            }
          }, (line: ConsoleLine) => line.id)
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor('#FFFFFF').borderRadius(16)
        .border({ width: 0.5, color: '#D2E0F0' })
        .shadow({ radius: 8, color: '#1A000000', offsetY: 2 })
      }
      .width('100%').height('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 16 })
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
      content: { title: { mainTitle: '车端控制台' }, backIcon: { action: () => this.onBack() } }
    })
  }
}
