# XDR Boost — How it works (v2)

51.2 s, 60 fps. Source: [`how.html`](how.html). Render: `JOBS=6 FPS=60 DPR=2 PAGE=how.html node render-par.mjs out.mp4`
(the timeline is cut into `JOBS` pieces, each rendered by its own Chrome, then joined without re-encoding).

## 1. Storyboard

| Time | Visuals | Virtual user | Linked updates | On-screen text | Transition | Sound |
|---|---|---|---|---|---|---|
| 0:00–4.6 | Starfield, grid parallax. Stepper draws node by node, labels type in. | Cursor enters at 2.6 s, hovers node 01 (it lifts), clicks at 3.7 s. | — | XDR BOOST · UNDER THE HOOD / How it works. / A hidden headroom, an invisible window, and a little math. / 01 HEADROOM · 02 EDR MODE · 03 MULTIPLY · 04 CONTROL LOOP | Camera pushes into node 01; a white token flies to the 1.0 tick of chapter 01. | — |
| 4.0–13.4 | Light card: pixel-value axis 0.0–3.4 with nits (×500). SDR bar accelerates into a wall at 1.0 and bounces. | Grabs the bar end, drags past 1.0 (wall goes translucent), pulls past 3.2; the bar stops at the panel peak. | Hero number and nits roll 1.00 → 3.20, 500 → 1,600; colour moves gray → purple → orange. | Pixels stop at 1.0. / ordinary apps stop here / panel peak · 1,600 nits / No ordinary app draws here. / equation built term by term / cyan note "Headroom is dynamic…" | EDR bar centre → token → overlay plane. | not added |
| 12.8–23.8 | Dark. macOS's overlay window floats above the MacBook Pro (M1 Pro, 2021) panel, exploded: cover glass, LCD, optical films, diffuser, mini-LED backlight. Code types line by line. | Cursor rests on each line as it takes effect, then hovers one LCD pixel. | L1: overlay rim glows, max-EDR readout rolls 1.00 → 3.20 (hero), HUD headroom. L2: chip swaps "8-bit unorm · max 255 = 1.0" → "rgba16Float · values > 1.0 allowed". L3: overlay fills, every 1.59 pulses, HUD k. L4: pixel trace (LCD → overlay → LCD → LED zone → out through the glass), then the stack collapses into "Liquid Retina XDR · light out = LED × LCD"; LEDs, panel and bloom brighten with the boost. | Wake the HDR mode. / pixel v = 0.80 / × k = 1.59 / 0.80 × 1.59 = 1.27 > 1.0 → EDR / LED zone runs above SDR level / up to 1,600 nits (peak, HDR) / footnote on sources | The 1.59 literal → token → curve endpoint. | not added |
| 23.2–36.2 | Light. Graph: red dashed k = L, gradient k = L^(1/2.5). Presets on the right. | Drags the point 1.0 → 2.0 (pause) → 3.2; hovers the 2.0× row (tooltip 2.0^(1/2.5) = 1.3195) and clicks it; the point springs back to 2.0. | Hero k, tooltip, preset outline, HUD all follow the point; a hollow red ring shows the naive k at the same L. | Multiply, in the right space. / proof panel at 2.0× / derivation | Curve endpoint → token → loop token. | not added |
| 35.6–46.2 | Dark. Loop SENSE → CLAMP → APPLY → WAIT, shown 4× slower, with a timeline (cyan headroom, gradient boost, frames at 5 fps). | Hovers the headroom drop, then APPLY (tooltip k = 2.0^(1/2.5) = 1.32). | At τ = 0.6 s macOS reports headroom 2.00; the next SENSE (τ = 1.0 s) reads it, CLAMP gives 2.0, APPLY sets k = 1.32, the boost line steps down. At τ = 1.45 s the frames stop; boost falls to 1.0× and the bloom goes out. | A loop, not a switch. / t = … s / stop drawing → macOS falls back to SDR / thermal ≥ serious → overlay closes / safe by design | Frozen loop token → token → MacBook screen. | not added |
| 45.6–51.2 | Ghost + MacBook (real app frames), bloom rises behind the title. | — | — | XDR Boost / Your display already had the brightness. Now you can use it. / github.com/fl03er/xdr-boost (typed) | hold | — |

