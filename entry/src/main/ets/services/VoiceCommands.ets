export interface VoiceCommand {
  kind: string;
  label: string;
  key: string;
  value: number;
}

export interface VoicePlan {
  commands: VoiceCommand[];
  error: string;
}

interface VoiceAlias {
  words: string[];
  kind: string;
  label: string;
  key: string;
  value: number;
}

interface VoiceToken {
  command: VoiceCommand;
  remaining: string;
  error: string;
}

/** A local command grammar: consume the entire utterance before executing any step. */
export class VoiceCommands {
  static readonly MAX_STEPS: number = 8;
  static readonly MAX_MOTION_MS: number = 30000;

  private static readonly aliases: VoiceAlias[] = [
    { words: ['紧急停车', '紧急停止', '马上停车', '立即停车', '急停'],
      kind: 'stop', label: '急停', key: 'emergency', value: 0 },
    { words: ['停止运动', '停止行驶', '停止移动', '停下来', '停车', '停下', '停止', '停住', '刹车', '停'],
      kind: 'stop', label: '停车', key: '', value: 0 },
    { words: ['退出语音模式', '关闭语音模式', '退出语音', '关闭语音', '退出声控', '关闭声控'],
      kind: 'exit', label: '退出语音模式', key: '', value: 0 },
    { words: ['拍一张照片', '拍张照片', '拍一张照', '拍张照', '拍个照', '截一张图', '截个图', '截图', '拍照', '截屏'],
      kind: 'capture', label: '截图', key: '', value: 0 },
    { words: ['加快一点', '快一点', '快点', '加速'], kind: 'speedStep', label: '加速', key: '', value: 20 },
    { words: ['减慢一点', '慢一点', '慢点', '减速'], kind: 'speedStep', label: '减速', key: '', value: -20 },
    { words: ['原地向左旋转', '原地往左旋转', '原地左旋转', '原地向左转', '原地往左转', '原地左转',
      '向左旋转', '往左旋转', '左旋转', '左旋'], kind: 'move', label: '左旋转', key: 'q', value: 2000 },
    { words: ['原地向右旋转', '原地往右旋转', '原地右旋转', '原地向右转', '原地往右转', '原地右转',
      '向右旋转', '往右旋转', '右旋转', '右旋'], kind: 'move', label: '右旋转', key: 'e', value: 2000 },
    { words: ['向左平移', '往左平移', '向左横移', '往左横移', '左平移', '左横移', '往左挪', '向左挪'],
      kind: 'move', label: '左平移', key: 'left', value: 2000 },
    { words: ['向右平移', '往右平移', '向右横移', '往右横移', '右平移', '右横移', '往右挪', '向右挪'],
      kind: 'move', label: '右平移', key: 'right', value: 2000 },
    { words: ['往前行驶', '向前行驶', '往前走', '向前走', '往前开', '向前开', '走直线', '往前直行',
      '向前直行', '直行', '前行', '前进', '往前', '向前'], kind: 'move', label: '前进', key: 'w', value: 2000 },
    { words: ['往后行驶', '向后行驶', '往后退', '向后退', '往后走', '向后走', '往后开', '向后开',
      '后退', '倒退', '倒车', '往后', '向后'], kind: 'move', label: '后退', key: 's', value: 2000 },
    { words: ['往左拐弯', '向左拐弯', '往左转弯', '向左转弯', '往左转', '向左转', '往左拐', '向左拐',
      '左转弯', '左拐弯', '左转', '左拐'], kind: 'move', label: '左转', key: 'a', value: 2000 },
    { words: ['往右拐弯', '向右拐弯', '往右转弯', '向右转弯', '往右转', '向右转', '往右拐', '向右拐',
      '右转弯', '右拐弯', '右转', '右拐'], kind: 'move', label: '右转', key: 'd', value: 2000 }
  ];

  static parse(text: string): VoiceCommand | null {
    const plan = VoiceCommands.parsePlan(text);
    return plan.error.length === 0 && plan.commands.length === 1 ? plan.commands[0] : null;
  }

  static isContinuation(text: string): boolean {
    return /^(?:(?:请你|请|小车)[\s，,]*)*(?:然后|接着|之后|随后|再)/.test(text.trim());
  }

