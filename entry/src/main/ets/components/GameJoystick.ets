import { hdsEffect } from '@kit.UIDesignKit';
import { AppColors } from '../constants/AppConstants';
import { CarAction } from '../models/CarModels';

@Component
export struct GameJoystick {
  @Prop connected: boolean = false;
  @Prop activeAction: CarAction = CarAction.NONE;
  onMoveStart: (action: CarAction) => void = () => {};
  onMoveEnd: (action: CarAction) => void = () => {};

  @State knobX: number = 0;
  @State knobY: number = 0;
  @State gestureAction: CarAction = CarAction.NONE;

  private readonly travel: number = 48;
  private readonly deadZone: number = 12;

  private updateJoystick(event: GestureEvent): void {
    if (!this.connected) {
      return;
    }
    let x = event.offsetX;
    let y = event.offsetY;
    const distance = Math.sqrt(x * x + y * y);
    if (distance > this.travel) {
      const ratio = this.travel / distance;
      x *= ratio;
      y *= ratio;
    }
    this.knobX = x;
    this.knobY = y;
    this.switchAction(this.resolveAction(x, y));
  }

  private resolveAction(x: number, y: number): CarAction {
    const absoluteX = Math.abs(x);
    const absoluteY = Math.abs(y);
    if (Math.sqrt(x * x + y * y) < this.deadZone) {
      return CarAction.NONE;
    }
    if (absoluteX > absoluteY * 1.35) {
      return x < 0 ? CarAction.SHIFT_LEFT : CarAction.SHIFT_RIGHT;
    }
    if (y > 0) {
      return CarAction.BACKWARD;
    }
    if (absoluteX < absoluteY * 0.42) {
      return CarAction.FORWARD;
    }
    return x < 0 ? CarAction.LEFT : CarAction.RIGHT;
  }

  private switchAction(next: CarAction): void {
    if (next === this.gestureAction) {
      return;
    }
    const previous = this.gestureAction;
    this.gestureAction = next;
    if (previous !== CarAction.NONE) {
      this.onMoveEnd(previous);
    }
    if (next !== CarAction.NONE) {
      this.onMoveStart(next);
    }
  }

  private releaseJoystick(): void {
    const previous = this.gestureAction;
    this.gestureAction = CarAction.NONE;
    this.knobX = 0;
    this.knobY = 0;
    if (previous !== CarAction.NONE) {
      this.onMoveEnd(previous);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(150)
        .height(150)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .border({ width: 0.5, color: $r('sys.color.toast_border_color') })
        .shadow({ radius: 10, color: '#16000000', offsetX: 0, offsetY: 4 })
      Text('前进')
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
        .align(Alignment.Top)
        .margin({ top: 9 })
      Text('后退')
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
        .align(Alignment.Bottom)
        .margin({ bottom: 9 })
      Text('平移')
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
        .align(Alignment.Start)
        .margin({ left: 7 })
      Text('平移')
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
        .align(Alignment.End)
        .margin({ right: 7 })
      Circle()
        .width(68)
        .height(68)
        .backgroundColor(this.activeAction === CarAction.NONE ? '#240A84FF' : AppColors.PRIMARY_BLUE)
        .border({ width: 1.5, color: this.activeAction === CarAction.NONE ? '#660A84FF' : '#D8EEFF' })
        .translate({ x: this.knobX, y: this.knobY })
        .scale({
          x: this.activeAction === CarAction.NONE ? 1 : 0.95,
          y: this.activeAction === CarAction.NONE ? 1 : 0.95
        })
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            sourceType: this.activeAction === CarAction.NONE ? hdsEffect.PointLightSourceType.NONE :
              hdsEffect.PointLightSourceType.BRIGHT,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
            options: { color: '#D8EEFF', intensity: 10, height: 120 }
          })
          .buildEffect())
      Circle()
        .width(16)
        .height(16)
        .backgroundColor(this.activeAction === CarAction.NONE ? '#660A84FF' : Color.White)
        .translate({ x: this.knobX, y: this.knobY })
    }
    .width(168)
    .height(168)
    .opacity(this.connected ? 1 : 0.45)
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.All, distance: 1 })
        .onActionUpdate((event: GestureEvent) => this.updateJoystick(event))
        .onActionEnd(() => this.releaseJoystick())
        .onActionCancel(() => this.releaseJoystick())
    )
  }
}
