// Run with Node and the TypeScript compiler bundled with the HarmonyOS SDK.
// Executes the actual parser/control methods with simulated network timing.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARKTS_TYPESCRIPT ||
  '/Users/raychen/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
};
const Empty = class {};
function load(source, name, modules = {}, logger = console) {
  const output = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const context = { exports: {}, console: logger, Date, Math, Number, String, Uint8Array, ArrayBuffer,
    setTimeout, clearTimeout, setInterval, clearInterval, NavPathStack: Empty, Scroller: Empty,
    require: id => modules[id] || new Proxy({}, { get: () => Empty }) };
  vm.runInNewContext(output + `\nexports.TestClass = ${name};`, context);
  return context.exports.TestClass;
}
const Parser = load(fs.readFileSync(path.join(root, 'services/MjpegParser.ets'), 'utf8'), 'MjpegParser');
const PhoneApi = load(fs.readFileSync(path.join(root, 'services/PhoneApi.ets'), 'utf8'), 'PhoneApi');
assert.equal(new PhoneApi().streamUrl(15), 'http://192.168.8.204:8080/api/v1/camera/stream.mjpg?fps=15');
assert.equal(new PhoneApi().frameUrl(), 'http://192.168.8.204:8080/api/v1/camera/frame.jpg');
assert.equal(new PhoneApi().streamUrl(30, 12), 'http://192.168.8.204:8080/api/v1/camera/stream.mjpg?fps=30&frames=12');
function part(jpeg) {
  return Buffer.concat([Buffer.from(`--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ${jpeg.length}\r\n\r\n`),
    jpeg, Buffer.from('\r\n')]);
}
const arrayBuffer = bytes => Uint8Array.from(bytes).buffer;
function testParser() {
  const jpeg = Buffer.from([255, 216, 13, 10, 13, 10, 12, 255, 217]);
  const wire = part(jpeg);
  for (let split = 1; split < wire.length; split++) {
    const parser = new Parser();
    const first = parser.push(arrayBuffer(wire.subarray(0, split)));
    const second = parser.push(arrayBuffer(wire.subarray(split)));
    assert.deepEqual(Buffer.from(second || first), jpeg);
  }
  const parser = new Parser();
  let latest;
  for (const byte of wire) { latest = parser.push(arrayBuffer([byte])) || latest; }
  assert.deepEqual(Buffer.from(latest), jpeg);
  const newer = Buffer.from([255, 216, 2, 255, 217]);
  assert.deepEqual(Buffer.from(parser.push(arrayBuffer(Buffer.concat([wire, part(newer)])))), newer);
  assert.throws(() => new Parser().push(arrayBuffer(Buffer.from(
    '--frame\r\nContent-Type: image/jpeg\r\nContent-Length: 2000000\r\n\r\n'))));
  parser.reset();
  assert.deepEqual(Buffer.from(parser.push(arrayBuffer(wire))), jpeg);
}
const indexSource = fs.readFileSync(path.join(root, 'pages/Index.ets'), 'utf8')
  .split('  @Builder')[0].replace(/@Entry\s*|@Component\s*|@State\s*/g, '')
  .replace('struct Index', 'class Index') + '\n}';
const RadarPresentation = load(fs.readFileSync(path.join(root, 'services/RadarPresentation.ets'), 'utf8'),
  'RadarPresentation');
