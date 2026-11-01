// Renders promo.html frame by frame into xdr-boost-promo.mp4 (1920x1080, 30 fps).
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
import { spawn } from 'node:child_process';
import puppeteer from 'puppeteer-core';

const ROOT = new URL('.', import.meta.url).pathname;
const FPS = Number(process.env.FPS || 30), DPR = Number(process.env.DPR || 1), BITRATE = process.env.BITRATE || '18M';
const [OUT = 'xdr-boost-promo.mp4', from = '0', to] = process.argv.slice(2);  // optional seconds range for test renders
const types = { '.html': 'text/html', '.js': 'text/javascript', '.png': 'image/png', '.jpg': 'image/jpeg', '.mjs': 'text/javascript' };
const server = http.createServer(async (req, res) => {
  try { const p = join(ROOT, decodeURIComponent(req.url.split('?')[0])); const body = await readFile(p); res.writeHead(200, { 'content-type': types[extname(p)] || 'application/octet-stream' }); res.end(body); }
  catch { res.writeHead(404); res.end(); }
}).listen(0);
const port = server.address().port;

const browser = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--force-color-profile=srgb', '--hide-scrollbars'] });
const page = await browser.newPage();
await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: DPR });
page.on('pageerror', e => console.error('page error:', e.message));
await page.goto(`http://localhost:${port}/promo.html?render&dpr=${DPR}`, { waitUntil: 'networkidle0' });
await page.evaluate(() => window.ready);
const duration = await page.evaluate(() => window.DURATION);
const t0 = Number(from), t1 = to ? Number(to) : duration;
const n = Math.round((t1 - t0) * FPS);

const ff = spawn('ffmpeg', ['-y', '-v', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
  '-c:v', 'h264_videotoolbox', '-b:v', BITRATE, '-profile:v', 'high', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', OUT], { stdio: ['pipe', 'inherit', 'inherit'] });
ff.on('close', code => { if (code) { console.error('ffmpeg exited', code); process.exit(1); } });
for (let i = 0; i < n; i++) {
  await page.evaluate(t => window.renderAt(t), t0 + i / FPS);
  const buf = await page.screenshot({ type: 'jpeg', quality: 98 });
  if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
  if (i % 60 === 0) console.error(`frame ${i}/${n}`);
}
ff.stdin.end();
await new Promise(r => ff.on('close', r));
await browser.close(); server.close();
console.error('wrote', OUT);
