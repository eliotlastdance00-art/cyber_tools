# TTS üçin dokumentleri bölmek

Python skripti PDF, DOCX we UTF-8 TXT faýllaryndan teksti alyp, sözlemleri mümkin boldugyça bütewi saklap, TTS üçin kiçi böleklere bölýär. Her abzas aýratyn saklanýar; aşa uzyn sözlem söz araçäklerinden, çäkden uzyn ýeke söz bolsa hökmany ýagdaýda simwollardan bölünýär. Bu skript ses döretmeýär: netijäni TTS hyzmatyna gezekli-gezegine iberip bolýar.

## Gurmak

Python 3.10 ýa-da täze wersiýa gerek:

```bash
python -m pip install -r requirements.txt
```

## Ulanmak

```bash
python tts_chunks.py kitap.pdf -o bolekler.json --max-chars 500
python tts_chunks.py makala.docx -o bolekler.txt --max-chars 300
python tts_chunks.py tekst.txt -o bolekler.json
```

`--max-chars` her bölek üçin iň köp Unicode simwol sanydyr (baýt ýa-da token sany däl). JSON netijesi tertipli setirler sanawydyr; TXT-de bölekler boş setir bilen bölünýär. Mysal üçin, JSON sanawyny okap, öz TTS funksiýaňyza iberiň:

```python
import json
from pathlib import Path

chunks = json.loads(Path('bolekler.json').read_text(encoding='utf-8'))
for chunk in chunks:
    # tts(chunk)  # Bu ýere öz TTS hyzmatyňyzyň çagyryşyny ýazyň.
    print(chunk)
```

## Çäklendirmeler

- Skanirlenen/surat görnüşli PDF üçin ilki OCR gerek. Garyşyk PDF-de surat sahypalaryndan tekst alynmaýar.
- PDF sütünleri, tablisalary, sözbaşylary we sahypa belgileri nädogry tertipde çykyp biler; netijäni barlaň. DOCX esasy tekst we tablisalary öz içine alýar, emma header/footer, bellikler we şekiller alynmaýar. Köne `.doc` faýlyny ilki `.docx` görnüşine geçiriň.
- Sözlem bölünişi düzgünlere esaslanýar, semantik düşünme ýa-da dil modeli däl; gysgaltmalar we başga aýratyn ýagdaýlarda ýalňyşyp biler. PDF setirindäki defisler bilkastlaýyn aýrylmaýar.
- TTS hyzmatynyň öz limitleri (baýt, token ýa-da dowamlylyk) bar bolsa, `--max-chars` bahasyny şoňa görä sazlaň.

Synaglar: `python -m unittest discover -s tests`

## Her bölegi aýratyn TXT faýly hökmünde çykarmak

```bash
python tts_chunks.py kitap.pdf --output-dir kitap_bolekleri --max-chars 500
```

Bu buýruk `chunk_000001.txt`, `chunk_000002.txt` we ş.m. faýllary tertip bilen döredýär. Her faýlda iň köp 500 Unicode simwol bolýar. Bukja öň bar bolsa boş bolmaly: öňki netijeler tötänleýin pozulmaz ýa-da garyşmaz. Ähli bölekler bir gezekde döredilýär; skript we PDF çykaryjy teksti ýatda saklaýar, örän uly kitaplarda ýat talaby ýokary bolup biler.

Gaýtalanýan sözlemler başlangyçda saklanýar, sebäbi kitapda olaryň gaýtalanmagy manyly bolup biler. Takyk gaýtalanýan doly sözlemleri (uly-kiçi harpa seretmezden) bütin dokument boýunça aýyrmak isleseňiz:

```bash
python tts_chunks.py kitap.pdf --output-dir kitap_bolekleri --max-chars 500 --dedupe
```

Bu diňe birmeňzeş sözlemleri aýyrýar, meňzeş manyly tekstleri tanamaýar; käbir zerur gaýtalamalar hem aýrylyp bilner. Netijäni gözden geçiriň.

## Tema boýunça kategoriýalara bölmek

Kategoriýalary we açar sözleri `categories.example.json` ýaly JSON faýlynda öz kitabyňyzyň diline we temasyna görä ýazyň. Soňra:

```bash
python tts_chunks.py kitap.pdf --output-dir netije --categories categories.example.json --max-chars 500
```

Her tema üçin aýratyn bukjada belgili `.txt` faýllar döredilýär; hiç bir açar söze gabat gelmedik sözlemler `uncategorized` bukjasyna düşýär. Her kategoriýada sözlemleriň kitapdaky özara tertibi saklanýar, emma dürli kategoriýalar boýunça asyl global tertip saklanmaýar. Bir sözlem birnäçe kategoriýa gabat gelse, olaryň hersinde ýerleşdirilýär. Isleseňiz `--dedupe` goşup, birmeňzeş gaýtalanýan sözlemleri kategoriýalaşdyrmazdan öň aýryp bilersiňiz.

Bu **açar söz** usulydyr, AI bilen many seljermesi däl: sözleriň dürlenişleri awtomat tanalmaýar, kontekst ýa-da inkär göz öňünde tutulmaýar. Açar sözler söz araçäkleri boýunça, uly-kiçi harpa seretmezden deňeşdirilýär; zerur görnüşleri aýratyn goşuň. Kategoriýa atlarynda diňe latyn harplaryny, sanlary, `_` we `-` ulanyň. Bu mysaldaky kategoriýalar diňe başlangyç nusgasydyr; netijäni barlaň.

## VoiceReader — PDF/dokumenti sese öwürýän web programma

`voicereader/` bukjasynda satylýan taýýar önüm bar: PDF, TXT, Markdown faýllaryny we teksti brauzerde ses bilen okaýar (hiç haýsy maglumat serwere iberilmeýär). Mugt dereje: her dokumentde 1,500 harpa çenli; Pro — bir gezeklik töleg bilen çäksiz.

- Ulanmagyny görmek: `cd voicereader && python3 -m http.server 8080` → `http://localhost:8080`
- Gumroad-da satmagyň ýoly (hasapla, marketing, real garaýyş): `voicereader/SELL.md`
- Önümiň gurluşy we Pro açarynyň işi: `voicereader/README.md`
