import { hdsEffect } from '@kit.UIDesignKit';

/** Mounted only during voice mode; the full-window effect never intercepts controls. */
@Component
export struct VoiceModeGlow {
  private controller: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();

  aboutToDisappear(): void { this.controller.pause(); }

  build() {
    Stack() {}
      .width('100%').height('100%').borderRadius(24)
      .visualEffect(new hdsEffect.HdsEffectBuilder().shaderEffect({
        effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
        animation: { duration: 4000, iterations: -1, autoPlay: true },
        controller: this.controller,
        params: {
          firstEdgeFlowLight: { startPos: 0, endPos: 1, color: '#1AD0F1' },
          secondEdgeFlowLight: { startPos: 0.5, endPos: 1.5, color: '#FFA4E5' }
        }
      }).buildEffect())
      .clip(true).hitTestBehavior(HitTestMode.None)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.ALL])
  }
}
