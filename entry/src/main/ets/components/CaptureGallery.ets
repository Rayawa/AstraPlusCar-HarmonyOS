import { HdsNavDestination, ScrollEffectType } from '@kit.UIDesignKit';
import { curves, LengthMetrics, promptAction } from '@kit.ArkUI';
import { CaptureItem } from '../services/CaptureStore';
import { Haptics } from '../services/Haptics';

@Component
export struct CaptureGallery {
  @Prop items: CaptureItem[] = [];
  onRemove: (name: string) => void = () => {};
  onDownload: (item: CaptureItem) => void = () => {};
  @State private previewItem: CaptureItem | null = null;
  @State private showPreview: boolean = false;
  @State private galleryAnimStep1: number = 0;
  @State private galleryAnimStep2: number = 0;
  @State private previewAnimStep1: number = 0;
  @State private previewAnimStep2: number = 0;
  private galleryTimers: number[] = [];
  private previewTimers: number[] = [];

  aboutToDisappear(): void {
    this.clearTimers(this.galleryTimers);
    this.clearTimers(this.previewTimers);
  }

  private clearTimers(timers: number[]): void {
    timers.forEach((timer: number) => clearTimeout(timer));
    timers.length = 0;
  }

  private startGalleryEntrance(): void {
    this.clearTimers(this.galleryTimers);
    this.galleryAnimStep1 = 0;
    this.galleryAnimStep2 = 0;
    const curve = curves.springMotion(0.35, 0.75);
    this.galleryTimers.push(setTimeout(() => this.getUIContext().animateTo({ duration: 500, curve: curve },
      () => this.galleryAnimStep1 = 1), 80));
    this.galleryTimers.push(setTimeout(() => this.getUIContext().animateTo({ duration: 500, curve: curve },
      () => this.galleryAnimStep2 = 1), 205));
  }

  private startPreviewEntrance(): void {
    this.clearTimers(this.previewTimers);
    this.previewAnimStep1 = 0;
    this.previewAnimStep2 = 0;
    const curve = curves.springMotion(0.35, 0.75);
    this.previewTimers.push(setTimeout(() => this.getUIContext().animateTo({ duration: 500, curve: curve },
      () => this.previewAnimStep1 = 1), 80));
    this.previewTimers.push(setTimeout(() => this.getUIContext().animateTo({ duration: 500, curve: curve },
      () => this.previewAnimStep2 = 1), 205));
  }

  private stopPreviewEntrance(): void {
    this.clearTimers(this.previewTimers);
    this.previewAnimStep1 = 0;
    this.previewAnimStep2 = 0;
  }

  private async showGridActions(item: CaptureItem): Promise<void> {
    Haptics.hard();
    try {
      const choice = await promptAction.showActionMenu({
        title: '截图操作', buttons: [
          { text: '下载到系统相册', color: $r('app.color.text_primary') },
          { text: '删除截图', color: $r('app.color.danger') }
        ]
      });
      if (choice.index === 0) { this.onDownload(item); }
      if (choice.index === 1) { this.onRemove(item.name); }
    } catch (error) { /* Dismissed without selecting an action. */ }
  }

  @Builder
  private CaptureActions(item: CaptureItem) {
    Column({ space: 2 }) {
      Button('下载到系统相册').width(190).height(44)
        .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.surface_background'))
        .onClick(() => { Haptics.hard(); this.onDownload(item); })
      Button('删除截图').width(190).height(44)
        .fontColor($r('app.color.danger')).backgroundColor($r('app.color.surface_background'))
        .onClick(() => {
          Haptics.hard();
          this.showPreview = false;
          this.previewItem = null;
          this.onRemove(item.name);
        })
    }.padding(8).backgroundColor($r('app.color.surface_background')).borderRadius(14)
  }