The HUD `headroom · boost · k · nits` is visible from 13.4 s to 45.6 s and is computed from the same state
functions as the chapters (`hudState` in `how.html`).

## 2. Every number on screen

All come from `SDR_NITS = 500`, `PEAK_NITS = 1600`, `GAMMA = 2.5`, `kOf(L) = L^(1/2.5)`, `nits = 500·L`.
The page throws on load if any of the checks below fail.

| Shown | Derivation | Check |
|---|---|---|
| 1.0 = 500 nits, ticks 0 / 500 / 1,000 / 1,500 | value × 500 | ✓ |
| headroom 3.2, 3.20, 1,600 nits | 1600 / 500 = 3.2 | ✓ locked |
| max EDR value 1.00 → 3.20 | headroom before / after EDR mode | ✓ locked |
| 1.0× → 1.00 · 500 nits | 1.0^0.4 = 1.000 | ✓ locked |
| 2.0× → 1.32 · 1,000 nits | 2.0^0.4 = 1.3195 | ✓ locked |
| 3.2× → 1.59 · 1,600 nits; clear = (1.59, 1.59, 1.59) | 3.2^0.4 = 1.5925 | ✓ locked |
| tooltip 2.0^(1/2.5) = 1.3195 | 4 decimals of the same | ✓ |
| drag tooltip L = 2.60 → k = 1.47 (any L) | live kOf(L) | ✓ computed |
| pixel v = 0.80, 0.80 × 1.59 = 1.27 | example pixel; 0.8 × 1.5925 = 1.274 | ✓ derived |
| naive k = L = 2.00; correct k = 1.32; ceiling 1.59 | at L = 2.0; ceiling = kOf(3.2) | ✓ derived |
| SENSE headroom 3.20 / 2.00; CLAMP min(3.2, 3.20) = 3.2, min(3.2, 2.00) = 2.0; APPLY k = 1.59 / 1.32; WAIT 0.5 s | loop with setting 3.2 | ✓ |
| frames sent · 5 fps; every 0.5 s | app constants | ✓ |
| t = … s, shown 4× slower | loop time τ = (video time − 1.4 s) / 4 | label states the slow-down |

Notes:
- The brief's example tooltip "L 2.02 → k 1.33" is off by one: 2.02^0.4 = 1.3248, so the video shows 1.32.
- The headroom drop to 2.00 is an example value, labelled "reported by macOS"; it is not tied to a cause (thermal
  pressure in the app closes the overlay instead, which the video says separately).
- The 0.1 s delay before the SDR fall-back is drawn qualitatively; no time is printed for it.

## 3. The panel layers in chapter 02

Apple's specifications for the MacBook Pro (14- and 16-inch, 2021) give a mini-LED backlight with local dimming
and an LCD, 500 nits SDR, 1,000 nits sustained and 1,600 nits peak (HDR content only), and 1,000,000:1 contrast.
Apple does not publish the film stack of this panel, so the diffuser and optical films are drawn as in a typical
mini-LED LCD, and the video says so in a footnote. Apple's Pro Display XDR Technology Overview (2020) describes the
same idea for its sibling display: a locally dimmed LED backlight, a reflective diffuser plate, a colour
transformation sheet, a micro-lens array, an LCD panel with a compensation polarizer, and cover glass, with a timing
controller that drives the LEDs and the LCD "as two distinct displays".

"LED zone runs above SDR level" follows from light out = LED × LCD: the LCD cannot pass more than all of the
light, so anything brighter than SDR white needs more light from the backlight. How the panel splits the work
between the two is not public, so the video shows no numbers for it.

## 4. What was left out
- Sound: not added.
- HDR (HEVC 10-bit PQ) version: not made. The pipeline captures sRGB screenshots, so marking the outro as HDR would
  only fake it.
