// Opens every panel of the exported web build at a CPU slowdown and fails on any frame in which the game's own code (including the
// background build and the redraw of the interface) takes over 33 ms: the Airports, Upgrades and Hangar panels from the menu, the pause
// menu and the results card from a shift. (The game logs these frames with ?perf: window.__menu.)
//   node tools/web_panel_check.js build/web [path-to-chrome]      env: THROTTLE=4, LIMIT_MS=33, LIST=1
const path = require('path');
const fs = require('fs');
const http = require('http');
let playwright;
try { playwright = require('playwright-core'); } catch (e) { playwright = require('playwright'); }
const { chromium } = playwright;

const root = path.resolve(process.argv[2] || 'build/web');
const chrome = process.argv[3] || process.env.CHROME_PATH || '/opt/pw-browsers/chromium';
const THROTTLE = +(process.env.THROTTLE || 4);
const LIMIT = +(process.env.LIMIT_MS || 33);
const MEDIAN = !!process.env.REPORT;      // REPORT=file: write each panel's worst frame there and leave the limit to tools/median_gate.py (median of several runs)
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.ttf': 'font/ttf', '.wav': 'audio/wav' };
const srv = http.createServer((q, r) => {
  let p = path.join(root, decodeURIComponent(q.url.split('?')[0]));
  if (p.endsWith('/')) p += 'index.html';
  fs.readFile(p, (e, d) => { if (e) { r.writeHead(404); r.end(); return; } r.writeHead(200, { 'Content-Type': mime[path.extname(p)] || 'application/octet-stream' }); r.end(d); });
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
    const errors = [];
    page.on('pageerror', e => errors.push(String(e)));
    await page.goto(`http://localhost:${port}/index.html?perf`);
    await page.waitForFunction(() => (window.__boot || []).some(m => m[0] === 'menu shown'), null, { timeout: 240000 });
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: THROTTLE });
    await page.waitForTimeout(4000);
    await page.touchscreen.tap(195, 420);              // (the first tap wakes the audio)
    await page.waitForTimeout(1500);
    const btn = async (id) => page.evaluate((i) => window.__btn && window.__btn[i], id);
    const waitScreen = async (prefix) => page.waitForFunction((p) => (window.__screen || '').startsWith(p), prefix, { timeout: 20000 });
    const results = [];
    // what the game logged between two page times
    const framesIn = async (t0, ms) => page.evaluate(([a, b]) => (window.__menu || []).filter(f => f[4] >= a && f[4] <= b).map(f => ({ at: f[0], wall: f[1], script: f[2], what: f[3] })), [t0, t0 + ms]);
    const now = async () => page.evaluate(() => performance.now());
    const open = async (name, tapId, screenPrefix, back) => {
      const p = await btn(tapId);
      if (!p) { fail(name + ': no "' + tapId + '" button on screen'); return; }
      const t0 = await now();
      await page.touchscreen.tap(p[0], p[1]);
      await waitScreen(screenPrefix).catch(async () => fail(name + ': the panel did not open (screen ' + (await page.evaluate(() => window.__screen)) + ', ' + JSON.stringify(await page.evaluate(() => Object.keys(window.__btn || {}))) + ')'));
      await page.waitForTimeout(1600);
      const fr = await framesIn(t0, 1300);
      const worst = fr.reduce((m, f) => Math.max(m, f.script), 0);
      const w = fr.slice().sort((a, b) => b.script - a.script)[0];
      results.push([name, worst, fr.length, w ? w.what : '']);
      if (!MEDIAN && worst > LIMIT) fail(`${name}: a frame spent ${worst.toFixed(1)} ms in the game's own code (limit ${LIMIT}): ${w.what}`);
      if (back) { const b = await btn('back'); if (b) { await page.touchscreen.tap(b[0], b[1]); await waitScreen('menu').catch(() => {}); await page.waitForTimeout(1200); } }
    };
    await open('Airports', 'airports', 'select', true);
    await open('Upgrades', 'upgrades', 'upgrades', true);
    await open('Hangar', 'shop', 'list', true);
    // a shift: the pause menu, then the results card
    const play = await btn('play');
    await page.touchscreen.tap(play[0], play[1]);
    await waitScreen('play');
    await page.waitForTimeout(3500);
    const pz = await page.evaluate(() => window.__pausePos);
    if (pz) {
      for (const round of ['Pause', 'Pause (again)']) {
        const t1 = await now();
        await page.touchscreen.tap(pz[0], pz[1]); await waitScreen('pause').catch(() => fail(round + ': the pause menu did not open')); await page.waitForTimeout(1600);
        const fr = await framesIn(t1, 1300); const worst = fr.reduce((m, f) => Math.max(m, f.script), 0); const w = fr.slice().sort((a, b) => b.script - a.script)[0];
        results.push([round, worst, fr.length, w ? w.what : '']); if (!MEDIAN && worst > LIMIT) fail(`${round}: a frame spent ${worst.toFixed(1)} ms in the game's own code: ${w.what}`);
        const rs = await btn('resume'); if (rs) { await page.touchscreen.tap(rs[0], rs[1]); await page.waitForTimeout(1500); }
      }
    }
    else fail('Pause: no pause button position published');
    const t2 = await now();
    await page.evaluate(() => window.__endShift && window.__endShift());
    await waitScreen('results').catch(() => fail('Results: the results card did not open'));
    await page.waitForTimeout(2500);
    { const fr = await framesIn(t2, 1300); const worst = fr.reduce((m, f) => Math.max(m, f.script), 0); const w = fr.slice().sort((a, b) => b.script - a.script)[0]; results.push(['Results', worst, fr.length, w ? w.what : '']); if (!MEDIAN && worst > LIMIT) fail(`Results: a frame spent ${worst.toFixed(1)} ms in the game's own code: ${w.what}`); }
    console.log(`PANELS under a ${THROTTLE}x CPU slowdown: the slowest frame of the game's own code while each opens (limit ${LIMIT} ms)`);
    for (const r of results) console.log(`  ${r[0].padEnd(10)} ${r[1].toFixed(1).padStart(6)} ms   (${r[2]} logged frames)  ${r[1] > 8 ? r[3] : ''}`);
    if (process.env.REPORT) require('fs').writeFileSync(process.env.REPORT, JSON.stringify(Object.fromEntries(results.map(r => [r[0], r[1]]))));
    if (errors.length) fail('page errors: ' + errors.join(' | '));
  } catch (e) {
    fail(String(e && e.stack || e));
  }
  await browser.close();
  srv.close();
  process.exit(failed ? 1 : 0);
});
