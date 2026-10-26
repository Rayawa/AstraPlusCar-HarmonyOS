// Offline checks of actual ArkTS methods with simulated ASR, permissions and vehicle responses.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARKTS_TYPESCRIPT ||
  '/Users/raychen/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
};
const tick = () => new Promise(resolve => setImmediate(resolve));
function clock() {
  let serial = 0, now = 0;
  const pending = new Map();
  return {
    setTimeout: (fn, ms) => { pending.set(++serial, { fn, at: now + ms }); return serial; },
    clearTimeout: id => pending.delete(id),
    setInterval: () => ++serial, clearInterval: () => {},
    advance(ms) {
      now += ms;
      for (const [id, task] of [...pending]) {
        if (task.at <= now) { pending.delete(id); task.fn(); }
      }
    },
    get count() { return pending.size; }
  };
}
const Empty = class {};
function load(file, name, modules = {}, globals = {}) {
  let source = fs.readFileSync(path.join(root, file), 'utf8');
  if (name === 'Index') {
    source = source.split('  @Builder')[0].replace(/@Entry\s*|@Component\s*|@State\s*/g, '')
      .replace('struct Index', 'class Index') + '\n}';
  }
  const output = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const context = { exports: {}, console, Date, Math, Number, String, Map, Promise,
    NavPathStack: Empty, Scroller: Empty, canIUse: () => true,
    require: id => modules[id] || new Proxy({}, { get: () => Empty }), ...globals };
  vm.runInNewContext(output + `\nexports.TestClass = ${name};`, context);
  return context.exports.TestClass;
}
const Commands = load('services/VoiceCommands.ets', 'VoiceCommands');
function testParser() {
  const mapping = { 前进: 'w', 向前: 'w', 后退: 's', 向后: 's', 左转: 'a', 右转: 'd',
    左旋转: 'q', 右旋转: 'e', 左平移: 'left', 右平移: 'right' };
  for (const [text, key] of Object.entries(mapping)) {
    assert.equal(Commands.parse(text).key, key);
    assert.equal(Commands.parse(text).value, 2000);
  }
  assert.equal(Commands.parse('请小车前进三秒。').value, 3000);
  assert.equal(Commands.parse('前进0.5秒.').value, 500, 'decimal duration is preserved');
  assert.equal(Commands.parse('前进十秒').value, 10000);
  for (const [text, value] of [['速度五十', 50], ['设置速度一百', 100], ['速度调到60', 60], ['速度零', 0]]) {
    assert.equal(Commands.parse(text).value, value);
  }
  for (const text of ['不要前进', '别停车', '如果前进', '前进然后后退', '前进停车', '前进0秒',
    '前进11秒', '前进0.1秒', '速度101', '前进很久', '这张截图不错']) {
    assert.equal(Commands.parse(text), null, `ambiguous or invalid text must not execute: ${text}`);
  }
  assert.equal(Commands.parse('停下！').kind, 'stop');
  assert.equal(Commands.parse('退出语音模式').kind, 'exit');
  assert.equal(Commands.parse('拍照').kind, 'capture');
  assert.equal(Commands.parse('帮我前进好吗').key, 'w');
  for (const word of ['直行', '前行', '走直线', '往前走', '向前开', '请直行一下']) {
    assert.equal(Commands.parse(word).key, 'w', word);
  }
  for (const [word, key] of [['倒车', 's'], ['倒退', 's'], ['右拐', 'd'], ['往左转弯', 'a'],
    ['原地左转', 'q'], ['往右旋转', 'e'], ['往左挪', 'left'], ['向右横移', 'right']]) {
    assert.equal(Commands.parse(word).key, key, word);
  }
  for (const [word, value] of [['前进半秒', 500], ['直行两点五秒', 2500], ['倒车三秒半', 3500]]) {
    assert.equal(Commands.parse(word).value, value);
  }
  for (const text of ['速度100前进三秒再右转', '先把速度设置为一百，然后直行三秒钟，接着向右拐',
    '以100的速度往前走三秒后右转']) {
    const plan = Commands.parsePlan(text);
    assert.equal(plan.error, '', text);
    assert.deepEqual(Array.from(plan.commands, command => [command.kind, command.key, command.value]),
      [['speed', '', 100], ['move', 'w', 3000], ['move', 'd', 2000]], text);
  }
  assert.equal(Commands.parsePlan('前进然后后退').commands.length, 2);
  assert.equal(Commands.parsePlan('前进停车').commands.length, 2);
  assert.equal(Commands.parsePlan('停下来拍张照').commands.length, 2);
  assert.equal(Commands.parsePlan('直行三秒再急停').commands.length, 1, 'emergency stop preempts the whole plan');
  for (const text of ['速度101前进三秒', '速度100前进三秒再飞起来', '前进三秒再', '直行不要右转',
    '如果前进三秒然后右转', '直行或者后退', '直行同时右转', '前进0.1秒再右转', '前进11秒再右转',
    '停车再前进', '退出语音再前进', '前进十秒后退十秒左转十秒右转一秒', '截图'.repeat(9)]) {
    const plan = Commands.parsePlan(text);
    assert.ok(plan.error.length > 0, text);
    assert.equal(plan.commands.length, 0, `${text}: rejects the entire plan before execution`);
  }
}
function recognizer(options = {}) {
  const timers = clock();
  const events = [];
  let listener, latestId;
  const engine = {
    setListener(value) { listener = value; },
    startListening(params) {
      latestId = params.sessionId;
      events.push(['listen', params]);
      if (!options.noStart) listener.onStart(latestId, 'ready');
    },
    cancel(id) { events.push(['cancel', id]); },
    shutdown() { events.push(['shutdown']); }
  };
  const Service = load('services/VoiceRecognition.ets', 'VoiceRecognition', {
    '@kit.AbilityKit': { abilityAccessCtrl: { createAtManager: () => ({
      requestPermissionsFromUser: () => options.permission || Promise.resolve({ authResults: [0] })
    }) } },
    '@kit.CoreSpeechKit': { speechRecognizer: {
      createEngine: () => options.opening || Promise.resolve(engine)
    } }
  }, { ...timers, canIUse: () => options.supported !== false });
  const service = new Service();
  const heard = [], errors = [];
  let listening = 0;
  const callbacks = { onListening: () => listening++,
    onText: (text, final) => heard.push([text, final]), onError: error => errors.push(error) };
  return { service, callbacks, timers, events, heard, errors, engine,
    get listener() { return listener; }, get id() { return latestId; }, get listening() { return listening; } };
}
async function testRecognition() {
  const r = recognizer();
  await r.service.start({}, r.callbacks);
  assert.equal(r.listening, 1);
  assert.equal(r.events[0][1].extraParams.recognitionMode, 0);
  const result = (text, final) => r.listener.onResult(r.id, { result: text, isFinal: final, isLast: false });
  result('前', false); result('前进', true); result('前进', true);
  assert.equal(r.heard.length, 2, 'duplicate final for the same clause is ignored');
  result('后退', true);
  assert.equal(r.heard.length, 3, 'a different complete clause may execute without partial callbacks');
  result('前', false); result('前进', true);
  assert.equal(r.heard.length, 5, 'a new utterance may repeat the same command');
  const oldId = r.id;
  r.service.discardPending();
  r.listener.onResult(oldId, { result: '前进', isFinal: true });
  assert.equal(r.heard.length, 5, 'touch stop discards delayed speech');
  r.timers.advance(150);
  assert.notEqual(r.id, oldId);
  const completedId = r.id;
  r.listener.onComplete(completedId, 'complete');
  r.timers.advance(150);
  assert.notEqual(r.id, completedId, 'recognition automatically starts a fresh session');
  r.listener.onError(oldId, 1, 'stale');
  assert.equal(r.errors.length, 0);
  r.service.stop();
  r.listener.onResult(r.id, { result: '前进', isFinal: true });
  r.timers.advance(70000);
  assert.equal(r.heard.length, 5);
  assert.equal(r.timers.count, 0, 'exit releases recognition timers');
}
async function testRecognitionFailures() {
  for (const options of [{ supported: false }, { permission: Promise.resolve({ authResults: [-1] }) }]) {
    const r = recognizer(options);
    await assert.rejects(r.service.start({}, r.callbacks));
    assert.equal(r.events.length, 0, 'no recording when unavailable or permission denied');
  }
  const permission = deferred();
  const p = recognizer({ permission: permission.promise });
  const starting = p.service.start({}, p.callbacks);
  p.service.stop(); permission.resolve({ authResults: [0] }); await starting;
  assert.equal(p.events.length, 0, 'late permission cannot reopen microphone after exit');
  const opening = deferred();
  const r = recognizer({ opening: opening.promise });
  const start = r.service.start({}, r.callbacks);
  await tick(); r.service.stop(); opening.resolve(r.engine); await start;
  assert.deepEqual(r.events, [['shutdown']], 'a late engine is immediately released');
  const timeout = recognizer({ noStart: true });
  const pending = timeout.service.start({}, timeout.callbacks).catch(error => error);
  await tick(); timeout.timers.advance(8000); await pending;
  assert.equal(timeout.errors.length, 1, 'startup timeout fails closed');
  const error = recognizer();
  await error.service.start({}, error.callbacks);
  error.listener.onError(error.id, 1002200011, 'failed');
  assert.equal(error.errors.length, 1);
  assert.equal(error.events.at(-1)[0], 'shutdown');
}
function page() {
  const timers = clock(), calls = [], vibrations = [];
  const Index = load('pages/Index.ets', 'Index', {
    '../services/VoiceCommands': { VoiceCommands: Commands },
    '../services/Haptics': { Haptics: { soft: () => vibrations.push('soft'), hard: () => vibrations.push('hard') } }
  }, timers);
  const p = new Index();
  p.connected = true; p.previewReady = true; p.voiceMode = true; p.voiceListening = true;
  p.pageStack = { size: () => 0, pushPathByName: () => {} };
  p.voiceRecognition = { stop: () => calls.push(['asr-stop']), discardPending: () => calls.push(['asr-discard']) };
  let session = 0, speed = 40;
  p.api = {
    session: async () => ({ sessionId: `s${++session}` }),
    command: async (sid, seq, id, key) => { calls.push(['command', key]); return { speed, accepted: true }; },
    stop: async sid => { calls.push(['stop', sid]); },
    speed: async (sid, seq, id, value) => { speed = value; calls.push(['speed', value]); return { speed, accepted: true }; }
  };
  p.cameraStream = { stop: () => {} };
  p.networkRoute = { release: async () => {} };
  p.showConnectionToast = () => {};
  p.keepPreviewAwake = async () => {};
  return { p, timers, calls, vibrations };
}
async function testVoiceMovement() {
  const { p, calls, timers, vibrations } = page();
  await p.executeVoiceCommand('前进');
  assert.equal(p.activeKey, 'w');
  assert.equal(p.pressedKey, 'w');
  assert.ok(p.commandId.length > 0);
  assert.deepEqual(vibrations, ['soft'], 'accepted movement gives vibration');
  timers.advance(1999); assert.equal(p.activeKey, 'w');
  timers.advance(1); assert.equal(p.activeKey, '');
  assert.ok(calls.some(call => call[0] === 'stop'), 'default movement is bounded to two seconds');
  await p.executeVoiceCommand('左平移三秒');
  await p.executeVoiceCommand('速度五十');
  assert.equal(p.speed, 50);
  assert.equal(p.activeKey, 'left', 'speed changes preserve current movement');
  timers.advance(3000);
  assert.equal(p.activeKey, '', 'speed command does not cancel the movement deadline');
  p.exitVoiceMode(); assert.equal(timers.count, 0);
}
async function testVoiceCancellation() {
  for (const action of ['exit', 'stop', 'back', 'rotate', 'disconnect', 'background', 'connection', 'gallery']) {
    const { p, calls, timers } = page();
    const command = deferred();
    p.api.command = async () => { calls.push(['command']); return await command.promise; };
    const executing = p.executeVoiceCommand('前进'); await tick();
    assert.equal(calls.filter(call => call[0] === 'command').length, 1);
    if (action === 'exit') p.exitVoiceMode();
    if (action === 'stop') p.emergencyStop();
    if (action === 'back') assert.equal(p.onBackPress(), true);
    if (action === 'rotate') p.updateViewport(800, 350);
    if (action === 'disconnect') p.disconnect();
    if (action === 'background') p.onPageHide();
    if (action === 'connection') p.openConnectionSheet();
    if (action === 'gallery') {
      p.pageStack = { size: () => 0, pushPathByName: () => calls.push(['gallery']) };
      p.openGallery();
    }
    command.resolve({ speed: 40, accepted: true }); await executing;
    assert.equal(p.activeKey, '', `${action}: delayed command never resumes motion`);
    assert.equal(p.renewTimer, -1);
    assert.equal(p.voiceMotionTimer, -1);
    assert.equal(timers.count, 0);
    assert.ok(calls.some(call => call[0] === 'stop'));
  }
  const { p, calls } = page();
  p.voiceListening = false;
  await p.executeVoiceCommand('前进'); assert.equal(calls.length, 0, 'startup does not execute motion');
  p.voiceListening = true;
  await p.executeVoiceCommand('不要前进'); assert.equal(calls.length, 0);
  p.previewReady = false;
  await p.executeVoiceCommand('前进'); assert.equal(calls.length, 0, 'fresh video remains required');
  p.voiceMode = false;
  assert.equal(p.onBackPress(), false, 'ordinary back navigation is preserved');
}
async function testVoiceFailuresAndCapture() {
  const { p, calls, vibrations } = page();
  p.api.command = async () => ({ speed: 40, accepted: false });
  await p.executeVoiceCommand('前进');
  assert.equal(p.activeKey, ''); assert.equal(vibrations.length, 0);
  assert.match(p.voiceCommandText, /控制失败/);
  p.pressedKey = '';
  p.api.speed = async () => { throw new Error('unavailable'); };
  await p.executeVoiceCommand('速度六十');
  assert.match(p.voiceCommandText, /调速失败/); assert.equal(vibrations.length, 0);
  p.capture = async () => true;
  await p.executeVoiceCommand('截图');
  assert.equal(p.voiceCommandText, '已执行：截图已保存');
  assert.deepEqual(vibrations, ['soft']);
  p.exitVoiceMode();
}
async function testModeToggleAndLateSpeed() {
  const { p, calls, vibrations } = page();
  p.voiceMode = false;
  const ready = deferred();
  let callbacks;
  p.voiceRecognition.start = async (_context, value) => { callbacks = value; await ready.promise; };
  p.getUIContext = () => ({ getHostContext: () => ({}) });
  const entering = p.toggleVoiceMode(); await tick();
  assert.equal(p.voiceMode, true); assert.equal(p.voiceListening, false);
  callbacks.onListening();
  callbacks.onText('前进', false); await tick();
  assert.equal(p.voiceTranscript, '前进');
  assert.equal(calls.filter(call => call[0] === 'command').length, 0, 'partial results display without executing');
  await p.toggleVoiceMode();
  callbacks.onText('前进', true); ready.resolve(); await entering;
  assert.equal(p.voiceMode, false);
  assert.equal(calls.filter(call => call[0] === 'command').length, 0, 'late ASR callbacks after toggle are ignored');
  assert.deepEqual(vibrations, ['hard', 'hard'], 'enter and exit both give vibration');

  const s = page();
  const response = deferred();
  s.p.api.speed = async () => { s.calls.push(['speed']); return await response.promise; };
  const speed = s.p.executeVoiceCommand('速度六十'); await tick();
  s.p.emergencyStop(); response.resolve({ speed: 60, accepted: true }); await speed; await tick();
  assert.equal(s.p.speed, 40, 'stop rejects a late speed result');
  assert.equal(s.calls.filter(call => call[0] === 'speed').length, 1, 'stop does not retry cancelled voice speed');
  assert.equal(s.p.voiceCommandText, '已发送停车指令');
  s.p.exitVoiceMode();
}
async function testSequentialPlan() {
  const { p, calls, timers, vibrations } = page();
  const stopped = deferred();
  p.api.stop = async sid => { calls.push(['stop', sid]); if (sid === 's2') await stopped.promise; };
  await p.executeVoiceCommand('速度100前进三秒再右转');
  assert.equal(p.voicePlanText, '速度 100 → 前进 3 秒 → 右转 2 秒');
  assert.equal(p.speed, 100);
  assert.equal(p.activeKey, 'w');
  assert.deepEqual(calls.slice(0, 3), [['speed', 100], ['stop', 's1'], ['command', 'w']]);
  timers.advance(2999); await tick(); assert.equal(p.activeKey, 'w');
  timers.advance(1); await tick();
  assert.equal(p.activeKey, '');
  assert.equal(p.voiceQueueRunning, true);
  assert.equal(calls.filter(call => call[0] === 'command').length, 1, 'right turn waits for acknowledged stop');
  timers.advance(10000); await tick();
  assert.equal(calls.filter(call => call[0] === 'command').length, 1, 'time passage cannot bypass pending stop');
  stopped.resolve(); await tick();
  assert.equal(p.activeKey, 'd');
  assert.equal(p.speed, 100, 'speed set by the first step is retained across movement sessions');
  assert.match(p.voiceCommandText, /3\/3/);
  timers.advance(1999); await tick(); assert.equal(p.activeKey, 'd');
  timers.advance(1); await tick();
  assert.equal(p.activeKey, '');
  assert.equal(p.voiceQueueRunning, false);
  assert.equal(p.voiceCommandText, '已完成全部 3 条指令');
  assert.equal(vibrations.length, 5, 'each accepted operation and acknowledged motion stop gives feedback');
  assert.equal(timers.count, 0);
  p.exitVoiceMode();
}
async function testQueueCancellation() {
  for (const action of ['stop', 'back', 'rotate', 'disconnect', 'background', 'new']) {
    const { p, calls, timers } = page();
    await p.executeVoiceCommand('直行三秒再右拐');
    if (action === 'stop') await p.executeVoiceCommand('停下来');
    if (action === 'back') p.onBackPress();
    if (action === 'rotate') p.updateViewport(800, 350);
    if (action === 'disconnect') p.disconnect();
    if (action === 'background') p.onPageHide();
    if (action === 'new') await p.executeVoiceCommand('倒车半秒');
    timers.advance(20000); await tick();
    assert.ok(!calls.some(call => call[0] === 'command' && call[1] === 'd'), `${action}: queued turn is discarded`);
    assert.equal(p.activeKey, '');
    assert.equal(p.voiceQueueRunning, false);
    assert.equal(timers.count, 0);
    p.exitVoiceMode();
  }
  // Rotation or stop can happen before the initial speed request completes, without a held movement.
  for (const action of ['rotate', 'stop']) {
    const { p, calls, timers } = page();
    const response = deferred();
    p.api.speed = async () => { calls.push(['speed']); return await response.promise; };
    const executing = p.executeVoiceCommand('速度100直行三秒再右拐'); await tick();
    if (action === 'rotate') p.updateViewport(800, 350); else p.emergencyStop();
    response.resolve({ speed: 100, accepted: true }); await executing; await tick();
    assert.ok(!calls.some(call => call[0] === 'command'), `${action}: late speed does not launch queued motion`);
    assert.equal(p.voiceQueueRunning, false);
    assert.equal(timers.count, 0);
    p.exitVoiceMode();
  }
  const { p, calls, timers } = page();
  const stopped = deferred();
  p.api.stop = async sid => { calls.push(['stop', sid]); if (sid === 's1') await stopped.promise; };
  await p.executeVoiceCommand('直行半秒然后右转');
  timers.advance(500); await tick();
  p.emergencyStop(); stopped.resolve(); await tick();
  assert.equal(calls.filter(call => call[0] === 'command').length, 1, 'stop while boundary acknowledgement is pending cancels next step');
  p.exitVoiceMode();
}
async function testQueueFailures() {
  for (const text of ['速度100直行三秒再飞起来', '直行三秒再', '速度101然后右转', '前进十秒'.repeat(4)]) {
    const { p, calls } = page();
    await p.executeVoiceCommand(text);
    assert.equal(calls.length, 0, `${text}: no valid prefix is executed from an invalid group`);
    p.exitVoiceMode();
  }
  for (const failure of ['speed', 'move', 'stop', 'capture']) {
    const { p, calls, timers } = page();
    if (failure === 'speed') p.api.speed = async () => { throw new Error('speed failed'); };
    if (failure === 'move') p.api.command = async () => { calls.push(['command']); throw new Error('motion failed'); };
    if (failure === 'stop') p.api.stop = async sid => { calls.push(['stop', sid]); if (sid === 's2') throw new Error('stop failed'); };
    if (failure === 'capture') p.capture = async () => { p.message = '截图保存失败'; return false; };
    await p.executeVoiceCommand(failure === 'capture' ? '拍张照再右转' : '速度100前进半秒再右转');
    timers.advance(500); await tick();
    assert.ok(!calls.some(call => call[0] === 'command' && call[1] === 'd'), `${failure}: failure prevents later motion`);
    assert.equal(p.voiceQueueRunning, false);
    assert.match(p.voiceCommandText, /后续指令已取消/);
    assert.equal(timers.count, 0);
    p.exitVoiceMode();
  }
}
async function testCaptureInQueue() {
  const { p, calls, timers } = page();
  const saved = deferred();
  p.capture = async () => { calls.push(['capture']); return await saved.promise; };
  await p.executeVoiceCommand('直行半秒拍张照然后右转半秒');
  timers.advance(500); await tick();
  assert.ok(calls.some(call => call[0] === 'capture'));
  assert.equal(calls.filter(call => call[0] === 'command').length, 1, 'capture acknowledgement is awaited');
  saved.resolve(true); await tick(); assert.equal(p.activeKey, 'd');
  timers.advance(500); await tick(); assert.equal(p.voiceQueueRunning, false);
  p.exitVoiceMode();
  const late = page();
  const pending = deferred();
  late.p.capture = async () => await pending.promise;
  const capture = late.p.executeVoiceCommand('拍张照再右转'); await tick();
  late.p.emergencyStop(); pending.resolve(true); await capture;
  assert.ok(!late.calls.some(call => call[0] === 'command'), 'late screenshot cannot resume a cancelled plan');
  late.p.exitVoiceMode();
}
async function testSpokenContinuation() {
  const { p, calls, timers } = page();
  await p.executeVoiceCommand('速度100前进三秒');
  await p.executeVoiceCommand('然后右转半秒');
  assert.equal(p.voicePlanText, '速度 100 → 前进 3 秒 → 右转 0.5 秒');
  assert.equal(p.activeKey, 'w', 'a spoken continuation does not interrupt the current movement');
  timers.advance(2999); await tick();
  assert.equal(calls.filter(call => call[0] === 'command').length, 1);
  timers.advance(1); await tick(); assert.equal(p.activeKey, 'd');
  timers.advance(500); await tick();
  assert.equal(p.voiceQueueRunning, false);
  assert.equal(p.voiceCommandText, '已完成全部 3 条指令');
  p.exitVoiceMode();
  const limit = page();
  await limit.p.executeVoiceCommand('前进十秒后退十秒左转十秒');
  await limit.p.executeVoiceCommand('再右转');
  assert.match(limit.p.voiceCommandText, /未追加/);
  assert.equal(limit.p.voiceQueueCommands.length, 3, 'continuations respect limits for the whole group');
  limit.p.emergencyStop();
  limit.timers.advance(60000); await tick();
  assert.equal(limit.calls.filter(call => call[0] === 'command').length, 1);
  limit.p.exitVoiceMode();
}
(async () => {
  testParser();
  await testRecognition();
  await testRecognitionFailures();
  await testVoiceMovement();
  await testVoiceCancellation();
  await testVoiceFailuresAndCapture();
  await testModeToggleAndLateSpeed();
  await testSequentialPlan();
  await testQueueCancellation();
  await testQueueFailures();
  await testCaptureInQueue();
  await testSpokenContinuation();
  console.log('Voice synonyms/complete plans, ASR lifecycle, acknowledged sequencing, timing, cancellation, failure isolation and haptics: OK');
})().catch(error => { console.error(error); process.exitCode = 1; });
