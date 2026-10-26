import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { speechRecognizer } from '@kit.CoreSpeechKit';

export interface VoiceRecognitionCallbacks {
  onListening: () => void;
  onText: (text: string, final: boolean) => void;
  onError: (message: string) => void;
}

/** Device-local Chinese ASR. The engine owns microphone capture in recognitionMode 0. */
export class VoiceRecognition {
  private engine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private generation: number = 0;
  private serial: number = 0;
  private session: string = '';
  private timer: number = -1;
  private restartTimer: number = -1;
  private lastFinal: string = '';
  private callbacks: VoiceRecognitionCallbacks | null = null;
  private readyResolve: (() => void) | null = null;
  private readyReject: ((error: Error) => void) | null = null;

  async start(context: common.UIAbilityContext, callbacks: VoiceRecognitionCallbacks): Promise<void> {
    this.stop();
    const current = this.generation;
    if (!canIUse('SystemCapability.AI.SpeechRecognizer')) { throw new Error('当前设备不支持语音识别'); }
    const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context,
      ['ohos.permission.MICROPHONE']);
    if (current !== this.generation) { return; }
    if (permission.authResults.length !== 1 || permission.authResults[0] !== 0) {
      throw new Error('请允许麦克风权限后开启语音模式');
    }
    const engine = await speechRecognizer.createEngine({ language: 'zh-CN', online: 1,
      extraParams: { locate: 'CN', recognizerMode: 'long',
        sysGeneralLexicon: ['前进', '直行', '往前走', '倒车', '后退', '左转', '右转', '左拐', '右拐',
          '原地左转', '原地右转', '左旋转', '右旋转', '左平移', '右平移', '停车', '停下来', '急停',
          '截图', '拍张照', '加速', '减速', '设置速度', '然后', '接着', '退出语音'] } });
    if (current !== this.generation) { engine.shutdown(); return; }
    this.engine = engine;
    this.callbacks = callbacks;
    const valid = (id: string): boolean => current === this.generation && id === this.session;
    engine.setListener({
      onStart: (id: string, message: string) => {
        if (!valid(id)) { return; }
        this.clearTimer();
        this.timer = setTimeout(() => this.fail('语音识别无响应，请重新开启', current, callbacks), 65000);
        callbacks.onListening();
        if (this.readyResolve !== null) { this.readyResolve(); }
        this.readyResolve = null;
        this.readyReject = null;
      },
      onEvent: (id: string, code: number, message: string) => {
        if (valid(id) && code === 1) { this.lastFinal = ''; }
      },
      onResult: (id: string, result: speechRecognizer.SpeechRecognitionResult) => {
        if (!valid(id) || result.result.trim().length === 0) { return; }
        if (!result.isFinal) { this.lastFinal = ''; }
        if (result.isFinal && this.lastFinal === result.result) { return; }
        if (result.isFinal) { this.lastFinal = result.result; }
        callbacks.onText(result.result, result.isFinal);
      },
      onComplete: (id: string, message: string) => {
        if (!valid(id)) { return; }
        this.clearTimer();
        this.session = '';
        this.restartTimer = setTimeout(() => {
          this.restartTimer = -1;
          if (current === this.generation) { this.listen(current, callbacks); }
        }, 150);
      },
      onError: (id: string, code: number, message: string) => {
        if (valid(id)) { this.fail(`语音识别失败（${code}），请重新开启`, current, callbacks); }
      }
    });
    const ready = new Promise<void>((resolve, reject) => { this.readyResolve = resolve; this.readyReject = reject; });
    this.listen(current, callbacks);
    await ready;
  }

  private listen(current: number, callbacks: VoiceRecognitionCallbacks): void {
    if (current !== this.generation || this.engine === null) { return; }
    this.session = `voice-${Date.now()}-${++this.serial}`;
    this.lastFinal = '';
    this.clearTimer();
    this.timer = setTimeout(() => this.fail('语音启动超时，请重新开启', current, callbacks), 8000);
    try {
      this.engine.startListening({ sessionId: this.session,
        audioInfo: { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 },
        extraParams: { recognitionMode: 0, maxAudioDuration: 60000 } });
    } catch (error) { this.fail((error as Error).message, current, callbacks); }
  }

  private fail(message: string, current: number, callbacks: VoiceRecognitionCallbacks): void {
    if (current !== this.generation) { return; }
    this.stop();
    callbacks.onError(message);
  }

  private clearTimer(): void {
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
  }

  // A touch stop invalidates the whole current clause, including a delayed final result.
  discardPending(): void {
    if (this.engine === null || this.callbacks === null) { return; }
    const session = this.session;
    this.session = '';
    this.clearTimer();
    if (this.restartTimer >= 0) { clearTimeout(this.restartTimer); }
    try { if (session.length > 0) { this.engine.cancel(session); } }
    catch (error) { this.fail((error as Error).message, this.generation, this.callbacks); return; }
    const current = this.generation;
    const callbacks = this.callbacks;
    this.restartTimer = setTimeout(() => {
      this.restartTimer = -1;
      if (current === this.generation) { this.listen(current, callbacks); }
    }, 150);
  }

  stop(): void {
    ++this.generation;
    this.clearTimer();
    if (this.restartTimer >= 0) { clearTimeout(this.restartTimer); this.restartTimer = -1; }
    const engine = this.engine;
    const session = this.session;
    this.engine = null;
    this.callbacks = null;
    this.session = '';
    if (this.readyReject !== null) { this.readyReject(new Error('语音已取消')); }
    this.readyResolve = null;
    this.readyReject = null;
    if (engine !== null) {
      try { if (session.length > 0) { engine.cancel(session); } } catch (error) { /* Release below. */ }
      try { engine.shutdown(); } catch (error) { /* Already released by the system. */ }
    }
  }
}
