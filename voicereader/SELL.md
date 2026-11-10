# VoiceReader Pro — hakyky pul gazanmak üçin amaly meýilnama
*(Satyşyň ýoly: gysga we hakykat)*

## 0. Ilki ýatda sakla — hakyky garaýyş
- Kod ýazmak işiň **20%-i**, müşderi tapmak **80%-i**. Programma taýýar; indi iň kyny — üns çekmek.
- Marketing etmeseň satylmaz. Nol satow = marketing ýok diýmekdir.
- Realizm: hepdede 3–5 gysga video + 2 jemgyýetde işjeňlik → 30 günde ilkinji 5–15 satow (≈ $85–255/aý). 90 günlük maksat: **50 satow ≈ $850–950**. Bu hakyky pul, ýöne «bir gije baýamak» däl.
- Üstünlik ölçegi: 1000 görünme → ≥10 «Try free» basyşy → ≥1 satow. Gelýänler bar, satylmaýan bolsa — tekibi ýa-da fiyaty düzelt. 30 günde 1000 görünme we nol satow → nişany üýtget (mysal üçin «medisinanyň talyplary» ýa-da fiyaty $9-a).

## 1. Töleg ulgamyny taýýarlamak (Gumroad — 10 minut)
1. [gumroad.com](https://gumroad.com) → mugt hasap aç.
2. **New product** → görnüşi **Digital product** → ady: `VoiceReader Pro — Lifetime License` → bahany **$19** goý («pay what you want» goýma).
3. URL-de **permalink** görner — onu `voicereader-pro` edip saýlaýagyn; ýa-da `assets/js/config.js`-daky `GUMROAD_PERMALINK` we `GUMROAD_BUY_URL`-i özünkiň bilen çalyş.
4. Önümiň mazmuny: `python tools/make_release_zip.py` işledip döredilen ZIP-i ýükle. Gumroad satyn alana awto tomly e-poçta bilen iberýär.
5. **License key**: Gumroad sanly önümler üçin awto tomly `license_key` berýär — satyn alana e-poçtada gelýär. Müşderi ony app-daki «Activate Pro» bölümine ýazýar → app `verifyLicense()` arkaly Gumroad API-da barlap açýar.
6. Düşündiriş + 2–3 screenshot (app-dan ekrany ýazga) goş; **30-day money-back** görkez — konwersiýany galdyrýar.
7. Gumroad komissiýasy ≈ 10% + 30¢. $19 → sende ≈ **$16.8**.

## 2. App-y mugt hostlamak
- **GitHub Pages**: repo → Settings → Pages → `main` şahasy / `voicereader` bukjasy → mugt https URL alynýar (mysal: `https://eliotlastdance00-art.github.io/cyber_tools/voicereader/`).
- Alternatiw mugt hostlar: **Netlify Drop** (bukja ýök gapygy ýaly drop et) ýa-da **Cloudflare Pages**.
- Haýsy host saýlasaň, `assets/js/config.js`-da `GUMROAD_BUY_URL`-i hakyky Gumroad önüm URL-iňe çalyş — ýogsam «Get Pro» düwmesi ýalan ýerde gider.
- ZIP-de oflayn ulanjak bolanlaryň görkezmesi: faýly açyp `python3 -m http.server 8080` işledip `http://localhost:8080`-a girsin (göni `file://`-de brauzer PDF workerini petikleýär).

## 3. Marketing (býujet $0, 4 hepdelik meýilnama)

**Hepdede 3 video** (TikTok / YouTube Shorts / Instagram Reels):
1. «POV: 200 sahypalyk PDF özüne okalap okalýar» — 30–60 sek ekran ýazgysy: PDF ýükle → ses saýla → Play → sözlemler ýanýar.
2. «Speechify vs. VoiceReader»: $139/aý subscription däl, bir gezek $19.
3. Talyp üçin gysga gürrüň: «45 min sagat → 15 min audio, ýolda-ýolda diňläň».
Bio-link: `…gumroad.com/l/voicereader-pro`.

**Işjeňlik ýerleri (spam däl — hakyky kömek ber, soňra önümiňi agza):**
- Reddit: r/productivity, r/students, r/ADHD, r/dyslexia, r/PKMS, r/GetStudying.
- Hacker News: «Show HN: VoiceReader — private, on-device PDF to speech (pay once)».
- Product Hunt: «coming soon» ýazgysyny 3 gün öň başlap, aýyň ikinji sişenbesinde çykar.
- Telegram/Discord: okuw toparlary, aýratyn Türkmen we rusdilli diaspora kanallary — bäsleşigi pesel.
- Quora: «How to listen to PDF while studying» ýaly soraglara jogap + çelgi.

**SEO (uzak möhlet, mugt):** Landing eýýäm taýýar; «PDF to speech one-time payment», «listen to PDF offline» ýaly long-tail ifadəlere gabat gelýär. 2 blog ýazgysy ýaz:
1. «Speechify-den ýadaňa bir gezeklik çözgüt»
2. «Görme kynçylygy bolanlar we talyplar üçin PDF-i sese öwürmek»

## 4. Aý möhlet meýilnama we karar nokatlary
| Aý | Maksat | Karar |
|---|---|---|
| Aý 1 | 12 video + 20 kömekçi jogap + Product Hunt | Nol satow → ýüzi (landing) ýa-da tekibi täzele; 1000 görkezme atymasyny yzarla |
| Aý 2 | SEO + 3 çuň forum gatyşmagy | <5 satow → nişa üýtget (med/ýuridik talyplar) |
| Aý 3 | E-mail list (mugt «1 maslahat günde») → Gumroad | 50 satow → 48 sagatlyk 10% skidka |

**Müşderiniň ynamy:** «30 gün puluňy gaýtar» ýazgysy boş söz däl — hakykatda ýerine ýetir.
**Puluň akymy:** komissiýa, gaýtarmalar we müşderi goldawy seniň jogapkärçiligiňde.

## 5. Ilkinji 7 gün üçin checklist
- [ ] Gumroad hasap + önüm + ZIP ýükle
- [ ] `config.js`: `GUMROAD_BUY_URL`, `PRICE_DISPLAY`, `OFFLINE_SECRET` (özüň üýtget!)
- [ ] App-y GitHub Pages/Netlify-da hostla; telefonda Play-iň ses çykaranyny barla
- [ ] 1 demonstrasiýa videosy taýýarla
- [ ] 5 mugt açary (`tools/make_license.py`) bilen 5 doga ynana — pikirleri we ekran ýazgylary al
- [ ] `git add voicereader && git push origin arena/91e42f35-cyber-tools`

## 6. Näme etmeli däl
- Başga önümiň göçürmesini ýasamak (hukugy howplary bar) — ýerine öz tapawudyňy (bir gezeklik töleg, gizlinlik, oflayn) nygtamaly.
- Ýalan synlar (fake reviews) — platformadan hasabyň ýapylar.
- «Hemmesi bir ýarym» — ilki satýan teklibiň biri bolsun.

**Funksiýa goşmak islegiň bolsa (bookmarks, cloud sync, themes):** diňe hepdede ≥5 satow yzygiderli bolsa goş — ýogsam wagtyňy kody däl-de, marketing işine sarp etmeli.
