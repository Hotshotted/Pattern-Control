// Plays the exported web build in headless Chromium, under CPU throttling (to mimic a phone), RECORDS what reaches the
// speakers and checks it:
//   node tools/web_audio_check.js build/web [path-to-chrome]      env: THROTTLE=4 (CPU slowdown), PLAYBACK_LOG=1
// * sound really comes out (menu music after the first tap, the shift music after PLAY),
// * no discontinuities (clicks / pops), no dropouts (runs of exact silence in the middle of the music),
//   no repeated buffers (an underrun replaying the last block), no clipping,
// * background audio: when the page is hidden / blurred every AudioContext is suspended, the output goes silent and the
//   game pauses; it stays silent after the page is visible again until the player taps Resume.
// Exits non-zero on any failure.
const path = require('path');
const fs = require('fs');
const http = require('http');
let playwright;
try { playwright = require('playwright-core'); } catch (e) { playwright = require('playwright'); }
const { chromium } = playwright;

const root = path.resolve(process.argv[2] || 'build/web');
const chrome = process.argv[3] || process.env.CHROME_PATH || '/opt/pw-browsers/chromium';
const THROTTLE = +(process.env.THROTTLE || 4);
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.ttf': 'font/ttf' };

// ---- analysis of a recording (mono Float32Array at `rate`) ----
function analyse(x, rate, from, to) {
  const a = Math.max(0, Math.floor(from * rate)), b = Math.min(x.length, Math.floor(to * rate));
  let clicks = 0, clipped = 0, repeated = 0, dropouts = 0, peak = 0, maxClick = 0;
  // clicks: a step far bigger than the recent steps (the signal is soft: everything is low-passed)
  const hist = new Float32Array(32); let hp = 0;
  for (let i = a + 1; i < b; i++) {
    const d = Math.abs(x[i] - x[i - 1]);
    let m = 0; for (let k = 0; k < 32; k++) m = Math.max(m, hist[k]);
    if (d > 4 * m + 0.03 && i - a > 64) { clicks++; maxClick = Math.max(maxClick, d); }
    hist[hp] = d; hp = (hp + 1) & 31;
    const v = Math.abs(x[i]); peak = Math.max(peak, v); if (v >= 0.999) clipped++;
  }
  // repeated buffers: two consecutive identical 128-sample blocks that are not silence
  for (const N of [128, 256, 512]) {
    for (let s = a; s + 2 * N <= b; s += N) {
      let same = true, e = 0;
      for (let k = 0; k < N; k++) { if (x[s + k] !== x[s + N + k]) { same = false; break; } e += x[s + k] * x[s + k]; }
      if (same && e / N > 1e-8) repeated++;
    }
  }
  // dropouts: runs of exact zeros longer than 20 ms while the music should be playing
  let run = 0; const min = Math.floor(0.02 * rate);
  for (let i = a; i < b; i++) { if (x[i] === 0) { run++; } else { if (run >= min) dropouts++; run = 0; } }
  if (run >= min) dropouts++;
  return { clicks, maxClick: +maxClick.toFixed(3), clipped, repeated, dropouts, peak: +peak.toFixed(3) };
}

const srv = http.createServer((q, r) => {
  let p = path.join(root, decodeURIComponent(q.url.split('?')[0]));
  if (p.endsWith('/')) p += 'index.html';
  fs.readFile(p, (e, d) => {
    if (e) { r.writeHead(404); r.end(); return; }
    r.writeHead(200, { 'Content-Type': mime[path.extname(p)] || 'application/octet-stream' });
    r.end(d);
  });
});