const vibrations = [];
function hapticPlayer(overrides = {}, logs = []) {
  return load(fs.readFileSync(path.join(root, 'services/Haptics.ets'), 'utf8'), 'Haptics', {
    '@kit.SensorServiceKit': { vibrator: {
      getVibratorInfoSync: () => [{}], isSupportEffectSync: () => true,
      startVibration: () => {}, ...overrides
    } }
  }, { ...console, error: (...args) => logs.push(args), warn: (...args) => logs.push(args) });
}
let hardwareQueries = 0;
const effectQueries = [];
const Haptics = hapticPlayer({
  getVibratorInfoSync: () => { hardwareQueries++; return [{}]; },
  isSupportEffectSync: effect => { effectQueries.push(effect); return true; },
  startVibration: (effect, attributes, callback) => {
    vibrations.push({ effect, attributes });
    callback();
  }
});
const RadarHaptics = load(fs.readFileSync(path.join(root, 'services/RadarHaptics.ets'), 'utf8'), 'RadarHaptics', {
  './Haptics': { Haptics }
});
const savedConnection = new Map();
let preferenceFlushes = 0;
const connectionPreferences = {
  getSync: (key, fallback) => savedConnection.get(key) ?? fallback,
  putSync: (key, value) => savedConnection.set(key, value),
  flush: async () => { preferenceFlushes++; }
};
const Index = load(indexSource, 'Index', {
  '../services/PhoneApi': { PhoneApi },
  '../services/RadarPresentation': { RadarPresentation },
  '../services/Haptics': { Haptics },
  '../services/RadarHaptics': { RadarHaptics },
  '@kit.ArkData': { preferences: { getPreferencesSync: () => connectionPreferences } },
  '@kit.PerformanceAnalysisKit': { hilog: { debug: () => {}, info: () => {}, warn: () => {} } }
});

