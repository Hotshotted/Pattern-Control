// Plays the exported web build in headless Chromium and checks that sound really comes out.
//   node tools/web_audio_check.js build/web [path-to-chrome]
// The check taps the page like a phone would (browsers keep audio suspended until a gesture), then listens to
// everything that reaches the AudioContext destination: the menu music must be audible after the first tap and the
// shift music (plus engine hums and effects) after PLAY. Exits non-zero if either is silent.
const path = require('path');
const fs = require('fs');
const http = require('http');
let playwright;
try { playwright = require('playwright-core'); } catch (e) { playwright = require('playwright'); }
const { chromium } = playwright;

const root = path.resolve(process.argv[2] || 'build/web');
const chrome = process.argv[3] || process.env.CHROME_PATH || '/opt/pw-browsers/chromium';
const THRESHOLD = 0.0015;      // peak sample level (the quietest layer, the menu bed, is about -19 dB)
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.ttf': 'font/ttf' };

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
  const browser = await chromium.launch({ executablePath: chrome, args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  try {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(String(e)));
    await page.addInitScript(() => {
      window.__audio = { peak: 0, running: false, nodes: 0 };
      const orig = AudioNode.prototype.connect;
      AudioNode.prototype.connect = function (dest, ...rest) {
        try {
          if (dest instanceof AudioDestinationNode && !this.__tee) {
            this.__tee = true;
            window.__audio.nodes++;
            const ctx = this.context;
            const an = ctx.createAnalyser(); an.fftSize = 1024;
            orig.call(this, an);
            const buf = new Float32Array(an.fftSize);
            setInterval(() => {
              if (ctx.state === 'running') window.__audio.running = true;
              an.getFloatTimeDomainData(buf);
              let m = 0; for (const v of buf) m = Math.max(m, Math.abs(v));
              window.__audio.peak = Math.max(window.__audio.peak, m);
            }, 40);
          }
        } catch (e) {}
        return orig.call(this, dest, ...rest);
      };
    });
    await page.goto(`http://localhost:${port}/index.html`);
    // Wait until the game has started (the loading page is gone).
    await page.waitForFunction(() => { const l = document.getElementById('loader'); return !l || l.style.display === 'none'; }, null, { timeout: 120000 });
    await page.waitForTimeout(3000);
    const peak = async () => page.evaluate(() => { const p = window.__audio.peak; window.__audio.peak = 0; return p; });
    await peak();
    // The first tap: it skips the logo intro and unlocks audio; the menu music fades in behind it.
    await page.touchscreen.tap(195, 420);
    let menu = 0;
    for (let i = 0; i < 12 && menu < THRESHOLD; i++) { await page.waitForTimeout(1000); menu = Math.max(menu, await peak()); }
    // PLAY: a shift starts (music, hums, the press sound).
    await page.touchscreen.tap(195, 430);
    let shift = 0;
    for (let i = 0; i < 12 && shift < THRESHOLD; i++) { await page.waitForTimeout(1000); shift = Math.max(shift, await peak()); }
    const info = await page.evaluate(() => ({ running: window.__audio.running, nodes: window.__audio.nodes }));
    console.log(JSON.stringify({ menuPeak: menu, shiftPeak: shift, ...info, errors }));
    if (!info.running || info.nodes === 0) { console.error('FAIL: no running audio context reached the speakers'); failed = true; }
    if (menu < THRESHOLD) { console.error('FAIL: the menu is silent (peak ' + menu + ')'); failed = true; }
    if (shift < THRESHOLD) { console.error('FAIL: the shift is silent (peak ' + shift + ')'); failed = true; }
    if (errors.length) { console.error('FAIL: page errors: ' + errors.join(' | ')); failed = true; }
    if (!failed) console.log('OK: sound comes out of the web build (menu and shift)');
  } catch (e) {
    console.error('FAIL: ' + e); failed = true;
  }
  await browser.close();
  srv.close();
  process.exit(failed ? 1 : 0);
});
