import { RadarPresentation } from '../services/RadarPresentation';

@Component
struct RadarSector {
  @Prop label: string = '';
  @Prop scanning: boolean = false;
  @Prop distance: number | null = null;

  private distanceText(): string {
    return RadarPresentation.distanceText(this.distance, this.scanning);
  }

  private color(): string {
    return RadarPresentation.color(this.distance, this.scanning);
  }

  build() {
    Column({ space: 1 }) {
      Text(`${this.label} · ${RadarPresentation.label(this.distance, this.scanning)}`)
        .fontSize(9).fontColor('#D9FFFFFF')
      Text(this.distanceText()).fontSize(12).fontWeight(FontWeight.Bold)
        .fontColor(this.color()).maxLines(1)
    }
    .layoutWeight(1).height(37).justifyContent(FlexAlign.Center)
    .backgroundColor('#40354350').borderRadius(7)
    .border({ width: { bottom: 2 }, color: this.color() })
  }
}

/** Front and side distances from the sensor-relative radar sectors. */
@Component
export struct RadarOverlay {
  @Prop scanning: boolean = false;
  @Prop points: number = 0;
  @Prop frontMm: number | null = null;
  @Prop leftMm: number | null = null;
  @Prop rightMm: number | null = null;

  build() {
    Column({ space: 4 }) {
      Row() {
        Text(this.scanning ? `雷达 ${this.points}点` : '雷达暂无有效数据')
          .fontSize(9).fontColor(Color.White).maxLines(1)
      }.width('100%')
      Row({ space: 4 }) {
        RadarSector({ label: '左', scanning: this.scanning, distance: this.leftMm })
        RadarSector({ label: '前', scanning: this.scanning, distance: this.frontMm })
        RadarSector({ label: '右', scanning: this.scanning, distance: this.rightMm })
      }.width('100%')
    }
    .width('100%').padding({ left: 6, right: 6, top: 5, bottom: 5 })
    .backgroundColor('#B0000000').borderRadius(10)
    .hitTestBehavior(HitTestMode.None)
  }
}