srv.listen(0, async () => {
  const port = srv.address().port;
  let failed = false;
  const fail = (m) => { console.error('FAIL: ' + m); failed = true; };
  const browser = await chromium.launch({ executablePath: chrome, args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=document-user-activation-required'] });
  try {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(String(e)));
    await page.addInitScript(() => {
      // Tee everything that reaches an AudioContext destination into an AudioWorklet recorder (it runs on the audio thread, so
      // a busy main thread cannot make it miss samples).
      window.__rec = { music: [], sfx: [], rate: 0, tees: 0 };
      const code = 'class R extends AudioWorkletProcessor{constructor(){super();this.b=new Float32Array(4096);this.n=0;}process(i){const c=i[0];if(c&&c.length){const l=c[0];for(let k=0;k<l.length;k++){let v=l[k];if(c.length>1)v=(v+c[1][k])*0.5;this.b[this.n++]=v;if(this.n===4096){this.port.postMessage(this.b.slice(0));this.n=0;}}}return true;}}registerProcessor("rec",R);';
      const url = URL.createObjectURL(new Blob([code], { type: 'text/javascript' }));
      const orig = AudioNode.prototype.connect;
      const rigs = new Map();     // per context: { node, pending: [sources] } (one recorder per context sums every source)
      AudioNode.prototype.connect = function (dest, ...rest) {
        try {
          if (dest instanceof AudioDestinationNode) {
            const ctx = this.context, src = this;
            let rig = rigs.get(ctx);
            if (!rig) {
              rig = { node: null, pending: [] };
              rigs.set(ctx, rig);
              window.__rec.tees++;
              window.__rec.rate = ctx.sampleRate;
              ctx.audioWorklet.addModule(url).then(() => {
                rig.node = new AudioWorkletNode(ctx, 'rec', { numberOfOutputs: 0 });
                rig.node.port.onmessage = (e) => { (ctx.__pw ? window.__rec.music : window.__rec.sfx).push(e.data); };
                for (const s of rig.pending) orig.call(s, rig.node);
                rig.pending = [];
              });
            }
            if (rig.node) orig.call(src, rig.node); else rig.pending.push(src);
          }
        } catch (e) {}
        return orig.call(this, dest, ...rest);
      };
    });
    const cdp = await context.newCDPSession(page);
    await page.goto(`http://localhost:${port}/index.html?debug`);
    await page.waitForFunction(() => { const l = document.getElementById('loader'); return !l || l.style.display === 'none'; }, null, { timeout: 180000 });
    await page.waitForTimeout(3000);
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: THROTTLE });   // a phone is several times slower than this machine
    const marks = {};
    const nowSec = async () => page.evaluate(() => Math.max(window.__rec.music.length, window.__rec.sfx.length) * 4096 / (window.__rec.rate || 44100));
    const state = async () => page.evaluate(() => ({ ctx: (window.__ctxs || []).map(c => c.state), game: window.__pw || null }));
    // 1. the first tap, then the menu music
    marks.tap = await nowSec();
    await page.touchscreen.tap(195, 420);
    await page.waitForTimeout(9000);
    marks.menuEnd = await nowSec();
    // 2. a few UI sounds in the menu (taps on the round buttons and back)
    await page.touchscreen.tap(60, 700); await page.waitForTimeout(900);
    await page.touchscreen.tap(30, 40); await page.waitForTimeout(900);
    // 3. a shift
    marks.play = await nowSec();
    await page.touchscreen.tap(195, 430);
    await page.waitForTimeout(14000);
    marks.shiftEnd = await nowSec();
    // 4. background audio: hide the page
    const before = await state();
    marks.hide = await nowSec();
    await page.evaluate(() => {
      Object.defineProperty(document, 'hidden', { configurable: true, get: () => true });
      Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
      document.dispatchEvent(new Event('visibilitychange'));
      window.dispatchEvent(new Event('pagehide'));
      window.dispatchEvent(new Event('blur'));
    });
    await page.waitForTimeout(3000);
    marks.hidden = await nowSec();
    await page.waitForTimeout(3000);
    marks.hiddenEnd = await nowSec();
    const during = await state();
    // 5. visible again: still silent until the player taps Resume
    await page.evaluate(() => {
      Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });
      Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' });
      document.dispatchEvent(new Event('visibilitychange'));
      window.dispatchEvent(new Event('focus'));
    });
    await page.waitForTimeout(3000);
    marks.visible = await nowSec();
    await page.waitForTimeout(2000);
    marks.visibleEnd = await nowSec();
    const visibleState = await state();
    // 6. Resume
    const rp = visibleState.game && visibleState.game.resume ? visibleState.game.resume : [195, 311];
    await page.touchscreen.tap(rp[0], rp[1]);
    marks.resume = await nowSec();
    await page.waitForTimeout(7000);
    marks.end = await nowSec();
    const after = await state();
    await page.screenshot({ path: path.join(process.env.TMPDIR || '/tmp', 'web_audio_check.png') });

    const pull = async (which) => {
      const r = await page.evaluate((w) => { const ch = window.__rec[w]; const n = ch.reduce((t, c) => t + c.length, 0); const all = new Float32Array(n); let o = 0; for (const c of ch) { all.set(c, o); o += c.length; } let bin = ''; const u8 = new Uint8Array(all.buffer); for (let i = 0; i < u8.length; i += 0x8000) bin += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000)); return btoa(bin); }, which);
      const b = Buffer.from(r, 'base64');
      return new Float32Array(b.buffer, b.byteOffset, b.length / 4);
    };
    const rate = await page.evaluate(() => window.__rec.rate || 44100);
    const xm = await pull('music');      // the page's looping layers (music, fog, engines)
    const xs = await pull('sfx');        // the engine's one-shots
    const x = xm.length >= xs.length ? xm : xs;
    const secs = Math.max(xm.length, xs.length) / rate;
    // The music stream must be perfectly clean (it is a continuous bed); the one-shots may have silence but no clicks.
    const menu = analyse(xm.length ? xm : x, rate, marks.tap + 3, marks.menuEnd);
    const shift = analyse(xm.length ? xm : x, rate, marks.play + 2, marks.shiftEnd);
    const shots = analyse(xs, rate, marks.tap + 2, marks.shiftEnd);
    const peakIn = (arr, a, b) => { let m = 0; for (let i = Math.floor(a * rate); i < Math.min(arr.length, Math.floor(b * rate)); i++) m = Math.max(m, Math.abs(arr[i])); return m; };
    const both = (a, b) => Math.max(peakIn(xm, a, b), peakIn(xs, a, b));
    const hiddenPeak = both(marks.hide + 0.5, marks.hiddenEnd)   // (suspended contexts record nothing, so this window is short or empty);
    const visiblePeak = both(marks.hiddenEnd + 0.2, marks.visibleEnd);
    const afterPeak = both(marks.resume + 1.5, marks.end);
    const menuAll = Math.max(peakIn(xm, marks.tap + 3, marks.menuEnd), peakIn(xs, marks.tap, marks.menuEnd));
    const shiftAll = Math.max(peakIn(xm, marks.play + 2, marks.shiftEnd), peakIn(xs, marks.play, marks.shiftEnd));
    const out = { rate, seconds: +secs.toFixed(1), throttle: THROTTLE, menu, shift, shots, musicStream: xm.length > 0, peaks: { hidden: +hiddenPeak.toFixed(4), visibleBeforeResume: +visiblePeak.toFixed(4), afterResume: +afterPeak.toFixed(4) }, game: { before: before.game, hidden: during.game, visible: visibleState.game, after: after.game }, ctx: { before: before.ctx, hidden: during.ctx, visible: visibleState.ctx, after: after.ctx }, errors };
    console.log(JSON.stringify(out));
    if (process.env.SAVE_WAV) { fs.writeFileSync(process.env.SAVE_WAV, Buffer.from(xm.buffer, xm.byteOffset, xm.byteLength)); }
    // ---- verdicts ----
    if (menuAll < 0.0015) fail('the menu is silent (peak ' + menuAll + ')');
    if (shiftAll < 0.0015) fail('the shift is silent (peak ' + shiftAll + ')');
    if (shots.clicks > 0) fail('one-shots: ' + shots.clicks + ' discontinuities (largest step ' + shots.maxClick + ')');
    if (shots.clipped > 0) fail('one-shots: ' + shots.clipped + ' clipped samples');
    if (shots.repeated > 0) fail('one-shots: ' + shots.repeated + ' repeated buffers');
    for (const [name, r] of [['menu', menu], ['shift', shift]]) {
      if (r.clicks > 0) fail(name + ': ' + r.clicks + ' discontinuities (largest step ' + r.maxClick + ')');
      if (r.repeated > 0) fail(name + ': ' + r.repeated + ' repeated buffers');
      if (r.dropouts > 0) fail(name + ': ' + r.dropouts + ' dropouts (runs of exact silence)');
      if (r.clipped > 0) fail(name + ': ' + r.clipped + ' clipped samples');
    }
    if (hiddenPeak > 0.0005) fail('sound kept playing while the page was hidden (peak ' + hiddenPeak + ')');
    if (visiblePeak > 0.0005) fail('sound came back by itself when the page became visible (peak ' + visiblePeak + ')');
    if (!(during.game && during.game.paused)) fail('the game did not pause when the page was hidden');
    if (!(during.game && during.game.muted)) fail('the Master bus was not muted when the page was hidden');
    if ((during.ctx || []).some(s => s === 'running')) fail('an AudioContext was still running while the page was hidden');
    if (afterPeak < 0.0015) fail('sound did not come back after Resume (peak ' + afterPeak + ')');
    if (after.game && (after.game.paused || after.game.muted)) fail('the game is still paused or muted after Resume');
    if (errors.length) fail('page errors: ' + errors.join(' | '));
    if (!failed) console.log('OK: clean sound under CPU throttling, and background audio is held');
  } catch (e) {
    fail(String(e && e.stack || e));
  }
  await browser.close();
  srv.close();
  process.exit(failed ? 1 : 0);
});