function testRadarReadings() {
  const lidar = { status: 'scanning', health: 'OK', points: 1000, age_seconds: 0.2,
    front_nearest_mm: 100, sector_90_mm: 501, sector_180_mm: 200, sector_270_mm: 50 };
  const radar = RadarPresentation.read(lidar);
  assert.equal(radar.frontMm, 100);
  assert.equal(radar.leftMm, 50, 'valid readings below 100 mm are never clamped or dropped');
  assert.equal(radar.rightMm, 501);
  assert.equal(RadarPresentation.distanceText(100, true), '0.10 m');
  assert.equal(RadarPresentation.distanceText(50, true), '0.05 m');
  assert.equal(RadarPresentation.distanceText(1, true), '<0.01 m');
  assert.equal(RadarPresentation.distanceText(null, true), '未测得');
  assert.equal(RadarPresentation.distanceText(100, false), '未就绪');
  assert.equal(RadarPresentation.rawText(100), '100 mm');
  for (const [mm, expected] of [[50, 3], [100, 3], [200, 3], [200.25, 2], [500, 2], [500.25, 1]]) {
    assert.equal(RadarPresentation.level(mm, true), expected, `threshold for ${mm} mm`);
  }
  for (const invalid of [null, undefined, 0, -1, NaN, Infinity, '100']) {
    assert.equal(RadarPresentation.validDistance(invalid), null);
    assert.equal(RadarPresentation.level(invalid, true), 0, 'missing readings never imply clear space');
  }
  for (const patch of [{ age_seconds: 2.5 }, { age_seconds: NaN }, { age_seconds: -1 },
    { status: 'stale' }, { status: 'waiting' }, { health: 'error' }, { points: 0 }]) {
    const unavailable = RadarPresentation.read({ ...lidar, ...patch });
    assert.equal(unavailable.ready, false);
    assert.equal(unavailable.frontMm, null);
  }
  assert.equal(RadarPresentation.read({ ...lidar, age_seconds: undefined }).ready, true,
    'older servers without age metadata remain compatible');
  const p = page(apiMock());
  p.applyStatus({ speed: 40, camera: { status: 'live' }, lidar });
  assert.equal(p.frontMm, 100);
  assert.equal(p.sector270Mm, 50);
  assert.equal(p.radarFreshness, '最近扫描 0.2 秒前');
  p.applyStatus({ speed: 40, camera: { status: 'live' }, lidar: { ...lidar, status: 'stale' } });
  assert.equal(p.lidarReady, false);
  assert.equal(p.frontMm, null);
  assert.equal(p.radarFreshness, '暂无新鲜扫描');
}
function testHapticsPresets() {
  vibrations.length = 0;
  Haptics.soft();
  Haptics.hard();
  RadarHaptics.warning();
  RadarHaptics.danger();
  assert.deepEqual(vibrations.map(v => [v.effect.effectId, v.effect.count, v.effect.intensity]), [
    ['haptic.effect.soft', 1, 50], ['haptic.effect.hard', 1, 50],
    ['haptic.effect.soft', 1, 20], ['haptic.effect.hard', 1, 65]
  ], 'button and radar feedback each have independently defined presets');
  assert.ok(vibrations.every(v => v.attributes.usage === 'touch'));
  assert.equal(hardwareQueries, 1, 'hardware support is cached');
  assert.deepEqual(effectQueries, ['haptic.effect.soft', 'haptic.effect.hard'], 'effect support is cached');

  let started = 0;
  let noHardwareQueries = 0;
  const noHardware = hapticPlayer({
    getVibratorInfoSync: () => { noHardwareQueries++; return []; },
    isSupportEffectSync: () => { throw new Error('effects must not be queried without hardware'); },
    startVibration: () => { started++; }
  });
  noHardware.soft();
  noHardware.hard();
  assert.equal(started, 0, 'devices without a vibrator skip feedback');
  assert.equal(noHardwareQueries, 1, 'missing hardware is cached too');

  const unsupportedLogs = [];
  let unsupportedQueries = 0;
  const unsupported = hapticPlayer({
    isSupportEffectSync: effect => { unsupportedQueries++; return effect === 'haptic.effect.hard'; },
    startVibration: () => { started++; }
  }, unsupportedLogs);
  unsupported.soft();
  unsupported.soft();
  unsupported.hard();
  assert.equal(started, 1, 'one unsupported effect does not block other supported effects');
  assert.equal(unsupportedQueries, 2, 'unsupported effects are not repeatedly queried');
  assert.equal(unsupportedLogs.length, 1, 'unsupported effects are reported once');

  const failure = Object.assign(new Error('mock vibration failure'), { code: 801 });
  for (const overrides of [
    { getVibratorInfoSync: () => { throw failure; } },
    { isSupportEffectSync: () => { throw failure; } },
    { startVibration: () => { throw failure; } },
    { startVibration: (effect, attributes, callback) => callback(failure) }
  ]) {
    const logs = [];
    const player = hapticPlayer(overrides, logs);
    assert.doesNotThrow(() => player.soft(), 'vibration failures never interrupt the calling action');
    assert.equal(logs.length, 1, 'hardware, effect and vibration failures are logged');
  }
}
async function testRadarHaptics() {
  const p = page(apiMock());
  vibrations.length = 0;
  const update = (front, left, right, patch = {}) => p.applyStatus({
    speed: 40, camera: { status: 'live' }, lidar: {
      status: 'scanning', health: 'OK', points: 1000, age_seconds: 0.2,
      front_nearest_mm: front, sector_270_mm: left, sector_90_mm: right, ...patch
    }
  });
  const effects = () => vibrations.map(v => v.effect.effectId);
  update(501, 501, 501);
  assert.equal(vibrations.length, 0, 'safe distances do not vibrate');
  update(500, 501, 501);
  assert.deepEqual(effects(), ['haptic.effect.soft'], 'front entering orange gives a light pulse');
  update(300, 501, 501);
  assert.equal(vibrations.length, 1, 'polling within the same color does not repeat feedback');
  update(300, 500, 501);
  assert.equal(vibrations.length, 2, 'left entering orange still alerts while front is orange');
  update(200, 400, 501);
  assert.equal(effects().at(-1), 'haptic.effect.hard', 'orange to red gives stronger feedback');
  update(100, 400, 200);
  assert.equal(vibrations.length, 4, 'right entering red still alerts while front is already red');
  update(50, 350, 150);
  assert.equal(vibrations.length, 4, 'steady red and orange readings do not repeat feedback');
  update(201, 350, 150);
  assert.equal(effects().at(-1), 'haptic.effect.soft', 'red to orange gives the orange pulse');
  update(501, 501, 501);
  assert.equal(vibrations.length, 5, 'leaving the warning range does not vibrate');
  update(500, 500, 500);
  assert.equal(vibrations.length, 6, 'simultaneous orange entries produce one pulse');
  update(501, 501, 501);
  update(500, 200, 200);
  assert.equal(vibrations.length, 7, 'simultaneous orange and red entries produce one pulse');
  assert.equal(effects().at(-1), 'haptic.effect.hard', 'red takes priority for simultaneous entries');
  const soft = vibrations.find(v => v.effect.effectId === 'haptic.effect.soft');
  const hard = vibrations.find(v => v.effect.effectId === 'haptic.effect.hard');
  assert.ok(hard.effect.intensity > soft.effect.intensity, 'red has a larger vibration intensity');
  assert.equal(soft.effect.intensity, 20, 'orange uses the dedicated radar amplitude');
  assert.equal(hard.effect.intensity, 65, 'red uses the dedicated radar amplitude');
  assert.ok(vibrations.every(v => v.effect.count === 1), 'each entry is a single pulse');
  for (const patch of [{ age_seconds: 2.5 }, { status: 'stale' }, { health: 'error' }, { points: 0 }]) {
    update(100, 100, 100, patch);
    assert.equal(vibrations.length, 7, 'unavailable radar never vibrates');
  }
  update(null, 0, -1);
  assert.equal(vibrations.length, 7, 'missing and invalid echoes never vibrate');
  update(200, 501, 501);
  assert.equal(vibrations.length, 8, 'a first valid dangerous reading alerts');
  p.isLandscape = true;
  update(200, 501, 501);
  assert.equal(vibrations.length, 8, 'orientation changes do not retrigger a steady warning');
  p.disconnect();
  await p.connectionCleanup;
  assert.equal(vibrations.length, 8, 'disconnect itself does not vibrate');
  p.connected = true;
  update(200, 501, 501);
  assert.equal(vibrations.length, 9, 'a new connection alerts again for its first dangerous reading');
  assert.deepEqual(p.api.calls, [], 'radar feedback never sends vehicle commands');
}
const padSource = fs.readFileSync(path.join(root, 'components/LandscapeControlPad.ets'), 'utf8')
  .split('  @Builder')[0].replace(/@Component\s*|@Prop\s*|@State\s*/g, '')
  .replace('struct LandscapeControlPad', 'class LandscapeControlPad') + '\n}';
