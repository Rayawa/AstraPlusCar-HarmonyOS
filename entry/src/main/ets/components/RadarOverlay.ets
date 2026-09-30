@Component
struct RadarSector {
  @Prop label: string = '';
  @Prop scanning: boolean = false;
  @Prop distance: number | null = null;

  private distanceText(): string {
    return this.scanning && this.distance !== null && Number.isFinite(this.distance) ?
      `${Math.round(this.distance)}` : '--';
  }

  private color(): string {
    if (!this.scanning || this.distance === null || !Number.isFinite(this.distance)) { return '#AA354350'; }
    if (this.distance <= 300) { return '#D0B52D3D'; }
    if (this.distance <= 800) { return '#D0A56819'; }
    return '#C0276848';
  }

  build() {
    Column({ space: 1 }) {
      Text(this.label).fontSize(9).fontColor(Color.White)
      Text(this.distanceText()).fontSize(10).fontWeight(FontWeight.Bold)
        .fontColor(Color.White).maxLines(1)
    }
    .layoutWeight(1).height(37).justifyContent(FlexAlign.Center)
    .backgroundColor(this.color()).borderRadius(7)
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
        Text(this.scanning ? `雷达 ${this.points} 点` : '雷达等待扫描')
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