  @Builder
  private PreviewSheet() {
    Column({ space: 12 }) {
      if (this.previewItem !== null) {
        Image(this.previewItem.uri).width('100%').layoutWeight(1).objectFit(ImageFit.Contain)
          .bindContextMenu(this.CaptureActions(this.previewItem), ResponseType.LongPress)
          .opacity(this.previewAnimStep1).translate({ y: this.previewAnimStep1 ? 0 : 20 })
        Text(this.previewItem.time).fontSize(13).fontColor($r('app.color.text_secondary'))
          .opacity(this.previewAnimStep2).translate({ y: this.previewAnimStep2 ? 0 : 20 })
        Text('长按图片可下载或删除').fontSize(11).fontColor($r('app.color.text_secondary'))
          .opacity(this.previewAnimStep2).translate({ y: this.previewAnimStep2 ? 0 : 20 })
      }
    }.width('100%').height('100%').padding(16).backgroundColor($r('app.color.gallery_background'))
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.items.length === 0) {
          Column({ space: 8 }) {
            Text('还没有截图').fontSize(21).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            Text('在驾驶页点击监看画面即可保存。').fontSize(13).fontColor($r('app.color.text_secondary'))
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
            .opacity(this.galleryAnimStep1).translate({ y: this.galleryAnimStep1 ? 0 : 20 })
        } else {
          Text('点击放大 · 长按下载或删除').width('100%').fontSize(11)
            .fontColor($r('app.color.text_secondary')).margin({ bottom: 8 })
            .opacity(this.galleryAnimStep1).translate({ y: this.galleryAnimStep1 ? 0 : 20 })
          Grid() {
            ForEach(this.items, (item: CaptureItem) => {
              GridItem() {
                Column({ space: 6 }) {
                  Image(item.uri).width('100%').height(130).objectFit(ImageFit.Cover)
                    .borderRadius(12)
                  Text(item.time).fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
                }
                .padding(8).backgroundColor($r('app.color.surface_background')).borderRadius(16)
                .shadow({ radius: 8, color: '#18000000', offsetY: 2 })
                .onClick(() => { Haptics.hard(); this.previewItem = item; this.showPreview = true; })
              }
              .priorityGesture(LongPressGesture().onAction(() => this.showGridActions(item)))
            }, (item: CaptureItem) => item.name)
          }
          .columnsTemplate('1fr 1fr').columnsGap(10).rowsGap(10)
          .width('100%').layoutWeight(1).scrollBar(BarState.Off)
          .opacity(this.galleryAnimStep2).translate({ y: this.galleryAnimStep2 ? 0 : 20 })
        }
      }
      .width('100%').height('100%').padding({ left: 16, right: 16, bottom: 16 })
      .backgroundColor($r('app.color.gallery_background'))
      .bindSheet($$this.showPreview, this.PreviewSheet(), {
        height: SheetSize.LARGE, showClose: true, title: { title: '截图预览' },
        backgroundColor: $r('app.color.gallery_background'),
        onAppear: () => this.startPreviewEntrance(),
        onWillDismiss: (action: DismissSheetAction) => { Haptics.hard(); action.dismiss(); },
        onDisappear: () => { this.stopPreviewEntrance(); this.showPreview = false; this.previewItem = null; }
      })
    }
    .onShown(() => this.startGalleryEntrance())
    .onWillDisappear(() => Haptics.hard())
    .height(LayoutPolicy.matchParent)
    .background($r('app.color.gallery_background'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .titleBar({
      enableComponentSafeArea: true,
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0), blurEffectiveEndOffset: LengthMetrics.vp(20) },
        originalStyle: { backgroundStyle: { backgroundColor: $r('app.color.gallery_background') },
          contentStyle: { titleStyle: { mainTitleColor: $r('app.color.text_primary') },
            backIconStyle: { backgroundColor: $r('app.color.input_background'),
              iconColor: $r('app.color.text_primary') } } },
        scrollEffectStyle: { backgroundStyle: { backgroundColor: $r('app.color.gallery_background') },
          contentStyle: { titleStyle: { mainTitleColor: $r('app.color.text_primary') },
            backIconStyle: { backgroundColor: $r('app.color.input_background'),
              iconColor: $r('app.color.text_primary') } } }
      },
      content: { title: { mainTitle: '截图图库' }, backIcon: { label: '返回' } }
    })
  }
}
