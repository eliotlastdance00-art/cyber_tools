# VoiceReader — «Programma ýükländen soň açylmady»: anyliz

> Sene: 2026-11-10 · Barlanan kommit: `f7e8740` (main) · Barlanan CI run: `42829824679`
> Bu dokument **testler günäkli däl** diýip başlaýar we soňra hakyky sebäpleri
> ähmiýeti boýunça sanap geçýär. Ahyrynda: nähili dogry gurnamaly (ädim-ädim).

---

## 0. Gysgaça jogap

- **`flutter test` bu problema günäli däl.** Testler diňe Dart logikasyny
  kompýuteriň içinde barlaýar. Ol APK-ny gurmaýar, sign etmeýär, telefona
  gurnaýyş etmeýär. Şonuň üçin «testler ýaşyl = telefonda işleýär» diýen
  netije **ýok**. (Şeýle-de bolsa: häzirki test sany 1, coverage ~0 — Phase 0
  üçin ýeterlik, ýöne hiç zady subut etmeýär.)
- «Açylmady» adatça **3 sany düýp sebäbiň** biri:
  1. telefona **APK däl-de `.zip` ýa-da `.aab`** düşdi → Android ony gurnap bilmeýär;
  2. APK **gurnaldy, ýöne açylmaýar** (signature/ABI/minSdk/Play Protect);
  3. programma **ak ekran** görkezýär (splash ak + crash gizlenýär) — «açylmady» ýaly duýulýar.
- Iň möhüm fakt: **şu wagta çenli bir sany hem GitHub Release ýok, bir sany hem
  tag ýok.** Diýmek `.aab`/APK diňe **Actions artefaktlaryndan** alyp bolýar, ol
  ýerden hem faýl **zip görnüşinde** düşýär.

---

## 1. Barlanan faktlar (subutnamalar)

| Barlag | Netije |
|---|---|
| `gh run list` | iň soňky `main` CI: **success**, 3m42s (run `42829824679`) |
| CI ädimleri | format → analyze → test → **debug APK guruldy** |
| Artefaktlar | `voicereader-debug-apk` — **66 MB, `.zip` içinde**; `coverage` — 272 B |
| `gh release list` | **boş** — hiç hili Release ýok |
| `git tag` | **hiç ýok** → `release.yml` hiç haçan işlemändir |
| Gurlan APK görnüşi | `--debug`, ähli ABI bilen (şol sebäp 66 MB) |
| `.fvmrc` | Flutter **3.47.9** (CI-da hut şol sürüm) |
| `pubspec.lock` | git-de **ýok** (repoda saklanmaýar) |
| `minSdk` | `build.gradle.kts`-de `flutter.minSdkVersion` (dinamiki), dokumentde «24» ýazylan — **gapma-garşylyk** |
| Splash | `launch_background.xml` = **ak** (`@android:color/white`), programma bolsa garaňky tema |

Şol dört setir ýagny: **CI ýaşyl bolmagy = «programma telefonda açylýar» däl.**
CI diňe APK-nyň *gurulýandygyny* subut edýär, *gurnalýandygyny* we *açylýandygyny* däl.

---

## 2. Näme üçin açylmaýar — sebäpler, ähmiýeti boýunça

### 2.1. ZIP faýly telefonda açmak (iň ýygy sebäp) — ✅ 60%

**Alamat:** «Faýl açylmady», «Parsing the package», «There was a problem parsing the package».
**Näme bolýar:** GitHub Actions artefakty **elmittelik zip**. `voicereader-debug-apk.zip`
içinde `app-debug.apk` ýatyr. Telefon zip-i gurnap bilmeýär; Android diňe `.apk`
bilen işleýär.
**Barlag:** faýlyň ady `.zip` bilen gutarýarmy? Ululygy 66 MB-my?
**Çözgüt:** kompýuterde zip-i açyň → **`app-debug.apk`** faýlyny telefona geçiriň →
şony basyň. (Ýa-da §3-B: `adb install`.)

### 2.2. AAB faýlyny gurnamak — ✅ 20%

**Alamat:** basanda **hiç zat bolmaýar** (telefon `.aab`-ny «belok» hökmünde görmeýär).
**Näme bolýar:** `.aab` (App Bundle) diňe **Google Play** üçin. Ol telefona gurnalmaýar.
`release.yml` hut `appbundle --release` gurýar.
**Barlag:** faýl ady `app-release.aab`-my? **Çözgüt:** `.apk` gerek — §2.1/§3.

### 2.3. Artefakt sahypasynda ýalňyş faýl almak — ✅ 10%

**Alamat:** `coverage.zip` ýa-da başga artefakt düşdi; ululygy 272 B.
**Çözgüt:** diňe `voicereader-debug-apk` (66 MB) artefaktyny saýlaň.

### 2.4. «App not installed» — signaturanyň üýtgemegi — ⚠️ örän ýygy, gözden düşýän

