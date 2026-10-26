// Plays the exported web build in headless Chromium at a CPU slowdown and reports how long the start takes: the page's own
// steps (download, engine start) and every step the game logs through Boot.mark (window.__boot), the time until the menu is
// there, and then the frame times of a shift (the longest frames, and how many are over 33 ms).
//   node tools/web_boot_check.js build/web [path-to-chrome]      env: THROTTLE=4, LIMIT_MENU_MS=..., SHIFT_SECONDS=20
// Exits non-zero when the menu comes later than LIMIT_MENU_MS (0 = only report).
const path = require('path');
const fs = require('fs');
const http = require('http');
let playwright;
try { playwright = require('playwright-core'); } catch (e) { playwright = require('playwright'); }
const { chromium } = playwright;

const root = path.resolve(process.argv[2] || 'build/web');
const chrome = process.argv[3] || process.env.CHROME_PATH || '/opt/pw-browsers/chromium';
const THROTTLE = +(process.env.THROTTLE || 4);
const LIMIT_MENU_MS = +(process.env.LIMIT_MENU_MS || 0);
const LIMIT_FRAME_MS = +(process.env.LIMIT_FRAME_MS || 0);
const LIMIT_BUILD_MS = +(process.env.LIMIT_BUILD_MS || 0);
const SHIFT_SECONDS = +(process.env.SHIFT_SECONDS || 20);
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.ttf': 'font/ttf', '.wav': 'audio/wav' };

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
  const browser = await chromium.launch({ executablePath: chrome, args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  try {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
    const page = await context.newPage();
    const cdp = await context.newCDPSession(page);
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: THROTTLE });
    const errors = [];
    const hitchLines = [];
    page.on('console', m => { const t = m.text(); if (t.startsWith('[hitch]') && hitchLines.length < 400) hitchLines.push(t); });
    page.on('pageerror', e => errors.push(String(e)));
    await page.addInitScript(() => {
      window.__frames = [];
      let last = 0;
      const tick = (t) => { if (last) window.__frames.push(t - last); last = t; requestAnimationFrame(tick); };
      requestAnimationFrame(tick);
    });
    const t0 = Date.now();
    await page.goto(`http://localhost:${port}/index.html?${process.env.QUERY || "debug"}`);
    // the menu is there when the game says so
    await page.waitForFunction(() => (window.__boot || []).some(m => m[0] === 'menu shown'), null, { timeout: 240000 });
    const wall = Date.now() - t0;
    const info = await page.evaluate(() => ({ boot: window.__boot, t: window.__pwT, now: performance.now() }));
    console.log(`\nSTART-UP under ${THROTTLE}x CPU slowdown (ms; page clock):`);
    console.log(`  page script ran at          ${info.t.shell.toFixed(0)}`);
    console.log(`  engine + data downloaded    ${info.t.downloaded ? info.t.downloaded.toFixed(0) : '?'}`);
    console.log(`  engine started (page)       ${info.t.started ? info.t.started.toFixed(0) : '?'}`);
    for (const m of info.boot) console.log(`  ${String(m[0]).padEnd(36)} +${String(m[1]).padStart(5)}   at page ${m[3].toFixed(0)}`);
    const menuAt = info.boot.find(m => m[0] === 'menu shown')[3];
    // what the game itself builds before it can show anything: from the engine being up to the pre-warm starting
    const upAt = info.boot.find(m => m[0] === 'engine up, scene loaded')[3];
    const builtAt = info.boot.find(m => m[0] === 'prewarm: everything shown')[3];
    console.log(`  GAME BUILD (engine up -> scene built): ${(builtAt - upAt).toFixed(0)} ms; engine boot ${upAt.toFixed(0)} ms`);
    if (LIMIT_BUILD_MS && builtAt - upAt > LIMIT_BUILD_MS) fail(`the game takes ${(builtAt - upAt).toFixed(0)} ms to build its scene (limit ${LIMIT_BUILD_MS})`);
    // the menu's own frames (?perf): every one over 33 ms in the first 20 s, and what ran in it
    await page.waitForTimeout(21000);
    const menuFrames = await page.evaluate(() => (window.__menu || []).slice());
    const worstScript = menuFrames.reduce((m, f) => Math.max(m, f[2]), 0);
    console.log(`MENU, first 20 s: ${menuFrames.length} frames over 33 ms (wall; a software renderer makes them all) or in our code; the 12 with the most game code, then the worst: ${worstScript.toFixed(1)} ms`);
    for (const f of menuFrames.slice().sort((a, b) => b[2] - a[2]).slice(0, 12)) console.log(`   t=${f[0]}s wall ${f[1]} ms, our code ${f[2]} ms: ${f[3]}`);
    if (process.env.LIMIT_MENU_FRAME_MS && worstScript > +process.env.LIMIT_MENU_FRAME_MS) fail(`a menu frame spent ${worstScript.toFixed(1)} ms in the game's own code (limit ${process.env.LIMIT_MENU_FRAME_MS})`);
    console.log(`  MENU SHOWN at ${menuAt.toFixed(0)} ms of page time (${wall} ms wall)`);
    if (LIMIT_MENU_MS && menuAt > LIMIT_MENU_MS) fail(`the menu took ${menuAt.toFixed(0)} ms (limit ${LIMIT_MENU_MS})`);
    // play a shift and look at the frames
    await page.waitForTimeout(1500);
    await page.touchscreen.tap(195, 420);
    await page.waitForTimeout(500);
    await page.evaluate(() => { window.__frames.length = 0; });
    for (let tries = 0; tries < 20; tries++) {
      await page.touchscreen.tap(195, 715);               // START SHIFT
      await page.waitForTimeout(1500);
      const playing = await page.evaluate(() => (window.__boot || []).some(m => m[0] === 'shift started'));
      if (playing) break;
    }
    await page.evaluate(() => { window.__frames.length = 0; });
    await cdp.send('Performance.enable');
    const metric = async () => { const r = await cdp.send('Performance.getMetrics'); const o = {}; for (const m of r.metrics) o[m.name] = m.value; return o; };
    const m0 = await metric();
    await page.waitForTimeout(SHIFT_SECONDS * 1000);
    const m1 = await metric();
    console.log(`\nMAIN THREAD over those ${SHIFT_SECONDS} s: busy ${(100 * (m1.TaskDuration - m0.TaskDuration) / (m1.Timestamp - m0.Timestamp)).toFixed(0)}%, script (wasm + JS) ${(100 * (m1.ScriptDuration - m0.ScriptDuration) / (m1.Timestamp - m0.Timestamp)).toFixed(0)}%, layout/style ${(100 * ((m1.LayoutDuration - m0.LayoutDuration) + (m1.RecalcStyleDuration - m0.RecalcStyleDuration)) / (m1.Timestamp - m0.Timestamp)).toFixed(0)}%`);
    const fr = await page.evaluate(() => window.__frames.slice());
    const sorted = fr.slice().sort((a, b) => b - a);
    const over = fr.filter(x => x > 33.4).length;
    const procs = await page.evaluate(() => (window.__procs || []).slice());
    if (procs.length) {
      const worst = Math.max(...procs.map(x => x[1]));
      const over = procs.reduce((a, x) => a + x[2], 0);
      const mean = procs.reduce((a, x) => a + x[0], 0) / procs.length;
      console.log(`GAME CODE per frame (every _process, no rendering) at ${THROTTLE}x: mean ${mean.toFixed(1)} ms, worst ${worst.toFixed(1)} ms, ${over} frames over 33 ms (${procs.length * 30} frames)`);
      if (process.env.REPORT) require('fs').writeFileSync(process.env.REPORT, JSON.stringify({ 'shift frame': worst }));
      if (LIMIT_FRAME_MS && worst > LIMIT_FRAME_MS) fail(`the game's own code took ${worst.toFixed(1)} ms in one frame (limit ${LIMIT_FRAME_MS})`);
    } else console.log('(no game-code timings: run with QUERY=perf)');
    // ?perf logs every frame over 50 ms with how long the game simulated it: the engine's delta clamp (1/20 s) shows here
    const sim = hitchLines.map(l => (l.match(/simulated (\d+) ms/) || [0, 0])[1]).map(Number).filter(x => x > 0);
    if (sim.length) console.log(`SIMULATED per slow frame (ms): max ${Math.max(...sim)} (the clamp is 50), ${sim.length} frames over 50 ms logged`);
    console.log(`\nFRAMES of ${SHIFT_SECONDS} s of the shift at ${THROTTLE}x: ${fr.length} frames, mean ${(fr.reduce((a, b) => a + b, 0) / Math.max(fr.length, 1)).toFixed(1)} ms, ${over} over 33 ms, worst ${sorted.slice(0, 8).map(x => x.toFixed(0)).join(' ')} ms`);
    if (errors.length) fail('page errors: ' + errors.join(' | '));
  } catch (e) {
    fail(String(e && e.stack || e));
  }
  await browser.close();
  srv.close();
  process.exit(failed ? 1 : 0);
});
