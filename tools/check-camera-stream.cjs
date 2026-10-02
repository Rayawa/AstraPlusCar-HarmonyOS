// Exercise the actual CameraStream with controlled HTTP completion and time.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARKTS_TYPESCRIPT ||
  '/Users/raychen/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/services/CameraStream.ets'), 'utf8');
const output = ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
}).outputText;
const settle = async () => { for (let i = 0; i < 12; i++) { await Promise.resolve(); } };
const jpeg = id => Uint8Array.from([255, 216, id, 255, 217]).buffer;
const parserOutput = ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/services/MjpegParser.ets'), 'utf8'), {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
}).outputText;
const parserContext = { exports: {}, ArrayBuffer, Uint8Array };
vm.runInNewContext(parserOutput, parserContext);
const Parser = parserContext.exports.MjpegParser;
const part = id => {
  const body = Buffer.from(jpeg(id));
  const wire = Buffer.concat([Buffer.from(`--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ${body.length}\r\nX-Frame-Sequence: ${id}\r\n\r\n`), body, Buffer.from('\r\n')]);
  return Uint8Array.from(wire).buffer;
};
function setup() {
  let now = 0, timerId = 0;
  const timers = new Map(), requests = [], frames = [], failures = [];
  const schedule = (fn, delay, interval = 0) => {
    const id = ++timerId;
    timers.set(id, { fn, at: now + delay, interval });
    return id;
  };
  const createHttp = () => {
    let resolve, reject;
    const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
    const task = { destroyed: false, handlers: {},
      on: (name, fn) => { task.handlers[name] = fn; },
      off: name => { delete task.handlers[name]; },
      destroy: () => { assert.equal(task.destroyed, false, 'destroy once'); task.destroyed = true; },
      request: (url, options) => { requests.push({ task, url, options, resolve, reject }); return promise; },
      requestInStream: (url, options) => { requests.push({ task, url, options, resolve, reject }); return promise; }
    };
    return task;
  };
  const modules = {
    '@kit.NetworkKit': { http: { createHttp, RequestMethod: { GET: 'GET' },
      HttpDataType: { ARRAY_BUFFER: 2 }, HttpProtocol: { HTTP1_1: 1 } } },
    '@kit.ImageKit': { image: { PixelMapFormat: { RGBA_8888: 3 },
      createImageSource: data => ({ release: async () => {},
        createPixelMap: async () => ({ id: new Uint8Array(data)[2], release: async () => {} }) }) } },
    '@kit.PerformanceAnalysisKit': { hilog: { warn: () => {}, info: () => {} } },
    './MjpegParser': { MjpegParser: Parser }
  };
  const context = { exports: {}, require: id => modules[id], ArrayBuffer, Uint8Array,
    Date: class extends Date { static now() { return now; } },
    setTimeout: (fn, delay) => schedule(fn, delay), clearTimeout: id => timers.delete(id),
    setInterval: (fn, delay) => schedule(fn, delay, delay), clearInterval: id => timers.delete(id) };
  vm.runInNewContext(output, context);
  const camera = new context.exports.CameraStream();
  const tick = async ms => {
    const end = now + ms;
    while (true) {
      const due = [...timers.entries()].filter(([, t]) => t.at <= end)
        .sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) { break; }
      const [id, t] = due;
      now = t.at;
      if (t.interval) { t.at += t.interval; } else { timers.delete(id); }
      t.fn();
      await settle();
    }
    now = end;
    await settle();
  };
  const start = (shortFrames = true) => camera.start('http://car/frame.jpg',
    frame => frames.push(frame.id), () => {}, message => failures.push(message), shortFrames);
  return { camera, requests, frames, failures, tick, start };
}
const emit = (request, id) => request.task.handlers.dataReceive?.(part(id));
(async () => {
  const partial = new Parser();
  const first = new Uint8Array(part(20)), next = new Uint8Array(part(30));
  const combined = new Uint8Array(first.length + next.length - 5);
  combined.set(first); combined.set(next.slice(0, next.length - 5), first.length);
  assert.equal(new Uint8Array(partial.push(combined.buffer))[2], 20);
  assert.equal(partial.sequence, 20, 'an incomplete later part cannot change the completed frame sequence');
  assert.equal(new Uint8Array(partial.push(next.slice(next.length - 5).buffer))[2], 30);
  assert.equal(partial.sequence, 30);
  const s = setup();
  s.start();
  await s.tick(650);
  assert.equal(s.requests.length, 3, 'at most three overlapping segments');
  emit(s.requests[1], 2);
  await settle();
  assert.deepEqual(s.frames, [2], 'a newer segment bypasses the stalled first segment');
  emit(s.requests[0], 1);
  await settle();
  assert.deepEqual(s.frames, [2], 'overlapping older source frames are discarded');
  emit(s.requests[0], 3);
  await settle();
  assert.deepEqual(s.frames, [2, 3], 'source sequence governs freshness, independent of request order');
  const late = s.requests[2].task.handlers.dataReceive;
  s.camera.stop();
  assert.ok(s.requests.every(r => r.task.destroyed), 'stop cancels all segments');
  late(part(4));
  await settle();
  await s.tick(3000);
  assert.deepEqual(s.frames, [2, 3]);
  assert.equal(s.failures.length, 0, 'stop cancels the watchdog and segment timers');
  for (const mode of [true, false]) {
    const stalled = setup();
    stalled.start(mode);
    await stalled.tick(2500);
    assert.equal(stalled.failures.length, 1, 'both modes retain the fresh-frame watchdog');
    assert.ok(stalled.requests.every(r => r.task.destroyed));
  }
  const ended = setup();
  ended.start();
  ended.requests[0].task.handlers.dataEnd();
  await ended.tick(300);
  assert.equal(ended.requests.length, 2, 'normal end continues with another segment');
  assert.equal(ended.failures.length, 0);
  ended.camera.stop();
  const frozen = setup();
  frozen.start();
  for (let i = 0; i < 26; i++) {
    frozen.requests.filter(r => !r.task.destroyed).forEach(r => emit(r, 1));
    await settle();
    await frozen.tick(100);
  }
  assert.deepEqual(frozen.frames, [1], 'repeated source frames are never decoded twice');
  assert.equal(frozen.failures.length, 1, 'a stopped camera triggers the watchdog despite received JPEGs');
  const slow = setup();
  slow.start();
  await slow.tick(800);
  emit(slow.requests[0], 1);
  await settle();
  assert.equal(slow.frames.length, 0, 'expired segments cannot make old video look current');
  await slow.tick(100);
  assert.equal(slow.requests[0].task.destroyed, true, 'segment lifetime is bounded');
  slow.camera.stop();
  console.log('Segmented MJPEG overlap, source sequence, lifetime, cancellation and watchdog: OK');
})().catch(error => { console.error(error); process.exitCode = 1; });