**Alamat:** `App not installed` / `Programma gurnalyp bilinmedi` (parse error däl).
**Näme bolýar:** GitHub Actions her işlän mahalynda **täze debug keýstor** döredýär
(`~/.android/debug.keystore`). Şonuň üçin **bir run-yň APK-sy bilen ikinjisiniň APK-sy
bir-biriniň üstüne gurnalmaýar** — `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.
Şeýle hem öň Play-dan / başga ýerden gurlan şol bir package (`com.voicereader.app`)
bolsa, konflikt bolýar.
**Çözgüt:** öň **`adb uninstall com.voicereader.app`** (ýa-da Sazlamalar → Programmalar →
VoiceReader → Aýyr) edip, soňra täzeden gurnap görüň. Hemişelik çözgüt: §5-däki
durnukly keýstor strategiýasy.

### 2.5. Play Protect / «Näbelli çeşmeler» petigi — ⚠️ ýygy

**Alamat:** «For your security, your phone is not allowed to install unknown apps from this source».
**Çözgüt:** Sazlamalar → Howpsuzlyk → Näbelli programmalary gurmaga rugsat (brauzer/fayl
menajeri üçin). Play Protect-i wagtlaýyn öçürip bolýar (töwella diňe debug APK üçin).
Debug APK Play Protect tarapyndan «zyýanly bolup biler» diýen duýduryş berip biler — normal.

### 2.6. Telefonyň Android wersiýasy (minSdk) — ⚠️ orta

**Alamat:** «Your device is not compatible» / «This app requires a newer version of Android».
**Näme bolýar:** `minSdk` dokumentde 24 diýilýär, ýöne kodda `flutter.minSdkVersion`
(Flutter SDK-nyň berýän bahasy). Bu **iki dürli baha** bolmagy mümkin — §4-de
anyk `24` edip goýdum.
**Barlag:** `adb shell getprop ro.build.version.sdk` (24 = Android 7.0).
**Çözgüt:** Android 7.0+ telefon gerek (ýa-da emulýator).

### 2.7. Ak ekran / bir sekuntlap açylyp ýapylmak — ⚠️ orta

**Alamat:** nyşan basylda **ak ekran** peýda bolýar, soň programma ýapylýar; ýa-da 1–2
sekunt ak ekrandan soň interfeýs çykýar.
**Näme bolýar:**
- `android/app/src/main/res/drawable*/launch_background.xml` = **ak**; programma bolsa
  **garaňky navy** tema → her açylyşda ak «çaknyşyk». Bu *slow launch*-da «açylmady» ýaly duýulýar.
- Eger başlangyçda hakyky Dart ýalňyşlygy bolsa, **debug** APK-da gyzyl ekran çykmaly;
  **release**-da bolsa ekran **boş / ak** bolýar — anyk maglumat ýok. Şu sebäp bilen
  §5-de başlangyç ýalňyşlyk ekranyny (log bilen) goşmagy maslahat berýärin.
**Barlag (iň takyk ýol):** USB bilen birikdirip:
```bash
adb logcat -s flutter:V AndroidRuntime:E ActivityManager:I | grep -i voicereader
```

### 2.8. Faýl doly ýüklenmedi / 0 B — ⚠️ seýrek

**Barlag:** ululygy 66 MB-my (debug) — 0 B ýa-da 1–2 MB bolsa, ýüklenme döwüldi.

---

## 3. Dogry gurnama ýoly (ädim-ädim)

### A. Brauzerden (kompýuter gerek)
1. GitHub → **Actions** → iň soňky ýaşyl **CI** run → aşakda **Artifacts** →
   **`voicereader-debug-apk`** (66 MB) → ýüklä.
2. ZIP-i açyň → içindäki **`app-debug.apk`**-ny telefona geçiriň (kabel / Telegram
   «Saved Messages» / Google Drive).
3. Telefonda faýly basyň → «Näbelli çeşmelere» rugsat beriň → **Install**.
4. Öň gurnalan bolsa **ilki aýyryň** (signatura konflikti, §2.4).

### B. `adb` bilen (iň ygtybarly we log berýär)
```bash
adb devices                       # enjam görünmelidir
adb uninstall com.voicereader.app # köne wersiýany arassala (bolmasa ýalňyş berer)
adb install -r app-debug.apk      # -r = üstüne goý; goşmaça: -d = downgrade rugsaty
adb shell am start -n com.voicereader.app/.MainActivity
adb logcat -s flutter:V AndroidRuntime:E   # açylmaýan bolsa sebäbini şu ýerde gör
```

### C. Release (Play Store ýoly — häzir taýýar däl)
`.aab` → Play Console → **Internal testing** → testeri goş → Play-dan gurna.
Bu ýol üçin **upload keýstor** we Play Console akkaunt ($25) gerek (§5).

---

## 4. Bu kommittde näme düzedildi

| Faýl | Üýtgeşme | Näme üçin |
|---|---|---|
| `.github/workflows/release.yml` | `workflow_dispatch` + **gurnalyp bolýan release APK** artefakty + `SHA256SUMS.txt` + tag bolsa GitHub Release-a APK goýbermek (draft) | `.aab` telefona gurnalmaýar; indi APK hem çykýar we loginsiz ýükläp bolýar |
| `.github/workflows/ci.yml` | `workflow_dispatch` | islendik wagt täze APK gurup bolmagy üçin |
| `android/app/build.gradle.kts` | `minSdk = 24` (anyk) | dokument bilen kodyň arasyndaky gapma-garşylygy ýapdy |
| `android/.../res/values/colors.xml`, `launch_background.xml`, `styles.xml` | ak splash → brand **navy** `#0B1B33` | «ak ekran» duýgusyny ýok edýär |
| `README.md`, `docs/ROADMAP.md` | gurnama bölümi + Phase 0.1 | indiki gezek ýalňyşmasyn |

