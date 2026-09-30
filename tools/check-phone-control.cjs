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
function load(source, name, modules = {}) {
  const output = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const context = { exports: {}, console, Date, Math, Number, String, Uint8Array, ArrayBuffer,
    setTimeout, clearTimeout, setInterval, clearInterval, NavPathStack: Empty,
    require: id => modules[id] || new Proxy({}, { get: () => Empty }) };
  vm.runInNewContext(output + `\nexports.TestClass = ${name};`, context);
  return context.exports.TestClass;
}
const Parser = load(fs.readFileSync(path.join(root, 'services/MjpegParser.ets'), 'utf8'), 'MjpegParser');
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
const Index = load(indexSource, 'Index');
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
(async () => {
  testParser();
  testLandscapeMapping();
  await testHeldSpeed();
  await testSpeedWhileStarting();
  await testCancelledSessionOpening();
  await testLateSpeedAfterStop();
  await testRouteBeforeStream();
  console.log('MJPEG fragmentation/latest-frame/bounds, landscape mapping, LAN binding and 4 control timing regressions: OK');
})().catch(error => { console.error(error); process.exitCode = 1; });
