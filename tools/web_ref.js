// The reference workload of the CI timing gates. A frame time in the game's own code depends on how fast the runner is at that moment
// (a shared VM: the same build measures 22 to 37 ms), so each check first times a fixed piece of work in the same browser, under the same CPU
// slowdown, and judges every frame measurement as a RATIO to it (tools/median_gate.py). The work is a mix of what the game does: a
// WebAssembly loop (integer hashing, memory, float sqrt), 4x4 matrix transforms on typed arrays, and Map / array / object churn
// like the script interpreter's. It never changes: its cost is the unit.
//
//   const { measureReference } = require('./web_ref.js');
//   const ms = await measureReference(page);     // median of REPS timed runs, in milliseconds, on this page (about:blank)
//
// `node tools/web_ref.js [chrome]` prints the reference under THROTTLE (default 4) a few times.

const REPS = 9;

// Runs inside the page. `reps` timed repetitions after two warm-ups; returns every repetition's milliseconds.
function pageWorkload(reps) {
  // ---- WebAssembly: (func (param n i32) (result f64)), built by hand ----
  const sleb = (v) => { const out = []; for (;;) { const b = v & 0x7f; v >>= 7; if ((v === 0 && !(b & 0x40)) || (v === -1 && (b & 0x40))) { out.push(b); return out; } out.push(b | 0x80); } };
  const uleb = (v) => { const out = []; do { let b = v & 0x7f; v >>>= 7; if (v) b |= 0x80; out.push(b); } while (v); return out; };
  const f64 = (x) => Array.from(new Uint8Array(new Float64Array([x]).buffer));
  const body = [
    0x02, 0x02, 0x7f, 0x01, 0x7c,                       // locals: 2 x i32 (i = 1, h = 2), 1 x f64 (x = 3)
    0x44, ...f64(1.0), 0x21, 0x03,                       // x = 1.0
    0x03, 0x40,                                          // loop
    0x20, 0x02, 0x20, 0x02, 0x41, 0x05, 0x74, 0x73, 0x20, 0x01, 0x6a, 0x21, 0x02,     // h = (h ^ (h << 5)) + i
    0x20, 0x02, 0x41, ...sleb(65532), 0x71, 0x20, 0x02, 0x36, 0x02, 0x00,              // mem[h & 65532] = h
    0x20, 0x03, 0x44, ...f64(1.0000001), 0xa2, 0x44, ...f64(0.5), 0xa0, 0x9f,          // sqrt(x * 1.0000001 + 0.5)
    0x20, 0x02, 0x41, 0x03, 0x76, 0x41, ...sleb(65532), 0x71, 0x28, 0x02, 0x00, 0x41, ...sleb(0x7fffffff), 0x71, 0xb7,  // + float(mem[(h >> 3) & 65532] & 0x7fffffff)
    0x44, ...f64(1e-9), 0xa2, 0xa0, 0x21, 0x03,                                         //   * 1e-9
    0x20, 0x01, 0x41, 0x01, 0x6a, 0x22, 0x01, 0x20, 0x00, 0x48, 0x0d, 0x00,            // i++; loop while i < n
    0x0b,                                                // end loop
    0x20, 0x03, 0x0b,                                    // return x
  ];
  const sec = (id, bytes) => [id, ...uleb(bytes.length), ...bytes];
  const mod = new Uint8Array([
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    ...sec(1, [0x01, 0x60, 0x01, 0x7f, 0x01, 0x7c]),
    ...sec(3, [0x01, 0x00]),
    ...sec(5, [0x01, 0x00, 0x01]),
    ...sec(7, [0x01, 0x03, 0x72, 0x75, 0x6e, 0x00, 0x00]),
    ...sec(10, [0x01, ...uleb(body.length), ...body]),
  ]);
  const wasmRun = new WebAssembly.Instance(new WebAssembly.Module(mod)).exports.run;
  // ---- typed-array matrix transforms ----
  const A = new Float32Array(16), B = new Float32Array(16), C = new Float32Array(16);
  for (let i = 0; i < 16; i++) { A[i] = 0.01 * (i + 1); B[i] = 0.02 * (16 - i); }
  const matmul = (n) => { for (let k = 0; k < n; k++) { for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) { let s = 0; for (let j = 0; j < 4; j++) s += A[r * 4 + j] * B[j * 4 + c]; C[r * 4 + c] = s; } A[k & 15] = C[(k * 5) & 15] * 0.5 + 0.01; } return C[3]; };
  // ---- Map / array / object churn ----
  const churn = (n) => { const m = new Map(); const arr = []; let acc = 0; for (let i = 0; i < n; i++) { m.set('k' + (i & 1023), i); acc += m.get('k' + ((i * 7) & 1023)) | 0; arr.push({ a: i, b: [i, i + 1] }); if (arr.length > 256) arr.length = 0; } return acc + arr.length; };
  const once = () => { const t0 = performance.now(); const s = wasmRun(1500000) + matmul(9000) + churn(24000); const t1 = performance.now(); if (!isFinite(s)) throw new Error('reference workload broke'); return t1 - t0; };
  once(); once();
  const out = [];
  for (let i = 0; i < reps; i++) out.push(once());
  return out;
}

async function measureReference(page, reps = REPS) {
  const all = await page.evaluate(pageWorkload, reps);
  const sorted = all.slice().sort((a, b) => a - b);
  return { ms: sorted[sorted.length >> 1], all };
}

module.exports = { measureReference, pageWorkload };

if (require.main === module) {
  let playwright;
  try { playwright = require('playwright-core'); } catch (e) { playwright = require('playwright'); }
  (async () => {
    const chrome = process.argv[2] || process.env.CHROME_PATH || '/opt/pw-browsers/chromium';
    const THROTTLE = +(process.env.THROTTLE || 4);
    const browser = await playwright.chromium.launch({ executablePath: chrome, args: ['--no-sandbox'] });
    const context = await browser.newContext();
    const page = await context.newPage();
    const cdp = await context.newCDPSession(page);
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: THROTTLE });
    for (let k = 0; k < 3; k++) {
      const r = await measureReference(page);
      console.log(`reference at ${THROTTLE}x: median ${r.ms.toFixed(1)} ms   runs ${r.all.map(x => x.toFixed(1)).join(', ')}`);
    }
    await browser.close();
  })();
}
