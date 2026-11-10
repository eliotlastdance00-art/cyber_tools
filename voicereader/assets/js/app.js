// VoiceReader app logic — all processing happens on this device.
(function () {
  'use strict';
  const cfg = window.VR_CONFIG;
  const $ = (sel) => document.querySelector(sel);
  const synth = window.speechSynthesis;

  const state = {
    text: '',
    sentences: [],
    idx: -1,
    playing: false,
    paused: false,
    skipRequested: false
  };

  // ---------- helpers ----------
  function splitSentences(text) {
    const matches = text.match(/[^.!?…\n]+[.!?…]+["'”)\]]*|[^.!?…\n]+(?:\n|$)|\S[^.!?…]*$/g) || [];
    return matches.map(s => s.replace(/\s+/g, ' ').trim()).filter(Boolean);
  }
  function fmtChars(n) { return n.toLocaleString('en-US'); }
  function estimateMinutes(text, rate) {
    const cps = 15 * (rate || 1); // rough chars/sec for English speech
    return Math.max(1, Math.round(text.length / cps / 60));
  }
  function getStoredSettings() {
    try { return JSON.parse(localStorage.getItem('vr_settings') || '{}'); } catch { return {}; }
  }
  function storeSettings(s) { localStorage.setItem('vr_settings', JSON.stringify(s)); }
  function toast(msg) {
    const t = $('#toast'); t.textContent = msg; t.classList.add('show');
    setTimeout(() => t.classList.remove('show'), 2600);
  }

  // ---------- voices ----------
  const voiceSelect = $('#voiceSelect');
  function populateVoices() {
    const voices = synth.getVoices();
    if (!voices.length) return;
    const saved = getStoredSettings().voiceURI;
    const sorted = voices.slice().sort((a, b) => {
      const score = v => (/en[-_]?US/i.test(v.lang) ? 0 : /^en/i.test(v.lang) ? 1 : /tr|ru/i.test(v.lang) ? 2 : 3);
      return score(a) - score(b) || a.lang.localeCompare(b.lang);
    });
    voiceSelect.innerHTML = sorted.map(v =>
      `<option value="${v.voiceURI}">${v.name} — ${v.lang}${v.localService ? '' : ' (online)'}</option>`
    ).join('');
    const wanted = saved && sorted.find(v => v.voiceURI === saved);
    voiceSelect.value = wanted ? wanted.voiceURI : sorted[0].voiceURI;
  }
  synth.onvoiceschanged = populateVoices;
  populateVoices();
  function currentVoice() {
    return synth.getVoices().find(v => v.voiceURI === voiceSelect.value) || null;
  }

  // rate / pitch / volume
  const rate = $('#rate'), pitch = $('#pitch'), volume = $('#volume');
  const rateVal = $('#rateVal'), pitchVal = $('#pitchVal');
  const saved = getStoredSettings();
  if (saved.rate) rate.value = saved.rate;
  if (saved.pitch) pitch.value = saved.pitch;
  if (saved.voiceURI) { /* applied in populateVoices */ }
  rateVal.textContent = Number(rate.value).toFixed(1) + '×';
  pitchVal.textContent = Number(pitch.value).toFixed(1);
  [rate, pitch, volume].forEach(el => el.addEventListener('input', () => {
    rateVal.textContent = Number(rate.value).toFixed(1) + '×';
    pitchVal.textContent = Number(pitch.value).toFixed(1);
    storeSettings({ ...getStoredSettings(), rate: rate.value, pitch: pitch.value, voiceURI: voiceSelect.value });
  }));
  voiceSelect.addEventListener('change', () =>
    storeSettings({ ...getStoredSettings(), voiceURI: voiceSelect.value, rate: rate.value, pitch: pitch.value }));

  // ---------- text source ----------
  const docText = $('#docText');
  const charCount = $('#charCount');
  const limitNote = $('#limitNote');
  const estTime = $('#estTime');

  function refreshMeta() {
    const len = state.text.length;
    charCount.textContent = fmtChars(len) + ' chars';
    estTime.textContent = '≈ ' + estimateMinutes(state.text, Number(rate.value)) + ' min listen';
    const over = !window.VRLicense.isPro() && len > cfg.FREE_CHAR_LIMIT;
    limitNote.textContent = over
      ? `Free limit is ${fmtChars(cfg.FREE_CHAR_LIMIT)} chars — activate Pro for this document.`
      : '';
    limitNote.classList.toggle('warn', over);
  }
  function setText(t, title) {
    state.text = (t || '').trim();
    docText.value = state.text;
    renderReader();
    refreshMeta();
    if (title) $('#docTitle').value = title;
  }
  docText.addEventListener('input', () => { state.text = docText.value; renderReader(); refreshMeta(); });

  // tabs
  document.querySelectorAll('.tab').forEach(tab => tab.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t === tab));
    $('#panePaste').style.display = tab.dataset.tab === 'paste' ? '' : 'none';
    $('#paneUpload').style.display = tab.dataset.tab === 'upload' ? '' : 'none';
  }));

  // file upload (PDF / TXT / MD) — drag&drop + picker
  const drop = $('#drop'), fileInput = $('#fileInput');
  drop.addEventListener('click', () => fileInput.click());
  ['dragover', 'dragleave', 'drop'].forEach(evt => drop.addEventListener(evt, (e) => {
    e.preventDefault();
    drop.classList.toggle('drag', evt === 'dragover');
    if (evt === 'drop' && e.dataTransfer.files.length) handleFile(e.dataTransfer.files[0]);
  }));
  fileInput.addEventListener('change', () => fileInput.files.length && handleFile(fileInput.files[0]));

  async function handleFile(file) {
    const name = file.name || 'document';
    try {
      if (/\.pdf$/i.test(name)) {
        const text = await extractPdfText(file);
        if (!text.trim()) { toast('No selectable text — scanned PDFs need OCR first.'); return; }
        setText(text, name.replace(/\.pdf$/i, ''));
      } else if (/\.(txt|md|text)$/i.test(name)) {
        setText(await file.text(), name.replace(/\.(txt|md|text)$/i, ''));
      } else {
        toast('Unsupported file — use PDF, TXT or MD.'); return;
      }
      toast('Loaded: ' + name);
    } catch (err) {
      console.error(err);
      toast('Could not read the file.');
    }
  }

  async function extractPdfText(file) {
    const pdfjs = await import('./assets/js/vendor/pdf.min.mjs');
    pdfjs.GlobalWorkerOptions.workerSrc = './assets/js/vendor/pdf.worker.min.mjs';
    const data = new Uint8Array(await file.arrayBuffer());
    const doc = await pdfjs.getDocument({ data }).promise;
    const parts = [];
    for (let p = 1; p <= doc.numPages; p++) {
      const page = await doc.getPage(p);
      const content = await page.getTextContent();
      parts.push(content.items.map(it => ('str' in it ? it.str : '')).join(' '));
    }
    return parts.join('\n\n');
  }

  // ---------- reader / speech ----------
  const reader = $('#reader');
  function renderReader() {
    stopSpeaking(false);
    state.sentences = splitSentences(state.text);
    state.idx = -1;
    reader.innerHTML = state.sentences
      .map((s, i) => `<span class="s" data-i="${i}">${escapeHtml(s)} </span>`)
      .join('');
    updateProgress();
  }
  function escapeHtml(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  reader.addEventListener('click', (e) => {
    const span = e.target.closest('span.s'); if (!span) return;
    jumpTo(Number(span.dataset.i));
  });
  function highlight(i) {
    reader.querySelectorAll('span.s.active').forEach(el => el.classList.remove('active'));
    if (i >= 0) {
      const el = reader.querySelector(`span.s[data-i="${i}"]`);
      if (el) { el.classList.add('active'); el.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); }
    }
  }
  function updateProgress() {
    const total = state.sentences.length;
    const done = Math.max(0, state.idx) + (state.playing || state.paused ? 1 : 0);
    $('#progressBar').style.width = (total ? Math.min(100, (done / total) * 100) : 0) + '%';
    $('#progressLabel').textContent = total ? `Sentence ${Math.min(done, total)} / ${total}` : 'Ready';
  }
  function speakFrom(i) {
    if (i >= state.sentences.length) { stopSpeaking(true); return; }
    state.idx = i;
    highlight(i); updateProgress();
    const u = new SpeechSynthesisUtterance(state.sentences[i]);
    const v = currentVoice(); if (v) { u.voice = v; u.lang = v.lang; }
    u.rate = Number(rate.value); u.pitch = Number(pitch.value); u.volume = Number(volume.value);
    u.onend = () => { if (state.playing && !state.skipRequested) speakFrom(i + 1); state.skipRequested = false; };
    u.onerror = () => { if (state.playing) speakFrom(i + 1); };
    synth.speak(u);
  }
  function startSpeaking() {
    if (!state.sentences.length) renderReader();
    if (!state.sentences.length) { toast('Add some text first.'); return; }
    if (!window.VRLicense.isPro() && state.text.length > cfg.FREE_CHAR_LIMIT) { openModal('limit'); return; }
    state.playing = true; state.paused = false;
    synth.cancel();
    speakFrom(state.idx >= 0 ? state.idx : 0);
    syncTransport();
  }
  function pauseSpeaking() {
    if (!state.playing) return;
    synth.pause(); state.paused = true; syncTransport();
  }
  function resumeSpeaking() {
    if (!state.paused) return;
    synth.resume(); state.paused = false; syncTransport();
  }
  function stopSpeaking(resetIdx) {
    synth.cancel();
    state.playing = false; state.paused = false;
    if (resetIdx !== false) { state.idx = -1; highlight(-1); }
    syncTransport(); updateProgress();
  }
  function jumpTo(i) {
    const wasPlaying = state.playing;
    state.skipRequested = true;
    synth.cancel(); state.skipRequested = false;
    state.idx = i; highlight(i); updateProgress();
    if (wasPlaying) { state.playing = true; speakFrom(i); }
  }
  function syncTransport() {
    $('#btnPlay').textContent = state.paused ? '▶ Resume' : state.playing ? '❚❚ Speaking…' : '▶ Play';
    $('#btnPlay').disabled = state.playing && !state.paused;
    $('#btnPause').style.display = state.playing && !state.paused ? '' : 'none';
    $('#btnResume').style.display = state.paused ? '' : 'none';
  }
  $('#btnPlay').addEventListener('click', startSpeaking);
  $('#btnPause').addEventListener('click', pauseSpeaking);
  $('#btnResume').addEventListener('click', resumeSpeaking);
  $('#btnStop').addEventListener('click', () => stopSpeaking(true));
  window.addEventListener('beforeunload', () => synth.cancel());

  // ---------- library (Pro) ----------
  const libList = $('#libList');
  function getLibrary() {
    try { return JSON.parse(localStorage.getItem('vr_library') || '[]'); } catch { return []; }
  }
  function setLibrary(items) { localStorage.setItem('vr_library', JSON.stringify(items)); }
  function renderLibrary() {
    const items = getLibrary();
    if (!items.length) { libList.innerHTML = '<p class="lib-empty">No saved documents yet. Pro users can keep a library here.</p>'; return; }
    libList.innerHTML = items.map(it => `
      <div class="lib-item" data-id="${it.id}">
        <div style="flex:1;min-width:0">
          <div class="t" title="${escapeHtml(it.title)}">${escapeHtml(it.title)}</div>
          <div class="d">${new Date(it.savedAt).toLocaleDateString()} · ${fmtChars(it.text.length)} chars</div>
        </div>
        <button class="del" title="Delete">✕</button>
      </div>`).join('');
  }
  libList.addEventListener('click', (e) => {
    const item = e.target.closest('.lib-item'); if (!item) return;
    const id = item.dataset.id;
    if (e.target.closest('.del')) {
      setLibrary(getLibrary().filter(x => x.id !== id)); renderLibrary(); return;
    }
    const doc = getLibrary().find(x => x.id === id);
    if (doc) { setText(doc.text, doc.title); toast('Loaded: ' + doc.title); }
  });
  $('#btnSaveLib').addEventListener('click', () => {
    if (!window.VRLicense.isPro()) { openModal('library'); return; }
    const text = state.text.trim();
    if (!text) { toast('Nothing to save yet.'); return; }
    const title = ($('#docTitle').value || 'Untitled').trim() || 'Untitled';
    const items = getLibrary();
    items.unshift({ id: String(Date.now()), title, text, savedAt: Date.now() });
    setLibrary(items.slice(0, 100));
    renderLibrary();
    toast('Saved to library.');
  });

  // ---------- Pro modal ----------
  const modal = $('#proModal');
  const licenseInput = $('#licenseInput');
  const modalStatus = $('#modalStatus');
  const modalReason = $('#modalReason');
  function openModal(reason) {
    modalReason.textContent = reason === 'limit'
      ? `The free tier reads up to ${fmtChars(cfg.FREE_CHAR_LIMIT)} characters per document. Pro removes the limit.`
      : reason === 'library'
        ? 'Saving documents to your library is a Pro feature.'
        : 'Unlock unlimited length and the document library with a one-time lifetime license.';
    modalStatus.textContent = ''; modalStatus.className = 'modal-status';
    modal.classList.add('open');
    setTimeout(() => licenseInput.focus(), 60);
  }
  function closeModal() { modal.classList.remove('open'); }
  $('#modalClose').addEventListener('click', closeModal);
  modal.addEventListener('click', (e) => { if (e.target === modal) closeModal(); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeModal(); });
  $('#btnGoPro').addEventListener('click', () => openModal('generic'));

  $('#btnActivate').addEventListener('click', async () => {
    const key = licenseInput.value;
    if (!key.trim()) { modalStatus.textContent = 'Paste your license key first.'; modalStatus.className = 'modal-status err'; return; }
    modalStatus.textContent = 'Checking key…'; modalStatus.className = 'modal-status';
    $('#btnActivate').disabled = true;
    const result = await window.VRLicense.verifyLicense(key);
    $('#btnActivate').disabled = false;
    if (result.ok) {
      window.VRLicense.setPro(key);
      modalStatus.textContent = result.source === 'gumroad' ? 'Pro activated ✓ (verified by Gumroad)' : 'Pro activated ✓ (offline check)';
      modalStatus.className = 'modal-status ok';
      applyProState();
      refreshMeta();
      toast('VoiceReader Pro is active. Thank you!');
      setTimeout(closeModal, 1200);
    } else {
      modalStatus.textContent = result.reason || 'Invalid license key.';
      modalStatus.className = 'modal-status err';
    }
  });

  function applyProState() {
    const pro = window.VRLicense.isPro();
    $('#proBadge').style.display = pro ? '' : 'none';
    $('#btnGoPro').style.display = pro ? 'none' : '';
    document.body.classList.toggle('pro', pro);
  }

  // ---------- init ----------
  applyProState();
  renderLibrary();
  renderReader();
  refreshMeta();
  syncTransport();
})();