const Pad = load(padSource, 'LandscapeControlPad');
function testLandscapeMapping() {
  const pad = new Pad();
  pad.drive = false;
  for (const [x, y, key] of [[20, 90, 'q'], [160, 90, 'e'], [90, 20, 'left'], [90, 160, 'right']]) {
    assert.equal(pad.zoneAt(x, y), key);
  }
  assert.equal(pad.zoneAt(90, 90), 'center');
  pad.drive = true;
  for (const [x, y, key] of [[20, 90, 'a'], [160, 90, 'd'], [90, 20, 'w'], [90, 160, 's']]) {
    assert.equal(pad.zoneAt(x, y), key);
  }
}
function page(api) {
  const p = new Index();
  p.api = api;
  p.connected = true;
  p.previewReady = true;
  p.networkRoute = { bind: async () => true, release: async () => {} };
  p.cameraStream = { start: () => {}, stop: () => {} };
  p.toasts = [];
  p.getUIContext = () => ({ getHostContext: () => ({}),
    getPromptAction: () => ({ showToast: toast => p.toasts.push(toast.message) }) });
  return p;
}
function apiMock() {
  const calls = [];
  let sessions = 0;
  const api = {
    calls,
    session: async () => { const sid = `s${++sessions}`; calls.push(['session', sid]); return { sessionId: sid }; },
    command: async (sid, seq, id, key) => { calls.push(['command', sid, seq, id, key]); return { speed: 40 }; },
    speed: async (sid, seq, id, speed) => { calls.push(['speed', sid, seq, id, speed]); return { speed }; },
    stop: async sid => { calls.push(['stop', sid]); return { speed: 40 }; },
    renew: async (sid, id) => { calls.push(['renew', sid, id]); return { speed: 40 }; }
  };
  return api;
}
async function testHeldSpeed() {
  const api = apiMock();
  const p = page(api);
  await p.beginAction('w', true);
  const motionId = p.commandId;
  p.changeSpeed(60);
  await delay(70);
  p.changeSpeed(65);
  await delay(70);
  assert.equal(p.speed, 65, 'speed applies while dragging and holding motion');
  assert.equal(p.activeKey, 'w');
  assert.equal(p.commandId, motionId);
  await p.renew(p.controlGeneration);
  assert.ok(api.calls.some(c => c[0] === 'renew' && c[2] === motionId));
  assert.equal(api.calls.filter(c => c[0] === 'session').length, 1);
  assert.equal(api.calls.filter(c => c[0] === 'command').length, 1);
  p.endAction('w');
  p.clearTimers();
}
async function testSpeedWhileStarting() {
  const api = apiMock();
  const pending = deferred();
  api.command = async (...args) => { api.calls.push(['command', ...args]); return pending.promise; };
  const p = page(api);
  const begin = p.beginAction('left', true);
  await delay(0);
  p.changeSpeed(70);
  await delay(140);
  assert.equal(api.calls.filter(c => c[0] === 'speed').length, 0);
  pending.resolve({ speed: 40 });
  await begin;
  await delay(0);
  assert.equal(p.speed, 70);
  assert.equal(p.activeKey, 'left');
  assert.equal(api.calls.filter(c => c[0] === 'session').length, 1);
  p.endAction('left');
  p.clearTimers();
}
async function testCancelledSessionOpening() {
  const api = apiMock();
  const pending = deferred();
  let opens = 0;
  api.session = async () => ++opens === 1 ? pending.promise : { sessionId: 'new' };
  const p = page(api);
  p.speedDesired = 55;
  const speed = p.flushSpeed();
  await delay(0);
  const begin = p.beginAction('e', true);
  await delay(0);
  assert.equal(opens, 1, 'new gesture waits for prior session creation');
  pending.resolve({ sessionId: 'old' });
  await Promise.all([speed, begin]);
  await delay(0);
  assert.equal(opens, 2);
  assert.ok(api.calls.some(c => c[0] === 'stop' && c[1] === 'old'));
  assert.ok(!api.calls.some(c => c[0] === 'speed' && c[1] === 'old'));
  assert.equal(p.sessionId, 'new');
  assert.equal(p.activeKey, 'e');
  p.endAction('e');
  p.clearTimers();
}
async function testLateSpeedAfterStop() {
  const api = apiMock();
  const pending = deferred();
  api.speed = async (...args) => { api.calls.push(['speed', ...args]); return pending.promise; };
  const p = page(api);
  await p.beginAction('q', true);
  p.speedDesired = 75;
  const speed = p.flushSpeed();
  await delay(0);
  p.endAction('q');
  p.connected = false;
  pending.resolve({ speed: 75 });
  await speed;
  assert.equal(p.speed, 40);
  assert.equal(p.activeKey, '');
  assert.equal(p.sessionId, '');
  assert.equal(api.calls.filter(c => c[0] === 'command').length, 1);
  p.clearTimers();
}
async function testRouteBeforeStream() {
  const api = apiMock();
  const events = [];
  api.setBaseUrl = () => true;
  api.streamUrl = () => 'http://car/api/v1/camera/stream.mjpg';
  api.frameUrl = () => 'http://car/api/v1/camera/frame.jpg';
  api.status = async () => {
    events.push('status');
    return { mode: 'phone', speed: 40, camera: { status: 'live' },
      lidar: { points: 10, status: 'scanning', health: 'OK' } };
  };
  const p = page(api);
  p.connected = false;
  p.networkRoute = { bind: async () => { events.push('bind'); }, release: async () => {} };
  p.cameraStream = { start: () => { events.push('stream'); }, stop: () => {} };
  await p.connect();
  assert.deepEqual(events, ['bind', 'status', 'stream']);
  p.disconnect();
  p.clearTimers();
}
function withConnection(api) {
  api.setBaseUrl = () => true;
  api.streamUrl = () => 'http://car/api/v1/camera/stream.mjpg';
  api.frameUrl = () => 'http://car/api/v1/camera/frame.jpg';
  api.status = async () => ({ bootId: 'boot1', mode: 'phone', speed: 40, moving: false,
    camera: { status: 'live' }, lidar: { points: 10, status: 'scanning', health: 'OK' } });
  return api;
}
async function testStreamRecoveryNeverResumesMotion() {
  const api = withConnection(apiMock());
  const p = page(api);
  let frame, failure, starts = 0;
  const previews = [];
  p.connected = false;
  p.cameraStream.start = (url, onFrame, onRate, onFailure, framePreview) => {
    starts++; frame = onFrame; failure = onFailure;
    previews.push([url, framePreview]);
  };
  await p.connect();
  p.showUnavailable = () => {};
  await p.beginAction('w', true);
  assert.equal(api.calls.filter(c => c[0] === 'command').length, 0, 'no motion without a fresh frame');
  frame({});
  await p.beginAction('w', true);
  const oldSession = p.sessionId;
  failure('test video stall');
  assert.deepEqual(previews[0], ['http://car/api/v1/camera/stream.mjpg', true],
    'the first connection already uses overlapping MJPEG segments');
  assert.equal(p.activeKey, '');
  assert.equal(p.pressedKey, '');
  assert.equal(p.previewReady, false);
  await delay(560);
  assert.equal(starts, 2, 'stream recovers automatically');
  assert.deepEqual(previews[1], ['http://car/api/v1/camera/stream.mjpg', true]);
  assert.equal(p.connected, true);
  assert.equal(p.previewReady, false);
  assert.ok(api.calls.some(c => c[0] === 'stop' && c[1] === oldSession));
  frame({});
  assert.equal(api.calls.filter(c => c[0] === 'command').length, 1, 'old gesture never replays');
  failure('second stall');
  p.onPageHide();
  await delay(560);
  assert.equal(starts, 2, 'background cancels recovery');
  assert.equal(p.reconnectTimer, -1);
  await p.connectionCleanup;
}
async function testLateStatusCannotAffectNewConnection() {
  const api = withConnection(apiMock());
  const p = page(api);
  p.bootId = 'boot1';
  const pending = deferred();
  let polls = 0;
  api.status = () => { polls++; return pending.promise; };
  const oldPoll = p.pollStatus();
  await p.pollStatus();
  assert.equal(polls, 1, 'status polling never overlaps in one connection');
  p.disconnect();
  p.connected = true;
  p.speed = 55;
  pending.resolve({ bootId: 'old-boot', mode: 'phone', speed: 10,
    camera: { status: 'live' }, lidar: { points: 1, status: 'scanning', health: 'OK' } });
  await oldPoll;
  assert.equal(p.connected, true, 'old boot ID cannot disconnect a new connection');
  assert.equal(p.speed, 55, 'late status cannot overwrite a new connection');
  p.disconnect();
  await p.connectionCleanup;
}

