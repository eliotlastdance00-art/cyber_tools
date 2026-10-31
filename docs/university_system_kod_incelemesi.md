# `University_system` — Kod İnceleme Raporu

> **İnceleme tarihi:** 31 Ekim 2026
> **İncelenen depo:** [`eliotlastdance00-art/University_system`](https://github.com/eliotlastdance00-art/University_system) — `main` @ `65945f0` (19 Ağu 2026, 71 commit)
> **Kapsam:** Tüm backend (`app/`, 117 dosya / 10.224 satır), veritabanı şeması + migration'lar, Docker/Makefile, `frontend/` (64 dosya / 11.468 satır), dokümantasyon ve git geçmişi.
> **Kod değişikliği yapılmadı.** Bu rapor yalnızca analiz + kanıt + öneri içerir.

---

## 0. Yönetici özeti

Proje **mimari olarak olgun** (katmanlı router → service → repository, `AppError` hiyerarşisi, yapılandırılmış JSON log, request-id, audit_logs tablosu, Argon2, parametreli SQL, çok aşamalı non-root Docker imajları). Buna karşılık **çalışırlık ve güvenlik tarafında ciddi açıklar** var:

| Alan | Durum |
|---|---|
| Kod tabanı | 126 API endpoint, 17 router, 10.2k satır Python |
| **Uygulama varsayılan hâliyle açılmıyor** | `requirements.txt` içinde `firebase-admin` yok → `ImportError`; `FIREBASE_CREDENTIALS_PATH` boşken `init_firebase(None)` → `ValueError` |
| **README'deki kurulumla giriş çalışmıyor** | Kod `roles.level` ve `refresh_tokens.is_revoked` kolonlarını sorguluyor, `database/schema.sql` bunları tanımlamıyor |
| **Kimlik doğrulaması olmayan endpoint** | **39 / 126 (%31)** — bunların içinde kullanıcı oluşturma, bölüm/program/ders silme var |
| **Kimliğe bürünme (impersonation)** | `Teacher` alias'ında `Depends` unutulmuş → `current_user` **istek gövdesinden** okunuyor |
| **Parola saklama** | `PUT /profile/me/password` parolayı **düz metin** olarak DB'ye yazıyor (ve 500 dönüyor) |
| **OTP 2. faktörü kırılabilir** | OTP, imzalı ama **şifrelenmemiş** JWT'nin içinde; deneme sayısı sınırsız; tek kullanımlık değil |
| Testler | **0 test dosyası** (pytest/pytest-cov bağımlılıkta var ama kullanılmıyor) |

**Bulgu dağılımı:** 9 × P0 (kritik), 9 × P1 (yüksek), 10 × P2 (orta).

Aşağıdaki P0'lar düzeltilmeden bu sistem **hiçbir ortamda yayına alınmamalı**; ilk 5 madde toplamda ~1 günlük iş.

---

## 1. İnceleme yöntemi

Statik okumanın yanında bulgular **çalıştırılarak** doğrulandı:

1. **Tam klon + git geçmişi taraması** (71 commit, tüm blob'larda `BEGIN PRIVATE KEY` / `AIza` araması).
2. **Kurulum simülasyonu:** `requirements.txt`'teki paketlerle sanal ortam kuruldu, `import app.main` denendi → gerçek hata çıktısı alındı.
3. **Ruff 0.17.3** ile statik analiz (`F821`, `S608`, `F811` vb.).
4. **Endpoint envanteri:** FastAPI `APIRoute.dependant` ağacı gezilerek her endpoint'in kimlik/rol bağımlılığı çıkarıldı (126 endpoint).
5. **OpenAPI şeması** üretilerek `Teacher` alias hatasının sonucu (`requestBody`) kanıtlandı.
6. **argon2 davranış testi:** düz metin parolanın `verify` çağrısında `InvalidHashError` ürettiği doğrulandı.

Komutlar ve çıktılar **Ek A**'da.

---

## 2. P0 — Kritik bulgular

### P0-1 · Parola değiştirme parolayı düz metin olarak kaydediyor (ve 500 dönüyor)

**Kanıt**
- `app/profile/router.py:37-45` → `service.update_password_me(user_id, data.new_password)`
- `app/profile/services.py:81-83` → **hash yok**: `await self.repo.update_password_me(id, new_password)`
- `app/profile/repository.py:68-78` → `SET password = %s` + **satır 77'de doğrudan `conn.commit()`**
- Hemen ardından `audit_log(... actor_id=None ...)` çağrılıyor; `database/migrations/001_grades_and_audit.sql:21` `audit_logs.actor_id INT NOT NULL` → insert patlar → `get_db` rollback **ama parola zaten commit edilmiş** → istemci 500 alır.

**Etki**
1. Parola veritabanında düz metin durur (Argon2'nin tüm faydası yok olur; DB yedeği sızarsa doğrudan hesap ele geçirme).
2. `verify_password()` Argon2 ile düz metni doğrulamaya çalışır → `InvalidHashError` → `False` → **kullanıcı bir daha giriş yapamaz** (hesap kilitlenir).
3. Kullanıcıya 500 döner, yani hata "başarısız" gibi görünür ama parola değişmiştir.

**Öneri**
```python
# profile/services.py
from app.core.security import hash_password
await self.repo.update_password_me(id, hash_password(new_password))
```
Ek olarak: mevcut parolayı iste (`current_password`), değişimden sonra `revoke_all_token(user_id)` çağır, audit kaydını `actor_id=id` ile yaz, repository içindeki manuel `commit()`leri kaldır (transaction sahibi `get_db` olmalı).

---

### P0-2 · Uygulama `requirements.txt` ile açılmıyor: `firebase-admin` eksik

**Kanıt** — `app/main.py:38` → `app/notifications/infrastructure/fcm_client.py:4` → `import firebase_admin`.
`requirements.txt` (80 paket) içinde `firebase-admin` **yok**. Gerçek çalıştırma:

```
File "/tmp/uni/app/notifications/infrastructure/fcm_client.py", line 4, in <module>
    import firebase_admin
ModuleNotFoundError: No module named 'firebase_admin'
```

**Etki:** `Docker/backend.Dockerfile` yalnızca `requirements.txt` kuruyor → konteyner başlar başlamaz `ImportError` ile ölür. Yerel kurulumda da aynı. Yani depo, mevcut hâliyle **hiç ayağa kalkmıyor**.

**Öneri:** `firebase-admin==6.x` (pinli) ekle **veya** FCM'i opsiyonel yap:
```python
try:
    import firebase_admin
    from firebase_admin import credentials, messaging
    FCM_AVAILABLE = True
except ImportError:          # push devre dışı, API çalışmaya devam eder
    FCM_AVAILABLE = False
```

---

### P0-3 · Firebase yapılandırması yokken uygulama açılışta çöküyor

**Kanıt** — `app/core/config.py:36`: `FIREBASE_CREDENTIALS_PATH: str | None = None` ("gracefully skipped if absent" yorumuna rağmen);
`app/main.py:49` lifespan → `init_firebase(settings.FIREBASE_CREDENTIALS_PATH)`;
`fcm_client.py:13-21`: `if _firebase_app is not None: return` → `credentials.Certificate(None)`.

Doğrulama çıktısı:
```
init_firebase(None) -> RAISES: ValueError Invalid certificate argument: "None".
```

**Etki:** `.env`'de Firebase yolu tanımlı değilse (yani `.env.example` boş olduğu için neredeyse her yeni kurulumda) API hiç açılmaz. Push bildirimleri opsiyonel bir özellik olduğu hâlde **tüm sistemin ön koşulu** hâline gelmiş.

**Öneri:** `init_firebase` içinde `if not cred_path: logger.warning(...); return` + `send_fcm` çağrılarında `FCM_AVAILABLE` kontrolü.

---

### P0-4 · 126 endpoint'in 39'unda kimlik doğrulaması yok

**Kanıt:** `APIRoute.dependant` ağacı taraması (Ek A). Öne çıkanlar:

| Endpoint | Risk |
|---|---|
| `POST /users/` — `app/users/router.py:32` | **Herkese açık kayıt.** Kod yorumu bunu bilinçli yapmış ("açyk registrasiýa endpoint"). Rol atanmıyor ama hesap açılıyor, audit `actor_id=created_user["id"]` (kendini aktör yazıyor). |
| `POST/PUT/DELETE /faculties` dışındaki `programs`, `cohorts`, `sections`, `subjects`, `academic_years` CRUD'ları | **Anonim kullanıcı müfredatı silebilir/değiştirebilir.** Örn. `DELETE /programs/{id}`, `PUT /subjects/{id}`. |
| `GET /sections/{id}/students`, `GET /sections/{id}/attendance/stats`, `POST /sections/` | Öğrenci listesi ve devam istatistikleri herkese açık (KVKK/GDPR ihlali). |
| `POST /lessons/{timetable_id}/start`, `PUT /lessons/{id}/cancel` | Ders başlatma/iptal. |
| `GET /attendance/lesson/{lesson_id}`, `/student/{student_id}`, `/group/{section_id}/stats` | Devam kayıtları anonim okunabiliyor. |

`GET /grades/...` ve `GET /attendance/student/{student_id}` ise **sadece "giriş yapmış olma"** istiyor (`get_current_user`) → her öğrenci başka öğrencinin notlarını/devamsızlığını ID değiştirerek okuyabilir (bkz. P1-1).

**Öneri:** Router seviyesinde varsayılan bağımlılık:
```python
router = APIRouter(dependencies=[Depends(get_current_user)])
```
ve her yazma endpoint'ine açık rol kontrolü (`admin_required` / `admin_or_dean` / `teacher_required`). `POST /users` **mutlaka** admin'e kapatılmalı; öğrenci kaydı ayrı, davet/onay akışlı bir endpoint olmalı.

---

### P0-5 · `Teacher` alias'ında `Depends` yok → `current_user` istek gövdesinden okunuyor (kimliğe bürünme)

**Kanıt** — `app/academic/lessons/router.py:20`:
```python
Teacher = Annotated[dict, (teacher_required)]   # ← Depends(...) yok
```
FastAPI bu metadatayı bağımlılık olarak görmüyor, `dict` tipini **request body** olarak yorumluyor. Üretilen OpenAPI şeması (kanıt):
```json
"/University_system/v1/lessons/my/history": {
  "requestBody": {
    "required": true,
    "content": {"application/json": {"schema": {"type": "object", "title": "Current User"}}}
  }
}
```
Aynı durum `POST /lessons/{timetable_id}/start`, `GET /lessons/my/stats`, `PUT /lessons/{id}/cancel` için de geçerli.

**Etki:** Anonim bir çağıran `{"id": 42, "role": "teacher"}` göndererek **herhangi bir öğretmen gibi** ders başlatıp iptal edebilir, o öğretmenin ders geçmişini/istatistiklerini okuyabilir. Kimlik doğrulama tamamen devre dışı.

**Öneri:**
```python
Teacher = Annotated[dict, Depends(teacher_required)]
```
ve benzer hataları yakalamak için CI'da `ruff` + OpenAPI'de `requestBody` beklenmeyen endpoint testi.

---

### P0-6 · İki faktörlü doğrulama (OTP) fiilen kırılabilir

Üç ayrı zayıflık birleşiyor:

1. **OTP, token'ın içinde taşınıyor:** `app/core/security.py:68-76`
   ```python
   payload = {"email": ..., "otp": otp, "exp": ..., "type": "otp_verification"}
   return jwt.encode(payload, settings.SECRET_KEY, algorithm=...)
   ```
   JWT **imzalıdır, şifreli değildir** → payload base64 ile okunur. Token `HttpOnly` cookie'de tutulsa da (`auth/service.py:92-99`) aynı origin'deki herhangi bir XSS/cookie sızıntısı veya proxy logu, OTP'yi doğrudan ele verir. Saldırgan **e-postaya erişmeden** 2. faktörü geçebilir.
2. **Deneme sınırı yok:** `auth/service.py:147` `hmac.compare_digest` ile karşılaştırıyor, ama sayaç/kilit yok. 6 haneli kod (`create_otp`, 900.000 olasılık) `OTP_EXPIRE_MINUTES` boyunca sınırsız denenebilir. Kod tabanında `RateLimitError` (`core/exceptions.py:101`) **tanımlı ama hiç kullanılmıyor** — rate limiting yok.
3. **Tek kullanımlık değil:** doğrulama sonrası yalnızca tarayıcı cookie'si siliniyor (`auth/service.py:155-161`), token'ın kendisi iptal edilemiyor (stateless JWT). Aynı cookie ile süre dolana kadar tekrar tekrar oturum üretilebilir.

**Öneri (en az):** OTP'yi token'a gömmeyin; `otp_hash` + `expires_at` + `attempts` kolonlarıyla DB/Redis'te saklayın. Doğrulama başarılında kaydı silin, 5 hatalı denemede kilitleyin, endpoint'e IP + e-posta bazlı rate limit (slowapi / Redis) ekleyin.

---

### P0-7 · Şema ile kod uyuşmuyor: temiz kurulumda giriş çalışmıyor

**Kanıt**
- `app/auth/repository.py:25` ve `:45` → `ORDER BY r.level ASC`
- `database/schema.sql:30-33` → `roles (id, name)` — **`level` kolonu yok** (migration'larda da yok)
- `app/auth/repository.py:53,67,81,93` → `refresh_tokens.is_revoked`
- `database/schema.sql:203-210` → kolon adı **`revoked`**

**Etki:** `database/schema.sql` + `001/002` migration'ları uygulandığında:
- `POST /auth/login` → `Unknown column 'r.level' in 'order clause'` → 500
- `POST /auth/verify-otp` → `Unknown column 'is_revoked'` → 500 (refresh token kaydedilemez)

Yani README'deki "Getting Started" akışı **kutudan çıktığı gibi çalışmıyor**. Ayrıca `schema.sql` başlığında kendisi "koddan geri türetildi, production DB ile karşılaştırın" diyor — tek doğruluk kaynağı yok, Alembic yok, `001` migration'ı `CREATE TABLE` (IF NOT EXISTS değil) olduğu için tekrar çalıştırılamıyor.

**Öneri:** Alembic'e geçin (veya en azından migration'ları idempotent yapın); `roles.level` + `refresh_tokens` şemasını migration olarak ekleyin; CI'da "boş DB → migration → `GET /` + login smoke test" çalıştırın.

---

### P0-8 · Not (grade) işlemleri `NameError` ile 500 veriyor

**Kanıt (ruff F821)**
```
app/academic/grades/service.py:20,24,37,66,79,100,113  F821 Undefined name `get_user_id`
app/academic/assignments/router.py:137,153,165         F821 Undefined name `get_user_id`
```
`app/academic/grades/service.py` başında `get_user_id` import edilmemiş (sadece `logger` var). `POST/PUT/DELETE /grades` her çağrıda `NameError` → 500. Aynı şekilde öğretmenin atama/schedule endpoint'leri (`GET /assignments/my`, `/my/semester/{s}`, `/my/schedule`) çalışmıyor.

**Etki:** Not verme modülü pratikte kullanılamaz; öğretmen panelinin üç ekranı boş/hatalı.

**Öneri:** `from app.core.dependencies import get_user_id` ekle; CI'da `ruff check --select F821` zorunlu kıl (bu tip hatalar 1 saniyede yakalanır).

---

### P0-9 · CORS: her origin + credentials

**Kanıt** — `app/main.py:69-74`:
```python
allow_origin_regex=".*",
allow_credentials=True,
allow_methods=["*"],
allow_headers=["*"],
```
`app/core/config.py:37`'deki `ALLOWED_ORIGINS` **hiç kullanılmıyor**.

**Etki:** Herhangi bir site, kullanıcının tarayıcısındaki cookie/oturumla API'ye credential'lı istek atabilir; CORS bir güvenlik sınırı olmaktan çıkar (XSS/CSRF yüzeyi büyür). Ayrıca `docs_url="/docs"` ve `/openapi.json` prod'da da açık (saldırgan için hazır envanter).

**Öneri:**
```python
app.add_middleware(CORSMiddleware,
    allow_origins=[o.strip() for o in settings.ALLOWED_ORIGINS.split(",")],
    allow_credentials=True, allow_methods=["GET","POST","PUT","PATCH","DELETE"], allow_headers=["Authorization","Content-Type"])
```
+ prod'da `docs_url=None, redoc_url=None, openapi_url=None` (veya auth arkasına al).

---

## 3. P1 — Yüksek öncelikli bulgular

### P1-1 · IDOR / yetki sınırı yokluğu
- **`PUT /profile/me`** (`profile/router.py:19-27`): `current_user` **hiç kullanılmıyor**, güncellenecek kullanıcı gövdedeki `id` (`profile/schemas.py:6`). Giriş yapmış herhangi bir kullanıcı **başkasının adını/e-postasını/fakülte-bölüm-şubesini** değiştirebilir. E-postayı kendi adresine çevirmek, kurbanın OTP'sini ele geçirme yolunu açar.
- **Notlar:** `GET /grades/{id}` ve `GET /grades/student/{student_id}` yalnızca `get_current_user` istiyor (`grades/router.py:27-33,58-64`) → öğrenci başkasının notlarını okur. Aynısı `GET /attendance/student/{id}` için geçerli.
- **Duyuru:** `POST /notification/broadcast` (`notifications/router.py:51`) herhangi bir giriş yapmış kullanıcıya açık → öğrenci tüm kampanyaya phishing duyurusu gönderebilir.
- **Öğretmen sahipliği** sadece devam yazma yolunda (`_check_lesson_owner`) kontrol ediliyor; notlarda yok: bir öğretmen **başka bölümün** dersine not girebilir.

**Öneri:** Servis katmanında "kaynak sahibi mi?" kontrolü (student_id == current_user.id veya subject assignment sahipliği), `PUT /profile/me`'de id'yi **yalnızca** token'dan al, broadcast'i `admin`e kısıtla.

### P1-2 · Oturum/yenileme token'ı zayıflıkları
- `POST /auth/refresh` ve `/logout` refresh token'ı **query parametresi** olarak alıyor (`auth/router.py:42,48`) → uvicorn access loglarına, proxy loglarına, tarayıcı geçmişine düşer. Gövdeye alın.
- Refresh token **düz metin** olarak `refresh_tokens` tablosunda (indekssiz `VARCHAR(500)`) → DB sızıntısı = oturum ele geçirme. Hash'leyip saklayın (`sha256`).
- **Reuse detection yok:** `old_token_change_new_token` eski satırı yerinde güncelliyor; çalınmış eski token'la yapılan deneme yalnızca "bulunamadı" döner, tüm aile iptal edilmez.
- **Access/refresh ayrımı tek yönlü:** `get_current_user` token tipini doğrulamıyor (`dependencies.py:20-38`) → **refresh token**, süresi günlerce geçerli bir access token gibi kullanılabilir (rol claim'i olmadığı için rol gerektiren uçlar 403 verir, ama "sadece giriş" isteyen 20+ uç açılır).
- **Rol / `is_active` her istekte kontrol edilmiyor** → rolü düşürülen veya pasife alınan kullanıcı, access token süresi dolana kadar yetkisini korur. `logout` yalnızca refresh token'ı iptal eder, access token yaşamaya devam eder.
- `decode_token` `aud`/`iss`/`jti` doğrulamıyor; access ve refresh aynı `SECRET_KEY` + algoritma ile üretiliyor.

**Öneri:** Token'lara `type` alanı ekleyip her iki yönde de doğrula; refresh'i hash'le; rotasyonda aileyi (`family_id`) iptal et; access token süresini 10-15 dk'ya indir; kritik işlemlerde `is_active`/rol için DB kontrolü.

### P1-3 · Rate limiting yok
`slowapi`/`limits` yok, Redis tabanlı sayaç yok. `POST /auth/login` ve `/auth/verify-otp` sınırsız → parola spreyi + OTP brute force (P0-6 ile birleşince 2FA pratikte aşılır). `RateLimitError` sınıfı tanımlı ama **hiçbir yerde raise edilmiyor**.

### P1-4 · Parola politikası ve oturum hijyeni
- `users/schemas.py:7` → `min_length=6` (README/Swagger "at least 8" diyor — dokümanla kod çelişiyor).
- Parola değişiminde **mevcut parola sorulmuyor** (`UpdatePassword` sadece `new_password`).
- Parola değişimi/e-posta değişimi sonrası **tüm oturumlar iptal edilmiyor**.
- **OTP cookie'si `secure=False` sabit** (`auth/service.py:46`) → HTTPS üretiminde bile cookie düz HTTP üzerinden gönderilebiliyor; ortam değişkenine bağlanmalı.
- Login'de e-posta enumerasyonu için küçük bir timing sinyali var (`if not user or not verify_password(...)` → kullanıcı yoksa Argon2 hiç çalışmaz).

### P1-5 · OTP ve hata bilgisi sızıntısı
- SMTP başarısız olduğunda `auth/service.py:104-124` hatayı yutuyor, **OTP'yi `print()` ile stdout'a yazıyor** ve istemciye "OTP gönderildi" diyor. Bu blok `DEBUG` ile korunmuyor → prod loglarında **açık OTP kodları**.
- `raise AppError(f"Login Error: {e!s}")` (`auth/service.py:79`) global handler üzerinden **iç hata metnini istemciye** döndürüyor (bilgi ifşası + 500).
- Aynı sorun `notifications`/`grades` servislerinde `logger.error(f"...")` kullanımıyla traceback kaybı olarak tekrar ediyor.

### P1-6 · İstemci tarafı token saklama
`frontend/src/utils/token.js` access **ve** refresh token'ı `localStorage`'da tutuyor (günlerce geçerli refresh token). Herhangi bir XSS → kalıcı oturum çalınması. Cookie tabanlı OTP akışı zaten var; access token'ı kısa ömürlü bellekte, refresh'i `HttpOnly; Secure; SameSite` cookie'de tutmak daha doğru.

### P1-7 · Production dağıtımı çalışmıyor
- `docker-compose.yml:17-18` → `VITE_API_URL=${VITE_API_URL:-http://localhost:8000}` build arg'ı **tarayıcıda** çözümlenir; son kullanıcının makinesinde `localhost:8000` yoktur.
- `Docker/frontend.Dockerfile` nginx konfigürasyonunda `/api` için `proxy_pass` **yok** → `client.js`'in varsayılan `/api` tabanı 404 döner (SPA `index.html`'e düşer).
- Backend `8000`, MySQL `3306`, Redis `6379` host'a publish ediliyor; Redis'te parola yok; compose'da MySQL kullanıcısı/parolası **root parolasıyla aynı** (`MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}`).
- `.env.example` **0 bayt**, `frontend/.env.frontend.eaxample` de **0 bayt** (ve adı yanlış yazılmış). `config.py` 13 zorunlu değişken istiyor → yeni geliştirici hiçbir şekilde ayağa kaldıramaz.
- `frontend/public/firebase-messaging-sw.js:9` içinde Firebase config (apiKey, projectId) **sabit yazılmış**; `firebase.js` ise `VITE_FIREBASE_*` bekliyor → iki ayrı doğruluk kaynağı.

### P1-8 · Frontend açılış riski
`frontend/src/firebase.js:4-13` `initializeApp(firebaseConfig)` **modül seviyesinde, try/catch dışında** çağrılıyor. `VITE_FIREBASE_*` tanımlı değilse (P1-7'deki boş `.env` örneği yüzünden olağan durum) config `undefined` olur ve hata tüm SPA'yı beyaz ekrana düşürebilir. `initMessaging()` içindeki zarif bozulma bu satırı korumuyor.

### P1-9 · Audit kaydı bazı akışları tamamen bozuyor / boşluklar var
- `audit_logs.actor_id INT NOT NULL` + `AuditLogger(actor_id: int | None)` → `actor_id=None` geçen her yol **500** üretir (`PUT /profile/me`, `PUT /profile/me/password`). Yani profil güncelleme uçları çalışmıyor.
- Audit kapsamı tutarsız: `source`'ların bir kısmı (`timetable`, `sections`, `subjects`, `departments`) audit yazmıyor; `grades` ise ortak `AuditLogger` / `AuditAction` enum'u yerine kendi `AuditLogRepository`'sini ve `"CREATE"` gibi serbest metinleri kullanıyor.
- Repository içlerinde manuel `conn.commit()` (auth, profile) `get_db`'nin "tek transaction" sözleşmesini deliyor → kısmi commit'ler (P0-1'in de kök nedeni).

---

## 4. P2 — Orta öncelikli bulgular

1. **Test yok, CI yok.** 0 test dosyası; `pytest`, `pytest-cov`, `coverage` bağımlılıkta ama kullanılmıyor. Tek workflow (`.github/workflows/summary.yml`) issue'ları AI ile özetliyor — lint/test/build adımı yok. `ruff` bile yapılandırılmamış (pyproject/pre-commit yok); mevcut kodda **180 ruff uyarısı** var (97 × E501, 40 × W291, 10 × F821, 6 × S608).
2. **`requirements.txt` bir `pip freeze` dökümü** (80 paket, dev/prod ayrımı yok, hash yok). İçinde projeyle ilgisiz/şüpheli isimler var: `argon`, `detect-installer`, `fastar`, `rignore`, `passlib` (kod `argon2-cffi`'yi doğrudan kullanıyor). Tedarik zinciri riski + gereksiz saldırı yüzeyi. `requirements.in` + `pip-compile --generate-hashes` önerilir.
3. **Şema yönetimi:** `database/schema.sql` "koddan geri türetildi" notuyla geliyor; `001` migration'ı idempotent değil; kolon adları koddan sapıyor (P0-7). Alembic yok.
4. **MySQL sürücüsü notu:** `aiomysql` + MySQL 8 varsayılan `caching_sha2_password`; `cryptography` paketi `requirements.txt`'te yok → bazı kurulumlarda `RuntimeError: 'cryptography' package is required` alınabilir.
5. **Dinamik SQL parçaları (5 yer):** `grades/repository.py:44`, `timetable/repository.py:256,505`, `notifications/repository.py:32,66` — kolon adları dict anahtarlarından geliyor. Bugün anahtarlar Pydantic şemasıyla sınırlı olduğu için **sömürülebilir değil**, ama desen kırılgan (ileride `model_dump()` genişlerse injection'a döner). Kolonları beyaz listeyle eşleyin.
6. **Dokümantasyon kırıkları:** README `ARCHITECTURE.md` ve `CONTRIBUTING.md`'ye link veriyor; depoda dosyalar `Arhitecture.md` (yazım hatası) ve `Contributing.md` → GitHub'da **404**. README'deki `.github/assets/*.png` ekran görüntüleri yok. `Arhitecture.md:198` "Firebase service account JSON'u git geçmişine commit'lendi" diyor — **71 commit'in tamamı tarandı, özel anahtar bulunmadı**; yalnızca herkese açık Firebase web API anahtarı (`AIza…`) `firebase-messaging-sw.js` içinde. Bu ifade düzeltilmeli (yanlış alarm olabilir ama geçmiş taraması temiz).
   Not: `Arhitecture.md`'nin "Known issues" bölümü (madde 6-10) bu rapordaki bazı bulguları (`OTP_COOKIE_SECURE`, `.idea`/`.vscode`, CI yokluğu) zaten kaydetmiş — yani ekip farkındalığı var, eksik olan uygulama.
7. **Depo hijyeni:** `.idea/` ve `.vscode/` commit'lenmiş; `.gitignore` kendi adını içeriyor (`gitignore` satırı işlevsiz); `app/academic/subjects/__init.py` (**`.py` uzantısı yok**, paket `__init__.py`'siz); `app/`, `app/notifications/`, `app/notifications/infrastructure/` altında `__init__.py` yok (implicit namespace ile çalışıyor, kırılgan).
8. **Hata/istisna disiplini:** neredeyse her servis `except Exception` + yeniden fırlatma; `logger.error` kullanımı traceback kaybediyor (`logger.exception` tercih edilmeli). `AppError` varsayılanı 500 olduğu için iş kuralı hataları da 500 dönüyor.
9. **Performans/dayanıklılık:** `aiomysql` havuzu sabit `minsize=1, maxsize=10`; `GET /health` DB/Redis durumunu kontrol etmiyor (DB kapalıyken "running" der); büyük listelerde (`/users`, `/grades`) sayfalama yok; `refresh_tokens.token` indekssiz; `audit_logs`'ta `entity_name/entity_id` indeksi yok.
10. **Boyut/karmaşıklık:** `timetable/repository.py` 734 satır, `generator.py` 575, `router.py` 470 — test edilmemiş "god module"ler; `core/base_repository.py` pratikte kullanılmıyor.

---

## 5. Güçlü yönler (korunmalı)

- **Katmanlama tutarlı:** her domain `router → service → repository → schemas → exceptions` olarak ayrılmış; `main.py` ince bir kompozisyon kökü.
- **Hata hiyerarşisi:** `AppError` + `status_code`/`error_code` + global handler → istemci için tutarlı sözleşme (`error_code`, `detail`, `request_id`).
- **Loglama:** `StructuredJsonFormatter` ile satır başına JSON, `request_id`/`method`/`path` alanları, `X-Request-ID` yanıt başlığı — Loki/Grafana'ya hazır.
- **Audit tasarımı (fikir olarak):** `AuditAction` enum'u ile serbest metin yerine sabit aksiyonlar, `old_value`/`new_value` JSON snapshot'ları; parolanın audit'e yazılmaması bilinçli.
- **SQL enjeksiyonuna karşı genel disiplin:** ~95% sorgu parametreli (`%s`); dinamik parçalar sınırlı ve şema-kontrollü.
- **Kimlik doğrulama temeli:** Argon2id, `hmac.compare_digest` ile OTP karşılaştırması, `HttpOnly` OTP cookie, refresh token rotasyonu + tek-uçuş (single-flight) refresh kuyruğu (frontend) — bu detaylar çoğu projede yok.
- **Docker:** çok aşamalı build, non-root kullanıcı (`appuser`, `nginx`), `tini` PID 1, `HEALTHCHECK`, nginx'te güvenlik başlıkları + gzip + SPA fallback, `Makefile` ile operasyon komutları.
- **Dokümantasyon kültürü:** README, `Arhitecture.md` (akış diyagramları, bilinen sorunlar listesi), `Plan.md`, `Contributing.md`, `SECURITY.md`, `LICENSE`, issue template'leri.
- **Commit geçmişi** okunabilir (feature branch + PR başlıkları), geçmişte sızmış gizli anahtar yok.

---

## 6. Öncelikli aksiyon planı

### Hafta 1 — "Sistem çalışsın ve kapılar kapansın" (P0)
1. `requirements.txt`: `firebase-admin` ekle (veya opsiyonel import) **+** `cryptography` (MySQL 8 auth için).
2. `init_firebase(None)` → uyarı + sessiz çıkış.
3. `profile` parola değişimini hash'le; mevcut parolayı doğrula; oturumları iptal et; manuel `commit()`leri kaldır.
4. `grades/service.py` + `assignments/router.py` → `get_user_id` importu.
5. `lessons/router.py:20` → `Depends(teacher_required)`.
6. Router varsayılan `Depends(get_current_user)` + yazma uçlarına rol kontrolü; `POST /users` admin-only.
7. `roles.level` + `refresh_tokens` şemasını migration'la hizala; boş DB → login smoke testi.
8. CORS'u `ALLOWED_ORIGINS`'e bağla, prod'da docs kapat.

### Hafta 2-3 — "Yetki ve oturum sağlamlaştırma" (P1)
9. IDOR düzeltmeleri (profile id, grades/attendance sahiplik, broadcast admin).
10. OTP'yi DB/Redis'te hash + tek kullanımlık + deneme limiti; OTP loglamasını kaldır.
11. Token tipleri, refresh hash + aile iptali, query param'dan gövdeye taşıma, access token süresini kısaltma.
12. Rate limiting (login/OTP/broadcast), parola politikası (≥8 + mevcut parola).
13. `.env.example` dosyalarını gerçek içerikle doldur; compose prod profilini (localhost/api proxy) düzelt; Redis auth + port kısıtları.
14. Frontend: firebase init'i try/catch içine al, token saklamayı gözden geçir.

### Hafta 4+ — "Sürdürülebilirlik" (P2)
15. `pytest` + `httpx.AsyncClient` ile smoke testleri (auth akışı, RBAC matrisi, grade CRUD), CI'da `ruff` + `pytest` + `npm run build`.
16. Alembic'e geçiş, idempotent migration'lar, `requirements.in` + hash'li lock.
17. Audit kapsamını tüm yazma yollarına yay, `AuditLogger`'ı tekilleştir, `actor_id` NULL'ı kaldır.
18. Doküman düzeltmeleri (ARCHITECTURE/CONTRIBUTING dosya adları, kırık görsel linkleri, geçmiş iddiası), repodan `.idea`/`.vscode` çıkarma, `__init__.py` düzeltmeleri.
19. Sayfalama, indeksler, `/health` derinlik kontrolü, `timetable` modülünün parçalanması.

---

## Ek A — Bulguları kendin doğrulama

```bash
# 1) Depoyu al
git clone https://github.com/eliotlastdance00-art/University_system.git && cd University_system

# 2) Bağımlılıklarla import (P0-2)
python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
python -c "import app.main"        # → ModuleNotFoundError: No module named 'firebase_admin'

# 3) Undefined name taraması (P0-8)
pip install ruff
ruff check app --select F821        # → 10 hata (grades/service.py, assignments/router.py)

# 4) Şema uyumsuzluğu (P0-7)
grep -n "r.level" app/auth/repository.py           # 25, 45
grep -n "roles" -A3 database/schema.sql | head     # roles(id, name) — level yok
grep -n "is_revoked" app/auth/repository.py        # kod
grep -n "revoked" database/schema.sql              # şema: 'revoked'

# 5) Açık endpoint envanteri (P0-4 / P0-5) — bu repodaki script'in özü
python - <<'PY'
import importlib, pathlib, os
from fastapi.routing import APIRoute
AUTH={'get_current_user','admin_required','dean_required','teacher_required',
      'admin_or_dean','admin_or_teacher','admin_or_student'}
def walk(dep, acc):
    for d in dep.dependencies:
        if d.call: acc.add(d.call.__name__); walk(d, acc)
total=open_=0
for p in sorted(pathlib.Path('app').rglob('router.py')):
    M=importlib.import_module(str(p.with_suffix('')).replace('/','.'))
    for r in M.router.routes:
        if not isinstance(r, APIRoute): continue
        total+=1; a=set(); walk(r.dependant,a)
        if not (a & AUTH):
            open_+=1; print(f"{p} {sorted(r.methods)} {r.path}")
print(f"\n{open_}/{total} endpoint kimlik doğrulamasız")
PY

# 6) OTP token'ının içeriği (P0-6)
python - <<'PY'
import base64, json
tok = "<cookie'den alınan otp_token>"
p = tok.split('.')[1]; p += '=' * (-len(p) % 4)
print(json.loads(base64.urlsafe_b64decode(p)))   # → {'email':..., 'otp':'123456', ...}
PY
```

---

## Ek B — Kimlik doğrulaması olmayan 39 endpoint

| Metot & yol | Modül |
|---|---|
| `POST /`, `PUT /{id}`, `GET /` | `app/academic/academic_years` |
| `POST /`, `GET /`, `GET /{id}`, `PUT /{id}`, `DELETE /{id}`, `GET /{id}/sections` | `app/academic/cohorts` |
| `POST /{timetable_id}/start`, `PUT /{id}/cancel`, `GET /my/history`, `GET /my/stats` | `app/academic/lessons` (P0-5) |
| `POST /`, `PUT /{id}`, `GET /`, `DELETE /{id}`, `GET /{id}`, `GET /{id}/cohorts` | `app/academic/programs` |
| `POST /`, `GET /`, `GET /{id}`, `PUT /{id}`, `DELETE /{id}`, `GET /{id}/students`, `GET /{id}/timetable`, `GET /{id}/attendance/stats` | `app/academic/sections` |
| `POST /`, `GET /`, `GET /faculty/{faculty_id}`, `GET /department/{department_id}`, `GET /{id}`, `PUT /{id}` | `app/academic/subjects` |
| `POST /login`, `POST /verify-otp`, `POST /refresh`, `POST /logout` | `app/auth` (kasıtlı) |
| `GET /{id}/departments` | `app/faculty` |
| `POST /` | `app/users` (**herkese açık kayıt**) |

Buna ek olarak **20 endpoint yalnızca "giriş yapmış olmayı"** istiyor (rol/sahiplik kontrolü yok): `GET /grades/{id}`, `GET /grades/student/{student_id}`, `GET /profile/me`, `GET/PATCH /notification/...`, `GET /attendance/student/{id}` vb.

---

## Ek C — Ölçümler

| Metrik | Değer |
|---|---|
| İzlenen dosya | 226 (`.git` 403 KB, çalışma ağacı ~1.7 MB) |
| Python | 117 dosya · 10.224 satır |
| Frontend | 64 dosya · 11.468 satır · 28 sayfa |
| API endpoint | 126 (17 router) |
| Kimlik doğrulamasız endpoint | 39 (%31) |
| `ruff check --select F` | 11 hata (10 × F821, 1 × F811) |
| `ruff` toplam (E,F,W,B,S) | 180 uyarı (97 × E501, 40 × W291, 10 × F821, 6 × S608, 6 × B008…) |
| Test dosyası | 0 |
| Git geçmişi | 71 commit · sızmış özel anahtar: yok |
| Bağımlılık | 80 paket (pinli, dev/prod ayrımı yok) |

---

*Bu raporu hazırlayan ajan yalnızca okuma/analiz yaptı; `University_system` deposunda hiçbir dosya değiştirilmedi, commit/push yapılmadı. P0'ların düzeltmesini isterseniz bu çalışma alanında yama hazırlayabilirim.*
