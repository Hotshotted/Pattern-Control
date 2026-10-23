// Plays the exported web build in headless Chromium and proves the wind is visible: on an empty field (?windtest: no aircraft,
// nothing else moving) two screenshots a moment apart must differ where the cream wind streaks drift, while the same field with
// ?nowind must not change at all. (Compared on the open grass left of the runway, where nothing else moves.)
//   node tools/web_wind_check.js build/web [path-to-chrome]      env: THROTTLE=4 (CPU slowdown)
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
  const results = {};
  try {
    for (const mode of ['wind', 'nowind']) {
      const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', e => errors.push(String(e)));
      await page.goto(`http://localhost:${port}/index.html?debug&windtest${mode === 'nowind' ? '&nowind' : ''}`);
      await page.waitForFunction(() => { const l = document.getElementById('loader'); return !l || l.style.display === 'none'; }, null, { timeout: 180000 });
      await page.waitForTimeout(3000);
      const cdp = await context.newCDPSession(page);
      await cdp.send('Emulation.setCPUThrottlingRate', { rate: THROTTLE });
      await page.touchscreen.tap(195, 420);            // (the first tap wakes the audio)
      await page.waitForTimeout(2500);
      await page.touchscreen.tap(195, 715);            // START SHIFT
      await page.waitForTimeout(4000);
      const a = (await page.screenshot()).toString('base64');
      await page.waitForTimeout(1500);
      const b = (await page.screenshot()).toString('base64');
      if (process.env.SAVE_SHOTS) { fs.writeFileSync(path.join(process.env.SAVE_SHOTS, mode + '_a.png'), Buffer.from(a, 'base64')); fs.writeFileSync(path.join(process.env.SAVE_SHOTS, mode + '_b.png'), Buffer.from(b, 'base64')); }
      // compare the two frames in the page: the field only (not the clock and score at the top)
      const diff = await page.evaluate(async ([a64, b64]) => {
        const load = (s) => new Promise((res) => { const i = new Image(); i.onload = () => res(i); i.src = 'data:image/png;base64,' + s; });
        const [ia, ib] = await Promise.all([load(a64), load(b64)]);
        const w = ia.width, h = ia.height;
        const get = (img) => { const c = document.createElement('canvas'); c.width = w; c.height = h; const x = c.getContext('2d'); x.drawImage(img, 0, 0); return x.getImageData(0, 0, w, h).data; };
        const da = get(ia), db = get(ib);
        // the open grass on the left of the runway: nothing else moves there (the runway lights, the chevrons, the vehicles and the clock are elsewhere)
        const y0 = Math.floor(h * 0.14), y1 = Math.floor(h * 0.95), x1 = Math.floor(w * 0.36);
        let changed = 0, peak = 0;
        for (let y = y0; y < y1; y++) {
          for (let x = 0; x < x1; x++) {
            if (x > w * 0.10 && x < w * 0.36 && y > h * 0.56 && y < h * 0.68) continue;       // (the windsock)
            const i = (y * w + x) * 4;
            const d = Math.max(Math.abs(da[i] - db[i]), Math.abs(da[i + 1] - db[i + 1]), Math.abs(da[i + 2] - db[i + 2]));
            if (d >= 5) changed++;
            if (d > peak) peak = d;
          }
        }
        return { changed, peak, w, h };
      }, [a, b]);
      results[mode] = { ...diff, errors };
      if (errors.length) fail(mode + ': page errors: ' + errors.join(' | '));
      await context.close();
    }
    console.log(JSON.stringify(results));
    if (results.wind.changed < 60) fail('the wind streaks do not visibly move: only ' + results.wind.changed + ' pixels changed');
    if (results.nowind.changed > 40) fail('?nowind should freeze the field, but ' + results.nowind.changed + ' pixels changed');
    if (results.wind.changed < 4 * (results.nowind.changed + 5)) fail('the field moves about as much without the wind (' + results.nowind.changed + ') as with it (' + results.wind.changed + ')');
    if (!failed) console.log('OK: the wind is visible (' + results.wind.changed + ' pixels moved against ' + results.nowind.changed + ' without it)');
  } catch (e) {
    fail(String(e && e.stack || e));
  }
  await browser.close();
  srv.close();
  process.exit(failed ? 1 : 0);
});