async function testRecoverySurvivesEarlyServerRefusal() {
  const api = withConnection(apiMock());
  const healthyStatus = api.status;
  const p = page(api);
  let frame, failure, starts = 0;
  p.connected = false;
  p.cameraStream.start = (_url, onFrame, _onRate, onFailure) => {
    starts++; frame = onFrame; failure = onFailure;
  };
  try {
    await p.connect();
    frame({});
    await p.beginAction('w', true);
    const oldSession = p.sessionId;
    let probes = 0;
    api.status = async () => {
      if (++probes === 1) { throw new Error('server restarting'); }
      return healthyStatus();
    };
    failure('service unavailable');
    await delay(560);
    assert.equal(probes, 1);
    assert.equal(p.connected, false, 'failed first retry keeps controls offline');
    assert.ok(p.reconnectTimer >= 0, 'server startup gets another bounded chance');
    assert.ok(api.calls.some(c => c[0] === 'stop' && c[1] === oldSession));
    await delay(2200);
    assert.equal(starts, 2, 'preview opens when the server is ready after initial refusal');
    assert.equal(p.connected, true);
    assert.equal(p.previewReady, false);
    frame({});
    assert.equal(p.reconnectAttempt, 0, 'fresh video ends the recovery episode');
    assert.equal(api.calls.filter(c => c[0] === 'command').length, 1, 'held command is never replayed');
  } finally { p.onPageHide(); await p.connectionCleanup; }
}

