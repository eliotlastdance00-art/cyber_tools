# VoiceReader Pro

Turn any PDF, document or text into audio — entirely on the user's device. Private by design: no uploads, no servers, no tracking. Free tier included; Pro is a **one-time lifetime payment** sold via Gumroad.

## What's inside

| File | Purpose |
|---|---|
| `index.html` | Landing page (sales page) — pricing, FAQ, buy buttons |
| `app.html` | The actual reader app |
| `assets/js/app.js` | Reader logic: sentence splitting, highlighting, Speech Synthesis, PDF extraction |
| `assets/js/license.js` | License verification (Gumroad API + offline FNV-1a fallback) |
| `assets/js/config.js` | **Edit me:** Gumroad permalink, buy URL, price, offline secret, free limit |
| `assets/js/vendor/pdf.min.mjs` | PDF.js 4.10.38 (extraction) |
| `assets/js/vendor/pdf.worker.min.mjs` | PDF.js worker |
| `manifest.webmanifest` + `sw.js` | Installable PWA, offline app shell |
| `tools/make_license.py` | Generate offline license keys (demo/gift keys) |
| `tools/make_release_zip.py` | Build the ZIP you upload to Gumroad |
| `SELL.md` | **How to actually sell it** — Gumroad setup, hosting, 4-week marketing plan, realistic expectations |

## Run locally

```bash
cd voicereader
python3 -m http.server 8080
# open http://localhost:8080
```

Opening `index.html` directly via `file://` mostly works, but the browser blocks the PDF.js module/worker on `file://` URLs — use the local server (or the hosted deployment) for PDF support.

## How Pro unlocking works

1. Buyer pays on Gumroad → receives a `license_key` by email.
2. In the app, **Unlock Pro → paste key → Activate**.
3. `license.js` POSTs to Gumroad's `licenses/verify` endpoint with `product_permalink` from `config.js`.
   - `success: true` → Pro activates (stored in `localStorage`).
   - Rejected → error shown.
   - Gumroad unreachable (offline/CORS/timeout) → falls back to the offline checksum, validated with `OFFLINE_SECRET` (same algorithm as `tools/make_license.py`).

> The offline fallback is obfuscation, not real security — anyone can read the JS. Gumroad is the source of truth; keep the price low and the refund policy honest instead of relying on DRM.

Free tier: first **1,500 characters** per document readable; the library save is Pro-only. Both limits live in `app.js` (`FREE_CHAR_LIMIT` in `config.js`).

## Deploy (free)

- **GitHub Pages**: repo Settings → Pages → branch `arena/91e42f35-cyber-tools` (or after merge, `main`), folder `/voicereader`? Pages serves from root or `/docs` only — easiest is Source = repo root, then the app is at `https://<user>.github.io/<repo>/voicereader/`.
- Or **Netlify Drop**: drag the `voicereader` folder onto https://app.netlify.com/drop — done.

After deploying anywhere, update `GUMROAD_BUY_URL` in `config.js` to your real product link.

## Test checklist

- [ ] Paste text → Play → sentences highlight, voice speaks
- [ ] Upload a text-based PDF → text extracted, plays
- [ ] Speed/pitch sliders audible
- [ ] Doc > 1,500 chars on free tier → modal appears on Play
- [ ] Valid Gumroad key (or `tools/make_license.py` key) → Pro activates, library unlocks
- [ ] Reload page → Pro persists
