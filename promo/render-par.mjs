// Renders a page in parallel chunks, then joins them: JOBS=6 FPS=60 DPR=2 PAGE=how.html node render-par.mjs out.mp4
import { spawn } from 'node:child_process';
import { writeFile, rm, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import puppeteer from 'puppeteer-core';

const OUT = process.argv[2] || 'out.mp4', JOBS = Number(process.env.JOBS || 6), FPS = Number(process.env.FPS || 30);
const ROOT = new URL('.', import.meta.url).pathname;
// read the duration from the page itself
const browser = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
const page = await browser.newPage();
await page.goto(`file://${join(ROOT, process.env.PAGE || 'promo.html')}?render`);
await page.waitForFunction(() => window.DURATION);
const duration = await page.evaluate(() => window.DURATION);
await browser.close();

const frames = Math.round(duration * FPS), per = Math.ceil(frames / JOBS), dir = await mkdtemp(join(tmpdir(), 'render-'));
const parts = [];
await Promise.all(Array.from({ length: JOBS }, (_, i) => {
  const a = i * per, b = Math.min(frames, a + per); if (a >= b) return;
  const file = join(dir, `part${i}.mp4`); parts[i] = file;
  return new Promise((res, rej) => {
    const p = spawn('node', [join(ROOT, 'render.mjs'), file, String(a / FPS), String(b / FPS)], { env: process.env, stdio: ['ignore', 'inherit', 'pipe'] });
    p.stderr.on('data', d => { const m = String(d).match(/frame (\d+)\/(\d+)/); if (m) console.error(`job ${i}: ${m[1]}/${m[2]}`); else process.stderr.write(d); });
    p.on('close', code => code ? rej(new Error(`job ${i} failed`)) : res());
  });
}));
await writeFile(join(dir, 'list.txt'), parts.filter(Boolean).map(f => `file '${f}'`).join('\n'));
await new Promise((res, rej) => spawn('ffmpeg', ['-y', '-v', 'error', '-f', 'concat', '-safe', '0', '-i', join(dir, 'list.txt'), '-c', 'copy', '-movflags', '+faststart', OUT], { stdio: 'inherit' })
  .on('close', c => c ? rej(new Error('concat failed')) : res()));
await rm(dir, { recursive: true });
console.error('wrote', OUT, `(${frames} frames, ${JOBS} jobs)`); process.exit(0);