async function testRecoveryExhaustsAndManualFailuresDoNotLoop() {
  const api = withConnection(apiMock());
  const p = page(api);
  let frame, failure;
  p.connected = false;
  p.cameraStream.start = (_url, onFrame, _onRate, onFailure) => { frame = onFrame; failure = onFailure; };
  try {
    await p.connect();
    frame({});
    let probes = 0;
    api.status = async () => { probes++; throw new Error('server remains offline'); };
    failure('offline');
    await delay(560);
    assert.equal(probes, 1);
    await delay(2100);
    assert.equal(probes, 2);
    await delay(4100);
    assert.equal(probes, 3, 'recovery has a finite request bound');
    assert.equal(p.connectionWanted, false);
    assert.equal(p.reconnectTimer, -1);
    assert.equal(p.connected, false);
    assert.match(p.message, /请手动连接/);
    await delay(600);
    assert.equal(probes, 3, 'exhaustion does not schedule an endless loop');
    await p.connect();
    await delay(600);
    assert.equal(probes, 4, 'manual connection failure never starts automatic recovery');
    assert.equal(p.reconnectTimer, -1);
  } finally { p.onPageHide(); await p.connectionCleanup; }
}

async function testBackgroundCancelsLaterRecoveryAttempt() {
  const api = withConnection(apiMock());
  const p = page(api);
  let frame, failure;
  p.connected = false;
  p.cameraStream.start = (_url, onFrame, _onRate, onFailure) => { frame = onFrame; failure = onFailure; };
  try {
    await p.connect();
    frame({});
    let probes = 0;
    api.status = async () => { probes++; throw new Error('server restarting'); };
    failure('offline');
    await delay(560);
    assert.equal(probes, 1);
    p.onPageHide();
    await delay(2200);
    assert.equal(probes, 1, 'background cancels the pending later retry');
    assert.equal(p.reconnectTimer, -1);
    assert.equal(p.connectionWanted, false);
  } finally { p.onPageHide(); await p.connectionCleanup; }
}
async function testCancelWhileBinding() {
  const api = withConnection(apiMock());
  const p = page(api);
  p.connected = false;
  const pending = deferred();
  const events = [];
  p.networkRoute.bind = async () => { events.push('bind'); await pending.promise; };
  p.networkRoute.release = async () => { events.push('release'); };
  const connecting = p.connect();
  await delay(0);
  p.disconnect();
  pending.resolve();
  await connecting;
  await p.connectionCleanup;
  assert.equal(p.connected, false);
  assert.deepEqual(events, ['bind', 'release'], 'binding is released after a cancelled open finishes');
}
(async () => {
  testParser();
  testLandscapeMapping();
  testHapticsPresets();
  testRadarReadings();
  await testRadarHaptics();
  await testHeldSpeed();
  await testSpeedWhileStarting();
  await testCancelledSessionOpening();
  await testLateSpeedAfterStop();
  await testRouteBeforeStream();
  await testStreamRecoveryNeverResumesMotion();
  await testRecoverySurvivesEarlyServerRefusal();
  await testRecoveryExhaustsAndManualFailuresDoNotLoop();
  await testBackgroundCancelsLaterRecoveryAttempt();
  await testLateStatusCannotAffectNewConnection();
  await testCancelWhileBinding();
  console.log('MJPEG parser, landscape mapping, radar readings/transition haptics, LAN binding, control timing and safe stream recovery: OK');
})().catch(error => { console.error(error); process.exitCode = 1; });