  static parsePlan(text: string): VoicePlan {
    let remaining = text.replace(/\s/g, '').replace(/[，。！？、,!?；;]/g, '|').replace(/\.(?![0-9])/g, '|');
    if (remaining.length > 240) { return VoiceCommands.invalid('指令过长，请分组说'); }
    if (/不要|别|不许|不能|无需|不需要|不想|如果|假如|要是|除非|一边|同时|或者|还是|也许|可能/.test(remaining)) {
      return VoiceCommands.invalid('包含否定、条件或不确定表达，请直接说要执行的动作');
    }
    const commands: VoiceCommand[] = [];
    let motionMs: number = 0;
    while (remaining.length > 0) {
      // Punctuation and sequencing words are optional, including between adjacent commands.
      const beforePrefix = remaining;
      remaining = VoiceCommands.trimPrefix(remaining);
      if (remaining.length === 0) {
        if (/[^|]/.test(beforePrefix)) { return VoiceCommands.invalid('连接词之后缺少指令，整组未执行'); }
        break;
      }
      const token = VoiceCommands.token(remaining);
      if (token === null) { return VoiceCommands.invalid(`未理解“${remaining.substring(0, 16)}”，整组未执行`); }
      if (token.error.length > 0) { return VoiceCommands.invalid(token.error); }
      commands.push(token.command);
      if (token.command.kind === 'move') { motionMs += token.command.value; }
      if (commands.length > VoiceCommands.MAX_STEPS) { return VoiceCommands.invalid('每组最多 8 条指令'); }
      if (motionMs > VoiceCommands.MAX_MOTION_MS) { return VoiceCommands.invalid('每组运动总时长最多 30 秒'); }
      remaining = token.remaining.replace(/^(?:一下|吧|好吗)/, '');
    }
    if (commands.length === 0) { return VoiceCommands.invalid('请说出控制指令'); }
    const emergency = commands.find((command: VoiceCommand) => command.key === 'emergency');
    if (emergency !== undefined) { return { commands: [emergency], error: '' }; }
    let stopped: boolean = false;
    for (let i = 0; i < commands.length; i++) {
      if (stopped && (commands[i].kind === 'move' || commands[i].kind === 'speed' || commands[i].kind === 'speedStep')) {
        return VoiceCommands.invalid('停车后的运动或调速请重新下达指令');
      }
      if (commands[i].kind === 'stop') { stopped = true; }
      if (commands[i].kind === 'exit' && i !== commands.length - 1) {
        return VoiceCommands.invalid('退出语音必须放在最后');
      }
    }
    return { commands: commands, error: '' };
  }

  private static invalid(error: string): VoicePlan { return { commands: [], error: error }; }

  private static trimPrefix(text: string): string {
    let result = text;
    const prefix = /^(?:\|+|然后再|接着再|之后再|随后再|然后|接着|之后|随后|再|先|后(?!退)|并且|并|和|请你|请|麻烦你|麻烦|帮我|给我|让小车|让车|小车|车子)/;
    while (prefix.test(result)) { result = result.replace(prefix, ''); }
    return result;
  }

  private static token(text: string): VoiceToken | null {
    const number = '([0-9]+(?:\\.[0-9]+)?|[零〇一二两三四五六七八九十百点半]+)';
    const speed = new RegExp('^(?:把速度设置为|把速度设置成|把速度调到|把速度调成|把速度设为|将速度调到|将速度设为|速度设置为|速度设置成|速度调到|速度调成|速度调为|速度设为|速度改为|速度改到|设置速度|设定速度|速度)' + number).exec(text);
    const drivingSpeed = new RegExp('^(?:以|用)' + number + '(?:的)?速度').exec(text);
    const speedMatch = speed === null ? drivingSpeed : speed;
    if (speedMatch !== null) {
      const value = VoiceCommands.number(speedMatch[1]);
      return { command: { kind: 'speed', label: `速度 ${value}`, key: '', value: value },
        remaining: text.substring(speedMatch[0].length),
        error: Number.isInteger(value) && value >= 0 && value <= 100 ? '' : '速度必须是 0–100 的整数，整组未执行' };
    }
    for (const alias of VoiceCommands.aliases) {
      for (const word of alias.words) {
        if (!text.startsWith(word)) { continue; }
        let remaining = text.substring(word.length);
        let value = alias.value;
        if (alias.kind === 'move') {
          const duration = new RegExp('^(?:持续|保持|行驶)?' + number + '(?:秒钟|秒)(半)?').exec(remaining);
          if (duration !== null) {
            value = (VoiceCommands.number(duration[1]) + (duration[2] === undefined ? 0 : 0.5)) * 1000;
            remaining = remaining.substring(duration[0].length);
            if (value < 500 || value > 10000) {
              return { command: { kind: alias.kind, label: alias.label, key: alias.key, value: value },
                remaining: remaining, error: '每个运动动作需在 0.5–10 秒内，整组未执行' };
            }
          }
        }
        const label = alias.kind === 'move' ? `${alias.label} ${value / 1000} 秒` : alias.label;
        return { command: { kind: alias.kind, label: label, key: alias.key, value: value },
          remaining: remaining, error: '' };
      }
    }
    return null;
  }

  private static number(text: string): number {
    if (/^[0-9]+(?:\.[0-9]+)?$/.test(text)) { return Number(text); }
    if (text === '半') { return 0.5; }
    if (text === '一百' || text === '百') { return 100; }
    const digits = '零一二三四五六七八九';
    const chinese = text.replace(/两/g, '二').replace(/〇/g, '零');
    const fraction = chinese.split('点');
    if (fraction.length === 2 && fraction[1].length > 0) {
      const whole = VoiceCommands.number(fraction[0]);
      let decimal = '';
      for (const digit of fraction[1]) {
        const index = digits.indexOf(digit);
        if (index < 0) { return -1; }
        decimal += index.toString();
      }
      return whole >= 0 ? whole + Number(`0.${decimal}`) : -1;
    }
    if (chinese.length === 1 && digits.includes(chinese)) { return digits.indexOf(chinese); }
    const parts = chinese.split('十');
    if (parts.length !== 2 || parts[0].length > 1 || parts[1].length > 1) { return -1; }
    const tens = parts[0].length === 0 ? 1 : digits.indexOf(parts[0]);
    const units = parts[1].length === 0 ? 0 : digits.indexOf(parts[1]);
    return tens > 0 && units >= 0 ? tens * 10 + units : -1;
  }
}
