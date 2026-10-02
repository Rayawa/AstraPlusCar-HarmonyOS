import { PathShape } from '@kit.ArkUI';
import { RadarPresentation } from '../services/RadarPresentation';

/** A single translucent obstacle ribbon, aligned to the sensor-relative zero. */
@Component
export struct RadarWarningHud {
  @Prop scanning: boolean = false;
  @Prop frontMm: number | null = null;
  @Prop leftMm: number | null = null;
  @Prop rightMm: number | null = null;
  @Prop pictureWidth: number = 640;
  @Prop pictureHeight: number = 360;
  @Prop ringWidth: number = 400;

  private distance(sector: number): number | null {
    if (sector === 0) { return this.frontMm; }
    if (sector === 1) { return this.rightMm; }
    return this.leftMm;
  }

  private approaching(distanceMm: number | null): boolean {
    return RadarPresentation.level(distanceMm, this.scanning) >= 2;
  }

  private ringHeight(): number { return Math.min(160, this.pictureHeight * 0.4); }

  private ringTop(): number { return Math.max(80, this.pictureHeight * 0.22); }

  private ringLeft(): number { return (this.pictureWidth - this.ringWidth) / 2; }

  private ribbonColor(distanceMm: number | null): string {
    return RadarPresentation.level(distanceMm, this.scanning) === 3 ? '#FF3B30' : '#FFC247';
  }

  private ribbonOpacity(distanceMm: number | null): number {
    const mm = RadarPresentation.validDistance(distanceMm);
    if (!this.approaching(mm) || mm === null) { return 0; }
    // Continuous intensity within the warning range; closer returns are darker.
    const proximity = Math.max(0, Math.min(1, 1 - mm / RadarPresentation.WARNING_MM));
    return 0.20 + 0.30 * proximity;
  }

  private ribbonGradient(distanceMm: number | null): [ResourceColor, number][] {
    const color = this.ribbonColor(distanceMm);
    const transparent = `#00${color.substring(1)}`;
    return [[transparent, 0.18], [color, 0.34], [color, 0.66], [transparent, 0.82]];
  }

  private ribbonPath(sector: number): string {
    let path = '';
    // Trace both edges of one 12 vp ribbon. Adjacent ends overlap and fade together.
    for (let edge = 0; edge < 2; edge++) {
      const inset = edge === 0 ? 2 : 14;
      const rx = this.ringWidth / 2 - inset;
      const ry = this.ringHeight() / 2 - inset;
      for (let step = 0; step <= 64; step++) {
        const progress = edge === 0 ? step / 64 : 1 - step / 64;
        const angle = (sector * 90 - 47 + progress * 94) * Math.PI / 180;
        const x = this.getUIContext().vp2px(this.ringWidth / 2 + rx * Math.sin(angle));
        const y = this.getUIContext().vp2px(this.ringHeight() / 2 - ry * Math.cos(angle));
        path += `${edge === 0 && step === 0 ? 'M' : 'L'} ${x.toFixed(2)} ${y.toFixed(2)} `;
      }
    }
    return `${path}Z`;
  }

  private captionX(sector: number): number {
    if (sector === 0) { return (this.pictureWidth - 90) / 2; }
    if (sector === 1) { return this.ringLeft() + this.ringWidth + 2; }
    return this.ringLeft() - 92;
  }

  private captionY(sector: number): number {
    if (sector === 0) { return this.ringTop() - 22; }
    return this.ringTop() + this.ringHeight() / 2 - 8;
  }

  // Only the constant sector is passed in; distance and position are read from state
  // inside the builder because by-value @Builder parameters are never refreshed.
  @Builder
  private DistanceCaption(label: string, sector: number) {
    Text(`${label} ${RadarPresentation.distanceText(this.distance(sector), this.scanning)}`)
      .width(90).fontSize(11).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
      .fontColor(this.ribbonColor(this.distance(sector))).maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .shadow({ radius: 2, color: '#DD000000', offsetY: 1 })
      .position({ x: this.captionX(sector), y: this.captionY(sector) })
      .animation({ duration: 320, curve: Curve.EaseInOut })
      .transition(TransitionEffect.OPACITY.animation({ duration: 280, curve: Curve.EaseOut }))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach([0, 1, 3], (sector: number) => {
          if (this.approaching(this.distance(sector))) {
            Column()
              .width(this.ringWidth).height(this.ringHeight())
              .linearGradient({ direction: sector === 0 ? GradientDirection.Right : GradientDirection.Bottom,
                colors: this.ribbonGradient(this.distance(sector)) })
              .clipShape(new PathShape({ commands: this.ribbonPath(sector) }))
              .opacity(this.ribbonOpacity(this.distance(sector)))
              .animation({ duration: 320, curve: Curve.EaseInOut })
              .transition(TransitionEffect.OPACITY.animation({ duration: 280, curve: Curve.EaseOut }))
          }
        }, (sector: number) => `${sector}`)
      }
      .width(this.ringWidth).height(this.ringHeight())
      .position({ x: this.ringLeft(), y: this.ringTop() })
      if (this.approaching(this.frontMm)) {
        this.DistanceCaption('前', 0)
      }
      if (this.approaching(this.leftMm)) {
        this.DistanceCaption('左', 3)
      }
      if (this.approaching(this.rightMm)) {
        this.DistanceCaption('右', 1)
      }
    }
    .width(this.pictureWidth).height(this.pictureHeight)
    .hitTestBehavior(HitTestMode.None)
  }
}