> Bellek: bu üýtgeşmeler **CI-nyň APK gurýan ädiminde** barlanýar (resurs/
> Gradle ýalňyşlygy şol ýerde çykar). `release.yml` diňe tag ýa-da el bilen
> işledilende barlanýar — şonuň üçin ony bir gezek `workflow_dispatch` bilen
> işledip görmeli.

---

## 5. Phase 1-e geçmezden öň ýapmaly 6 sany tehniki bergi

1. **Durnukly debug/upload keýstor.** CI-nyň debug keýstory her run-da üýtgeýär →
   APK-lar bir-biriniň üstüne gurnalmaýar. Çözgüt: `key.properties` + GitHub
   secrets (§ `release.yml`-däki kommentler), ýa-da `debug.keystore`-y şifrläp
   artefakt hökmünde saklamak.
2. **`pubspec.lock`-y git-e goşmak.** Häzir ýok: şu gün `pub get` bir wersiýany,
   ertir başga wersiýany çözer → «düýn işleýärdi» klassikasy.
3. **Başlangyç ýalňyşlyk ekrany.** `runZonedGuarded` + `ErrorWidget.builder` →
   boş ak ekran ýerine: ýalňyşlyk teksti + «Copy log» düwmesi. Şeýle hem
   `debugPrint` bilen `adb logcat`-a ýazgy.
4. **Golden path: install → launch → screenshot.** CI-da emulýator ädimi
   (`flutter drive` / `integration_test`) — «APK gurnalýarmy we açylýarmy?»
   soragyna awtomatik jogap. Häzir bu ädim **ýok**, şonuň üçin şu günki ýaly
   ýagdaý gaýtalanyp biler.
5. **Sürüm belgisi.** `pubspec.yaml` = `1.0.0+1`, ýöne önüm taýýar däl.
   `0.1.0+1` edip, hakyky relizde 1.0.0-a çykmaly (versionCode-yň yzly-yzyna
   ösmegi Play üçin hökmany).
6. **`flutter_tts` + `pdfrx` Phase 3/2-de goşlanda `INTERNET` ygtyýarlygy.**
   Häzir `main/AndroidManifest.xml`-de `INTERNET` **ýok** (diňe debug/profile-da bar).
   Offline maksat bilen dogry, ýöne Play Billing/analitika goşulsa, faýl
   manifestini üýtgetmeli — şu zat Phase 6-da garaşylmadyk sähel bolup biler.

---

## 6. Näme üçin testler bu problemi tutup bilmeýär

| Synag görnüşi | Näme barlaýar | Şu problema tutýarmy? |
|---|---|---|
| `flutter test` (häzirki) | Dart logikasy, widget agajy (host VM) | ❌ ýok |
| `flutter analyze` | statiki ýalňyşlyklar | ❌ ýok |
| `flutter build apk` | Gradle + resurslar + manifest birkemsizligi | ⚠️ diňe **gurulýandygyny** |
| `adb install` + `am start` | hakyky enjamda gurnalma + açylma | ✅ **şu ýerde tutulýar** |
| `integration_test` (emulýator) | gurnama → açylma → esasy akym | ✅ (geljekde goşmaly) |

**Gysgaça:** «CI ýaşyl» = «APK gurulýar». «Programma işleýär» däl.
Phase 0-nyň **DoD-syna** («debug APK artefakt») ýene bir setir goşmaly:
**«APK-ni bir enjamda gurnap, açyp, ekran suratyny artefakta goşmak»**.

---

## 7. Maňa näme aýtmaly (takyk diagnoz üçin)

Şu üç zady ýazsaň, sebäbi 100% anyklap berip bilerin:

1. Faýlyň **ady we ululygy** (`.zip`? `.apk`? `.aab`? näçe MB?);
2. telefonyň **modeli + Android wersiýasy**;
3. nähili görkezýär: *«parse error»* / *«app not installed»* / *«ak ekran, soň ýapylýar»* / *«basýar-am hiç zat bolmaýar»*.

Şolaryň biri-de adaty `adb logcat` çykyşy bolsa — iň gowy.
