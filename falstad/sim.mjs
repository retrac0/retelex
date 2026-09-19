// Run a CircuitJS circuit in falstad.com's simulator, headless, and record it.
//
//   node falstad/sim.mjs <circuit.txt> <seconds> <out.json> [--shot out.png] [--size 1920x1080]
//
// Opens https://www.falstad.com/circuit/circuitjs.html in headless Chromium, imports
// the circuit, checks that every element was read, runs for <seconds> of simulated
// time and records every labeled node at every time step.  out.json holds t, one
// array per label, and what the simulator reported.  Needs Node 22 or later
// (built-in WebSocket) and a Chromium binary: `chromium`, or $CHROMIUM.
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const args = process.argv.slice(2);
const opt = k => { const i = args.indexOf(k); return i < 0 ? null : args.splice(i, 2)[1]; };
const shot = opt('--shot');
const [W, H] = (opt('--size') || '640x400').split('x').map(Number);
const [file, seconds, out] = args;
if (!out) {
  console.error('usage: node falstad/sim.mjs <circuit.txt> <seconds> <out.json> [--shot out.png] [--size WxH]');
  process.exit(2);
}
const xml = readFileSync(file, 'utf8');
// labels and elements of the circuit itself, not those inside its subcircuit models
const top = xml.replace(/<ccm[\s\S]*?<\/ccm>/g, '');
const labels = [...new Set([...top.matchAll(/<ln [^>]*te="([^"]*)"/g)].map(m => m[1]))];
const nElements = [...top.matchAll(/^\s*<[A-Za-z]+ x="/gm)].length;
const sleep = ms => new Promise(r => setTimeout(r, ms));

// ---- a minimal DevTools-protocol client
const port = 9300 + Math.floor(Math.random() * 600);
const profile = mkdtempSync(join(tmpdir(), 'falstad-'));
const proc = spawn(process.env.CHROMIUM || 'chromium', ['--headless=new', '--no-sandbox',
  '--disable-gpu', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
  '--disable-backgrounding-occluded-windows', 'about:blank'], { stdio: 'ignore' });
let targets;
for (let i = 0; i < 100 && !targets; i++) {
  try { targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); }
  catch { await sleep(100); }
}
const ws = new WebSocket(targets.find(t => t.type === 'page').webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let id = 0; const pending = new Map(); const events = [];
ws.onmessage = ev => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) {
    const { res, rej } = pending.get(m.id); pending.delete(m.id);
    m.error ? rej(new Error(JSON.stringify(m.error))) : res(m.result);
  } else if (m.method) events.push(m);
};
const send = (method, params = {}) => new Promise((res, rej) => {
  const i = ++id; pending.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method, params }));
});
const evaluate = async expr => {
  const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || 'evaluate failed');
  return r.result.value;
};
const done = async code => {
  try { ws.close(); } catch {}
  const exited = new Promise(r => proc.once('exit', r));
  proc.kill();
  await Promise.race([exited, sleep(5000)]);
  try { rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }); } catch {}
  process.exit(code);
};

try {
  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: 'https://www.falstad.com/circuit/circuitjs.html' });
  // wait for the simulator AND its start-up circuit, or the start-up circuit replaces ours
  await evaluate(`new Promise(r => { const t = setInterval(() => {
    if (window.CircuitJS1 && CircuitJS1.getElements().length > 0) { clearInterval(t); r(); } }, 100); })`);
  await sleep(1000);
  await evaluate(`CircuitJS1.setSimRunning(false); CircuitJS1.importCircuit(${JSON.stringify(xml)}, false); 1`);
  await sleep(1500);
  const loaded = await evaluate(`(() => { const t = {};
    for (const e of CircuitJS1.getElements()) t[e.getType()] = (t[e.getType()] || 0) + 1;
    return { n: CircuitJS1.getElements().length, types: t, ts: CircuitJS1.getMaxTimeStep() }; })()`);
  if (loaded.n !== nElements) {
    console.error(`read ${loaded.n} elements of ${nElements}:`, JSON.stringify(loaded.types));
    await done(1);
  }
  const t0 = Date.now();
  const rec = await evaluate(`new Promise(resolve => {
    const names = ${JSON.stringify(labels)}, rec = { t: [] };
    for (const n of names) rec[n] = [];
    CircuitJS1.ontimestep = s => { rec.t.push(s.getTime()); for (const n of names) rec[n].push(s.getNodeVoltage(n)); };
    CircuitJS1.setSimRunning(true);
    let last = -1, stuck = 0;
    const poll = setInterval(() => {
      const t = CircuitJS1.getTime();
      stuck = (t === last) ? stuck + 1 : 0; last = t;
      if (t >= ${Number(seconds)} || stuck > 50 || !CircuitJS1.isRunning()) {
        clearInterval(poll); CircuitJS1.setSimRunning(false); CircuitJS1.ontimestep = null;
        rec.stalled = stuck > 50 || t < ${Number(seconds)};
        resolve(rec);
      }
    }, 200);
  })`);
  const conv = events.filter(e => e.method === 'Runtime.consoleAPICalled')
    .map(e => e.params.args.map(a => a.value).join(' '))
    .filter(s => /converge|timestep down|Singular|nan/i.test(s));
  rec.meta = { file, elements: loaded.n, types: loaded.types, timeStep: loaded.ts,
               steps: rec.t.length, simSeconds: rec.t.at(-1), wallSeconds: (Date.now() - t0) / 1000,
               solverMessages: conv.length, failures: conv.filter(s => /failed|Singular|nan/i.test(s)) };
  writeFileSync(out, JSON.stringify(rec));
  if (shot) writeFileSync(shot, Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
  console.log(`${file}: ${loaded.n} elements, ${rec.meta.steps} steps, ${(rec.meta.simSeconds * 1e3).toFixed(2)} ms ` +
              `in ${rec.meta.wallSeconds.toFixed(0)} s${rec.stalled ? ', STALLED' : ''}` +
              (rec.meta.failures.length ? `, solver: ${rec.meta.failures[0]}` : ''));
  await done(rec.stalled || rec.meta.failures.length ? 1 : 0);
} catch (e) {
  console.error(e.message);
  await done(1);
}
