@Component
export struct VoiceControlPanel {
  @Prop listening: boolean = false;
  @Prop transcript: string = '';
  @Prop command: string = '';
  @Prop plan: string = '';
  @Prop compact: boolean = false;
  @Prop captureBusy: boolean = false;
  onCapture: () => void = () => {};

  build() {
    Column({ space: this.compact ? 5 : 10 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.mic')).fontSize(this.compact ? 16 : 22).fontColor(['#62E6A7'])
        Text(this.listening ? '语音控制 · 正在聆听' : '语音控制 · 启动中…')
          .fontSize(this.compact ? 12 : 15).fontWeight(FontWeight.Bold)
          .fontColor(this.compact ? Color.White : $r('app.color.text_primary'))
        Blank()
        if (!this.compact) {
        Button(this.captureBusy ? '保存中' : '截图').height(32).fontSize(12)
          .fontColor(this.compact ? Color.White : $r('app.color.text_primary'))
          .backgroundColor(this.compact ? '#440A84FF' : $r('app.color.input_background'))
          .enabled(!this.captureBusy).onClick(() => this.onCapture())
        }
      }.width('100%')
      Column({ space: 4 }) {
        Text('识别到的语音').fontSize(10).fontColor(this.compact ? '#B8C8D2' : $r('app.color.text_secondary'))
        Text(this.transcript.length > 0 ? this.transcript : '请说出指令…')
          .fontSize(this.compact ? 13 : 17).fontWeight(FontWeight.Medium)
          .fontColor(this.compact ? Color.White : $r('app.color.text_primary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').alignItems(HorizontalAlign.Start)
      if (this.plan.length > 0) {
        Column({ space: 4 }) {
          Text('理解后的步骤').fontSize(10)
            .fontColor(this.compact ? '#B8C8D2' : $r('app.color.text_secondary'))
          Text(this.plan).fontSize(this.compact ? 10 : 12)
            .fontColor(this.compact ? Color.White : $r('app.color.text_primary'))
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      Column({ space: 4 }) {
        Text('执行指令').fontSize(10).fontColor(this.compact ? '#B8C8D2' : $r('app.color.text_secondary'))
        Text(this.command.length > 0 ? this.command : '等待指令')
          .fontSize(this.compact ? 12 : 14).fontWeight(FontWeight.Medium).fontColor('#62E6A7')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').alignItems(HorizontalAlign.Start)
      Text(this.compact ? '例：速度100前进三秒再右转；直行 / 往前走均可' :
        '例：速度100，前进三秒，再右转\n也可说：直行 · 往前走 · 倒车 · 右拐 · 原地左转 · 拍张照 · 停下来')
        .fontSize(this.compact ? 9 : 11).fontColor(this.compact ? '#B8C8D2' : $r('app.color.text_secondary'))
        .width('100%')
      Text('动作默认 2 秒（0.5–10 秒）；每组≤8步，运动≤30秒；停车取消整组')
        .fontSize(this.compact ? 9 : 10).fontColor(this.compact ? '#B8C8D2' : $r('app.color.text_secondary'))
        .width('100%').maxLines(2)
    }
    .width('100%').padding(this.compact ? 12 : 16).borderRadius(18)
    .backgroundColor(this.compact ? '#B30B1B28' : $r('app.color.panel_background'))
    .border({ width: 1, color: '#7762E6A7' })
  }
}
