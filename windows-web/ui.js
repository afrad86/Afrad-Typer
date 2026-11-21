'use strict';
/* Afrad Typer (web) - typing engine and screens. */

let tab = 'today';
let T = null;            // current session
let timerId = null;
let optsOpen = false;    // settings / options shown (a pop-up in Focus mode)
let sitting = { wpms: [], typingSecs: 0, lastBreak: 0 };
let lastPaceIdx = -1;

const TABS = [['today', 'Daily Practice'], ['practice', 'Practice'], ['advanced', 'Advanced'], ['progress', 'Progress'], ['weak', 'Weak Spots'], ['library', 'Library'], ['guide', 'How it works']];

/* ---------- sounds ---------- */
let actx = null;
function beep(freq, dur, vol) {
  if (!S_().sounds) return;
  try {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    const o = actx.createOscillator(), g = actx.createGain();
    o.frequency.value = freq; o.type = 'sine'; g.gain.value = vol;
    g.gain.exponentialRampToValueAtTime(0.0001, actx.currentTime + dur);
    o.connect(g); g.connect(actx.destination); o.start(); o.stop(actx.currentTime + dur);
  } catch (e) { /* no audio available */ }
}
const soundWrong = () => beep(200, 0.09, 0.08);
const soundDone = ok => { beep(ok ? 880 : 300, 0.18, 0.1); if (ok) setTimeout(() => beep(1175, 0.2, 0.1), 130); };

/* ---------- session ---------- */
function currentMode() { return tab === 'advanced' ? 'stages' : (S_().mode === 'stages' ? 'lessons' : S_().mode); }
const MODE_NAME = { lessons: 'Lessons', timed: 'Timed', passages: 'Passages', symbols: 'Symbols', stages: 'Stages' };

function newSession(opts) {
  opts = opts || {};
  stopTimer();
  const s = S_(), mode = currentMode();
  const t = {
    mode, text: '', label: '', info: '', detail: '', key: null, idx: 0, count: 0, flags: null, timeLimit: 0,
    warm: false, replay: !!opts.replayWords, replayWords: opts.replayWords || null, pace: s.paceWPM || 0, stage: 0,
    pos: 0, started: false, startT: 0, pausedAt: 0, lastKeyAt: 0, states: [], ks: {}, ps: {}, ws: {}, intervals: [],
    correctKeys: 0, totalKeys: 0, correctCount: 0, boostKeys: 0, boostCorrect: 0, lastT: 0, prev: null,
    curWord: -1, curSum: 0, curCount: 0, curErr: false, wordMiss: {}, result: null, mask: []
  };
  if (mode === 'lessons') {
    const items = lessonItems(s);
    if (!items.length) { t.label = 'Add some custom words'; }
    else {
      const per = Math.max(1, s.itemsPerLesson), count = Math.ceil(items.length / per);
      const key = ['drill', s.source, s.scope, s.generator, per].join('|');
      let idx = s.lessonByKey[key] || 0; if (idx < 0 || idx >= count) idx = 0;
      t.idx = idx; t.count = count; t.key = key;
      const chunk = items.slice(idx * per, (idx + 1) * per);
      t.text = lessonText(chunk, s.generator, s.repetition);
      t.label = 'Lesson ' + (idx + 1) + ' / ' + count;
      t.info = chunk.join('    ');
      t.detail = s.source + (s.source === 'Custom' ? '' : ' top ' + s.scope) + ' · ' + s.generator + ' ' + per + '×' + s.repetition + ' · lesson ' + (idx + 1);
      if (s.autoFocus) {
        const ng = s.source === 'Trigrams' ? 3 : s.source === 'Tetragrams' ? 4 : null;
        const boost = adaptiveBoost(s, chunk.length * Math.max(1, s.repetition), ng);
        if (boost) {
          const mixed = interleave(t.text.split(' ').map(w => [w, false]), boost.tokens.map(w => [w, true]));
          t.text = mixed.map(m => m[0]).join(' ');
          t.flags = mixed.map(m => m[1]);
          t.info += '\nAuto-focus: ' + boost.summary;
          t.detail += ' · auto-focus';
        }
      }
    }
  } else if (mode === 'timed') {
    t.timeLimit = s.timedSeconds; t.text = timedText(s.wordPool);
    t.label = s.timedSeconds + '-second test';
    t.info = 'Everyday words from the top ' + s.wordPool + '. Type as much as you can before time runs out.';
    t.detail = s.timedSeconds + ' s test';
  } else if (mode === 'passages') {
    const list = allPassages(); const p = list.find(x => x.id === s.selectedPassage) || list[0];
    const chunks = chunkPassage(p.text, Math.max(120, s.wordCount * 6));
    if (!chunks.length) t.label = 'This passage is empty';
    else {
      const key = 'passage|' + p.id; let idx = s.lessonByKey[key] || 0; if (idx < 0 || idx >= chunks.length) idx = 0;
      t.idx = idx; t.count = chunks.length; t.key = key; t.text = chunks[idx];
      const short = p.title.length > 42 ? p.title.slice(0, 42) + '…' : p.title;
      t.label = short + ' — part ' + (idx + 1) + ' / ' + chunks.length; t.detail = short + ' · part ' + (idx + 1);
    }
  } else if (mode === 'symbols') {
    t.text = symbolsText(s.wordPool, s.wordCount); t.label = 'Numbers & symbols';
    t.info = 'Digits, currency, brackets and punctuation mixed with everyday words.'; t.detail = 'Numbers & symbols';
  } else if (mode === 'stages') {
    const st = TARGETS.includes(s.stageSelected) ? s.stageSelected : 45;
    if (s.warmupEnabled && s.warmupDay !== dayKey()) {
      t.warm = true;
      const recent = data.history.filter(isCounted).slice(-10);
      const avg = recent.length ? recent.reduce((a, r) => a + r.wpm, 0) / recent.length : 40;
      t.pace = Math.max(20, Math.round(avg * 0.7 / 5) * 5);
      t.text = timedText(1000, 40); t.label = 'Warm-up — accuracy first';
      t.info = 'Relaxed warm-up for today: follow the pace marker at ' + t.pace + ' WPM (about 70% of your average) and aim for zero mistakes. It does not count towards your stage. Your stage lessons come next.';
      t.detail = 'Warm-up (stage)';
    } else {
      const mix = stageMix(s, st);
      t.text = decorate(timedText(1000, Math.max(10, s.stageMinWords)), mix.caps, mix.punct);
      t.label = 'Stage ' + st + ' WPM — lesson'; t.info = stageReport(st).text;
      t.detail = 'Stage ' + st + ' WPM lesson'; t.stage = st;
    }
  }
  if (t.replayWords && t.replayWords.length) {
    t.replay = true; t.warm = false; t.flags = null; t.timeLimit = 0; t.stage = 0;
    t.text = t.replayWords.flatMap(w => [w, w, w, w, w]).join(' '); t.label = 'Mistake replay'; t.info = 'Retype each word you slipped on 5 times in a row.'; t.detail = 'Mistake replay';
  }
  if (!['passages', 'symbols', 'stages'].includes(mode) && !t.replay) {
    t.text = decorate(t.text, s.capitalPercent, s.punctuationPercent);
    if (s.capitalPercent > 0) t.detail += ' · caps ' + s.capitalPercent + '%';
    if (s.punctuationPercent > 0) t.detail += ' · punct ' + s.punctuationPercent + '%';
  }
  t.chars = Array.from(t.text);
  t.states = new Array(t.chars.length).fill(0);
  // word ranges and the weak-spot mask
  t.wordAt = new Array(t.chars.length).fill(-1); t.words = [];
  t.mask = new Array(t.chars.length).fill(false);
  let wi = -1, tokenIdx = -1, inTok = false;
  t.chars.forEach((c, i) => {
    if (c === ' ') { inTok = false; return; }
    if (!inTok) { inTok = true; wi++; tokenIdx++; t.words.push([i, i]); }
    t.wordAt[i] = wi; t.words[wi][1] = i + 1;
    if (t.flags && t.flags[tokenIdx]) t.mask[i] = true;
  });
  T = t; lastPaceIdx = -1;
  renderAll();
  if (T.pace > 0 && T.chars.length) markPace(0);
}

function stopTimer() { if (timerId) { clearInterval(timerId); timerId = null; } }
function startTimer() { stopTimer(); timerId = setInterval(tick, 100); }
function elapsedSecs() { return T && T.started ? ((T.pausedAt || performance.now()) - T.startT) / 1000 : 0; }
/* Away from the keyboard: after a few seconds with no key the clock stops; the next key carries on (the pause is not counted). */
function setPauseBar() { const b = $('#pause'); if (b) b.hidden = !(T && T.pausedAt && !T.result); }
function resumeIfPaused() {
  if (!T) return;
  T.lastKeyAt = performance.now();
  if (T.pausedAt) { T.startT += performance.now() - T.pausedAt; T.pausedAt = 0; setPauseBar(); }
}
function tick() {
  if (!T || T.result) return;
  const afk = S_().afkSeconds;
  if (!T.pausedAt && afk > 0 && T.started && T.lastKeyAt && performance.now() - T.lastKeyAt >= afk * 1000) { T.pausedAt = T.lastKeyAt + afk * 1000; setPauseBar(); }
  if (T.pausedAt) { updateStats(); return; }
  updateStats();
  if (T.timeLimit > 0 && elapsedSecs() >= T.timeLimit) { finish(true); return; }
  if (T.pace > 0) markPace(Math.floor(elapsedSecs() * T.pace * 5 / 60));
}
function markPace(i) {
  const spans = $('#inner').children;
  if (lastPaceIdx >= 0 && spans[lastPaceIdx]) spans[lastPaceIdx].classList.remove('pace');
  i = Math.min(i, T.chars.length - 1);
  if (spans[i]) spans[i].classList.add('pace');
  lastPaceIdx = i;
}

/* ---------- typing ---------- */
function finalizeWord() {
  if (T.curWord < 0) return;
  const [a, b] = T.words[T.curWord];
  const w = T.chars.slice(a, b).join('').toLowerCase().replace(/[^\p{L}']/gu, '');
  if (w.length >= 2) {
    const st = T.ws[w] || (T.ws[w] = { attempts: 0, misses: 0, totalMs: 0, timedCount: 0 });
    st.attempts++; if (T.curErr) st.misses++;
    if (T.curCount > 0) { st.totalMs += T.curSum / T.curCount; st.timedCount++; }
    if (T.curErr) T.wordMiss[w] = (T.wordMiss[w] || 0) + 1;
  }
  T.curWord = -1; T.curSum = 0; T.curCount = 0; T.curErr = false;
}
function typeChar(ch) {
  if (!T || T.result || T.pos >= T.chars.length) return;
  const now = performance.now();
  if (!T.started) { T.started = true; T.startT = now; startTimer(); }
  resumeIfPaused();
  const expected = T.chars[T.pos];
  T.totalKeys++;
  const isBoost = !!T.mask[T.pos];
  if (isBoost) T.boostKeys++;
  const ms = T.lastT ? now - T.lastT : null; T.lastT = now;
  const correct = ch === expected;
  const k = expected.toLowerCase();
  const st = T.ks[k] || (T.ks[k] = { attempts: 0, misses: 0, totalMs: 0, timedCount: 0 });
  st.attempts++;
  if (ms !== null && ms < 3000) { st.totalMs += ms; st.timedCount++; T.intervals.push(ms); }
  if (!correct) st.misses++;
  if (T.prev && /\p{L}/u.test(T.prev) && /\p{L}/u.test(expected)) {
    const pk = T.prev.toLowerCase() + k;
    const ps = T.ps[pk] || (T.ps[pk] = { attempts: 0, misses: 0, totalMs: 0, timedCount: 0 });
    ps.attempts++;
    if (ms !== null && ms < 3000) { ps.totalMs += ms; ps.timedCount++; }
    if (!correct) ps.misses++;
  }
  const w = T.wordAt[T.pos];
  if (w >= 0) {
    if (w !== T.curWord) { finalizeWord(); T.curWord = w; }
    if (T.pos > T.words[w][0] && ms !== null && ms < 3000) { T.curSum += ms; T.curCount++; }
    if (!correct) T.curErr = true;
  } else finalizeWord();
  const spans = $('#inner').children;
  if (correct) { T.correctKeys++; if (isBoost) T.boostCorrect++; T.correctCount++; T.states[T.pos] = 1; spans[T.pos].className = 'ok'; }
  else { T.states[T.pos] = 2; spans[T.pos].className = 'bad'; soundWrong(); }
  if (correct || !S_().strictMode) {
    T.prev = expected; T.pos++;
    if (T.pos >= T.chars.length) { finish(false); return; }
  }
  setCaret();
  applyHide();
  updateStats();
}
/* Backspace: take back the last letter so you can retype it (off in strict mode). The mistake still counts against accuracy. */
function backspace() {
  if (!T || T.result) return;
  resumeIfPaused();
  if (S_().strictMode) { // strict mode never moves past a mistake, so Backspace just clears the red mark
    if (T.states[T.pos] === 2) { T.states[T.pos] = 0; const s = $('#inner').children[T.pos]; if (s) s.className = 'cur'; setCaret(); }
    return;
  }
  if (T.pos <= 0) return;
  T.pos--;
  if (T.states[T.pos] === 1) T.correctCount--;
  T.states[T.pos] = 0;
  const sp = $('#inner').children[T.pos]; if (sp) sp.className = '';
  T.prev = T.pos > 0 ? T.chars[T.pos - 1] : null;
  T.curWord = -1; T.curSum = 0; T.curCount = 0; T.curErr = false;
  setCaret(); applyHide(); updateStats();
}
function setCaret() {
  const spans = $('#inner').children;
  $$('#inner .cur').forEach(e => e.classList.remove('cur'));
  const c = spans[T.pos]; if (!c) return;
  c.classList.add('cur');
  const lh = parseFloat(getComputedStyle($('#inner')).lineHeight) || 40;
  const line = Math.round(c.offsetTop / lh);
  $('#inner').style.transform = 'translateY(' + (-Math.max(0, line - 1) * lh) + 'px)';
}
function applyHide() {
  const n = S_().hideAhead; if (!T) return;
  const spans = $('#inner').children;
  const hideOn = n > 0 && T.mode !== 'stages';
  const cw = T.wordAt[Math.min(T.pos, T.chars.length - 1)];
  for (let i = 0; i < spans.length; i++) {
    const w = T.wordAt[i];
    const hide = hideOn && w >= 0 && cw >= 0 && w > cw && w <= cw + n;
    spans[i].classList.toggle('hid', hide);
  }
}

function finish(timedOut) {
  if (!T || T.result) return;
  stopTimer(); finalizeWord();
  const s = S_();
  let secs = elapsedSecs();
  if (timedOut && T.timeLimit > 0) secs = T.timeLimit;
  const minutes = Math.max(secs, 1) / 60;
  const wpm = T.correctCount / 5 / minutes, raw = T.totalKeys / 5 / minutes;
  const acc = T.totalKeys === 0 ? 100 : T.correctKeys / T.totalKeys * 100;
  const steady = T.intervals.filter(x => x < 1000);
  let consistency = 0;
  if (steady.length >= 10) {
    const mean = steady.reduce((a, b) => a + b, 0) / steady.length;
    const v = steady.reduce((a, b) => a + (b - mean) * (b - mean), 0) / steady.length;
    consistency = clamp(100 * (1 - Math.sqrt(v) / Math.max(mean, 1) / 1.5), 0, 100);
  }
  let passed = null, note = '', isStage = false, reasons = '';
  if ((T.mode === 'lessons' || T.mode === 'passages') && !T.replay) {
    let passAcc = acc;
    if (T.boostKeys > 0 && T.totalKeys > T.boostKeys) passAcc = (T.correctKeys - T.boostCorrect) / (T.totalKeys - T.boostKeys) * 100;
    passed = wpm >= s.minWPM && passAcc >= s.minAccuracy;
    if (T.boostKeys > 0) note = 'Pass mark judged on the lesson words (accuracy ' + passAcc.toFixed(1) + '%); the mixed-in weak-spot words do not count against you.';
  }
  if (T.mode === 'stages' && T.warm) {
    s.warmupDay = dayKey(); note = 'Warm-up done. Press Enter to start your stage lessons.';
  } else if (T.mode === 'stages' && !T.replay) {
    isStage = true;
    const t = T.stage, need = stageAccuracy(t), ok = wpm >= t && acc >= need;
    passed = ok; const r = [];
    if (wpm < t) r.push('your speed (' + Math.round(wpm) + ' WPM) is below ' + t);
    if (acc < need) r.push('your accuracy (' + acc.toFixed(1) + '%) is below ' + need + '%');
    reasons = ok ? 'This run counted as a pass.' : 'This run missed because ' + r.join(' and ') + '.';
  }
  const missed = T.replay ? [] : Object.entries(T.wordMiss).sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1)).slice(0, 12).map(e => e[0]);
  T.result = { wpm, raw, acc, consistency, secs, passed, timedOut, note, missed };

  if (T.totalKeys > 0) {
    const top = (o, n) => { const out = {}; Object.entries(o).sort((a, b) => b[1].attempts - a[1].attempts).slice(0, n).forEach(e => { out[e[0]] = e[1]; }); return out; };
    const rec = {
      t: Date.now(), mode: MODE_NAME[T.mode], detail: T.detail + (isStage ? (passed ? ' · passed' : ' · missed') : ''),
      wpm, accuracy: acc, seconds: secs, rawWPM: raw, consistency: steady.length >= 10 ? consistency : null,
      keys: T.ks, pairs: top(T.ps, 20), words: top(T.ws, 25), warm: T.warm, replay: T.replay
    };
    if (isStage) { rec.stage = T.stage; rec.passed = passed; }
    data.history.push(rec);
    levelInfo(true);
    sitting.wpms.push(wpm); sitting.typingSecs += secs;
  }
  if (isStage) T.result.note = stageNote(reasons);
  if (note && isStage) T.result.note += ' ' + note;
  if (!T.replay && !T.warm) T.result.pace = null;
  save();
  soundDone(passed !== false);
  renderAll();
  if (s.breakReminder && sitting.typingSecs - sitting.lastBreak >= 25 * 60) showModal('Time for a short break', 'You have been typing for about 25 minutes. Rest your hands and eyes for a few minutes, then come back fresh.', 'Continue', () => { sitting.lastBreak = sitting.typingSecs; });
}
function stageNote(reasons) {
  const s = S_(), t = T.stage, rep = stageReport(t);
  if (t <= s.stageCleared) return reasons + ' This stage was already cleared, so your ladder progress is unchanged.';
  if (rep.cleared) {
    s.stageCleared = t;
    const nx = nextStage(t);
    if (nx) { s.stageSelected = nx; showModal('Stage unlocked!', 'You cleared the ' + t + ' WPM stage and unlocked the ' + nx + ' WPM stage. Great work!', 'Continue'); return 'Stage ' + t + ' cleared! Stage ' + nx + ' is now unlocked. ' + rep.text; }
    showModal('All stages cleared!', 'You cleared the ' + t + ' WPM stage, the last one. You have completed every stage!', 'Continue');
    return 'Stage ' + t + ' cleared. You have completed every stage! ' + rep.text;
  }
  const more = Math.max(0, s.stageMinLessons - rep.window);
  const tail = more > 0 ? ' At least ' + more + ' more lesson(s) needed.' : ' Keep going: you need ' + rep.need + ' passes among your latest ' + s.stageMinLessons + ' lessons.';
  return reasons + ' Not unlocked yet.' + tail + ' ' + rep.text;
}
function proceed() {
  const s = S_();
  if (T && T.result && T.result.passed !== false && ['lessons', 'passages'].includes(T.mode) && !T.replay && T.key) {
    s.lessonByKey[T.key] = (T.idx + 1) % T.count; save();
  }
  newSession();
}
function retry() { newSession(T && T.replay ? { replayWords: T.replayWords } : null); }

/* ---------- key handling ---------- */
window.addEventListener('keydown', e => {
  if (!$('#app') || $('#app').hidden || !T) return;
  if (!$('#modal').hidden) { if (e.key === 'Enter') { e.preventDefault(); $('#modal-ok').click(); } return; }
  if (tab !== 'practice' && tab !== 'advanced') return;
  const tag = (e.target.tagName || '').toLowerCase();
  // Esc always restarts the lesson, even right after you used a drop-down or button.
  if (e.key === 'Escape' && !e.ctrlKey && !e.metaKey && !e.altKey && !(tag === 'input' && e.target.type !== 'checkbox') && tag !== 'textarea') { e.preventDefault(); if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); if (S_().focusMode) { S_().focusMode = false; optsOpen = false; save(); } retry(); return; }
  if (['input', 'textarea', 'select'].includes(tag)) return;
  if (e.ctrlKey || e.metaKey || e.altKey) return;
  if (T.result) {
    if (e.key === 'Enter') { e.preventDefault(); proceed(); }
    else if (e.key === 'Tab') { e.preventDefault(); if (T.result.passed === true) proceed(); else retry(); }
    else if (e.key === 'Escape') { e.preventDefault(); retry(); }
    return;
  }
  if (e.key === 'Escape' || e.key === 'Tab') { e.preventDefault(); if (T.started) retry(); return; }
  if (e.key === 'Backspace') { e.preventDefault(); backspace(); return; }
  if (e.key === ' ') e.preventDefault();
  if (e.key.length === 1) { e.preventDefault(); typeChar(e.key); }
});

/* ---------- modal ---------- */
function showModal(title, text, btn, onOk) {
  $('#modal-title').textContent = title; $('#modal-text').textContent = text; $('#modal-ok').textContent = btn || 'OK';
  $('#modal').hidden = false;
  $('#modal-ok').onclick = () => { $('#modal').hidden = true; if (onOk) onOk(); };
}

/* ---------- rendering: practice ---------- */
const radio = (key, opts, val, num) => '<div class="radios">' + opts.map(o => '<button class="opt' + (o === val ? ' on' : '') + '" data-set="' + key + '" data-val="' + o + '"' + (num ? ' data-num="1"' : '') + '>' + o + '</button>').join('') + '</div>';
const toggle = (key, val, label) => '<label class="tog"><input type="checkbox" data-input="' + key + '"' + (val ? ' checked' : '') + '> ' + label + '</label>';

function renderAll() {
  const s = S_();
  renderTabs();
  $$('.pane').forEach(p => { p.hidden = true; });
  if (tab === 'practice' || tab === 'advanced') { $('#pane-practice').hidden = false; renderPractice(); }
  else { const p = $('#pane-' + tab); p.hidden = false; ({ today: renderToday, progress: renderProgress, weak: renderWeak, library: renderLibrary, guide: renderGuide })[tab](p); }
  renderLevel();
  renderGoal();
  const hasPic = !!avatarOf(user);
  $('#who').innerHTML = '<div class="whorow"><span data-act="avatar" title="Click to ' + (hasPic ? 'change' : 'add') + ' your picture">' + avatarHtml(user) + '</span><span>' + esc(user) + '</span></div>' +
    '<div class="wl"><span class="wk">Photo</span>' + (hasPic ? '<button class="link" data-act="avatar">Change photo</button> · <button class="link" data-act="avatar-remove">Remove</button>' : '<button class="link" data-act="avatar">Add photo</button>') + '</div>' +
    '<div class="wl"><span class="wk">Password</span>' + (hasPw(user) ? '<button class="link" data-act="pw-change">Change password</button> · <button class="link" data-act="pw-remove">Remove</button>' : '<button class="link" data-act="pw-set">Set a password</button>') + '</div>' +
    '<button class="small" id="switch">Switch user</button>';
}
const PLAN = [
  { key: 'warmup', mode: 'lessons', name: 'Lessons', title: 'Warm-up', detail: 'An easy lesson, slowly. Aim for 100% accuracy, not speed.', share: 0.15, offset: 0 },
  { key: 'lessons', mode: 'lessons', name: 'Lessons', title: 'Lessons', detail: 'Your lessons, with your weak keys, pairs and words mixed in automatically.', share: 0.40, offset: 0.15 },
  { key: 'timed', mode: 'timed', name: 'Timed', title: 'Timed tests', detail: 'Push your speed against the clock.', share: 0.25, offset: 0 },
  { key: 'passages', mode: 'passages', name: 'Passages', title: 'Real text', detail: 'Relax into a steady rhythm on a whole passage.', share: 0.20, offset: 0 }
];
function renderToday(p) {
  const s = S_(), goal = Math.max(1, s.dailyGoalMinutes || 20), todayMin = secondsToday() / 60, target = 100;
  const hs = data.history.filter(isCounted).slice(-10), avg10 = hs.length ? hs.reduce((a, r) => a + r.wpm, 0) / hs.length : 0;
  const mins = share => Math.max(1, Math.round(goal * share));
  let first = null;
  const rows = PLAN.map(it => {
    const need = mins(it.share), off = it.offset > 0 ? mins(it.offset) : 0, done = Math.max(0, secondsToday(it.name) / 60 - off), fin = done >= need;
    if (!fin && !first) first = it;
    return '<div class="plan"><span class="chk' + (fin ? ' ok' : '') + '">' + (fin ? '✓' : '') + '</span><div class="grow"><b>' + it.title + ' — ' + Math.min(done, need).toFixed(0) + ' / ' + need + ' min</b><div class="muted">' + it.detail + '</div></div><button data-go="' + it.mode + '">' + (fin ? 'Again' : 'Start') + '</button></div>';
  }).join('');
  p.innerHTML = '<h2>Daily Practice</h2><p class="muted">' + new Date().toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' }) + '</p>' +
    '<div class="row"><button class="primary" data-go="' + (first ? first.mode : 'lessons') + '">' + (first ? 'Start next step: ' + first.title : 'Practise more') + '</button></div>' +
    '<div class="tiles">' + tile('Minutes today (goal ' + goal + ')', todayMin.toFixed(0)) + tile('Day streak', streakDays()) + tile('Average of last 10 (goal ' + target + ')', avg10.toFixed(0) + ' WPM') + '</div>' +
    '<div class="bar"><i style="width:' + Math.min(100, todayMin / goal * 100).toFixed(0) + '%"></i></div>' +
    '<div class="row"><label>Daily goal: <input type="number" data-input="dailyGoalMinutes" min="5" max="180" step="5" value="' + goal + '" style="width:70px"> minutes</label></div>' +
    '<h3>Suggested session</h3><p class="muted">Short, focused practice beats long occasional sessions. Stay above 95% accuracy and your speed will follow.</p>' + rows;
}
/* Level from your recent typing.
   Sessions that count: normal text modes (not Symbols), no warm-ups or replays, very short runs (under ~30 characters) ignored, the rest weighted by length.
   A lesson or passage repeated on the same day counts once (the best run). Median of the last 30.
   Accuracy below 95% scales your speed down (net speed). Levels have a +/-2 WPM buffer so the tag does not flicker. */
const LEVELS = [[100, 'Pro Max', '#c78bff'], [80, 'Pro', '#e8d44d'], [60, 'Advanced', '#f0883e'], [40, 'Intermediate', '#5fb878'], [0, 'Beginner', '#8ab4f8']];
function levelSessions() {
  const best = new Map(), out = [];
  for (const r of data.history) {
    if (!isCounted(r) || r.mode === 'Symbols' || r.wpm * r.seconds / 12 < 30) continue;
    if (r.mode !== 'Lessons' && r.mode !== 'Passages') { out.push(r); continue; }
    const k = dayKey(new Date(r.t)) + '|' + r.mode + '|' + String(r.detail);
    const i = best.get(k);
    if (i === undefined) { best.set(k, out.length); out.push(r); } else if (r.wpm > out[i].wpm) out[i] = r;
  }
  return out.slice(-30);
}
function pickTier(v, stored) {
  const n = LEVELS.length;
  if (stored !== undefined && stored !== null && stored >= 0 && stored < n) {
    const stay = v >= LEVELS[stored][0] - 2 && (stored === 0 || v < LEVELS[stored - 1][0] + 2);
    if (stay) return stored;
  }
  const i = LEVELS.findIndex(l => v >= l[0]);
  return i < 0 ? n - 1 : i;
}
function levelInfo(commit) {
  const last = levelSessions();
  if (last.length < 10) return { few: last.length };
  const wt = r => Math.min(400, r.wpm * r.seconds / 12);          // longer sessions weigh more (capped)
  const sorted = last.slice().sort((a, b) => a.wpm - b.wpm), tot = sorted.reduce((a, r) => a + wt(r), 0);
  let cum = 0, med = sorted[sorted.length - 1].wpm;
  for (const r of sorted) { cum += wt(r); if (cum >= tot / 2) { med = r.wpm; break; } }
  const w = Math.round(med), acc = last.reduce((a, r) => a + r.accuracy * wt(r), 0) / tot;
  const net = acc >= 95 ? med : med * Math.pow(acc / 95, 2);
  const s = S_(), i = pickTier(net, s.levelTier), plain = pickTier(med, s.levelTierPlain);
  if (commit && (s.levelTier !== i || s.levelTierPlain !== plain)) { s.levelTier = i; s.levelTierPlain = plain; save(); }
  return { w, acc, level: LEVELS[i], held: i > plain, n: last.length };
}
function renderLevel() {
  const el = $('#lvl'), L = levelInfo(false);
  if (L.few !== undefined) { el.innerHTML = '<div class="gt">Your level</div><div class="gs">Do 10 sessions to get your level (' + L.few + ' / 10).</div>'; el.title = ''; return; }
  el.innerHTML = '<div class="lh"><span class="tg" style="background:' + L.level[2] + '">' + L.level[1] + '</span><a class="qm" data-help="level" title="How levels work">?</a></div>' + levelBars(L.level[1]) + '<div class="row2"><div><b>' + L.w + '</b><span>WPM</span></div><div><b>' + L.acc.toFixed(1) + '%</b><span>Accuracy</span></div></div>' + (L.held ? '<div class="gs">Held back by accuracy (needs 95%)</div>' : '');
  el.title = 'Median speed and average accuracy of your last ' + L.n + ' counted sessions';
}
const LEVEL_RANGE = ['100+ WPM', '80–99 WPM', '60–79 WPM', '40–59 WPM', 'below 40 WPM'];
function levelBars(cur) {
  const n = LEVELS.length, ci = LEVELS.findIndex(l => l[1] === cur);
  return '<div class="lbars">' + LEVELS.slice().reverse().map((l, k) => {
    const idx = n - 1 - k, num = k + 1, st = idx < ci ? 'not reached yet' : idx === ci ? 'your level' : 'reached';
    return '<i class="lb' + (idx >= ci ? ' f' : '') + '" style="' + (idx >= ci ? 'background:' + l[2] : '') + '" title="Level ' + num + ' of ' + n + ' · ' + l[1] + ' / ' + LEVEL_RANGE[idx] + ' · ' + st + '"></i>';
  }).join('') + '</div>';
}

const GUIDE = [
  ['level', 'Your level and tag', ['The tag is based on the median speed of your last 30 sessions (warm-ups and mistake replays are not counted). It needs at least 10 sessions.', 'Beginner: below 40 WPM. Intermediate: 40–59. Advanced: 60–79. Pro: 80–99. Pro Max: 100+.', 'Accuracy matters: below 95% average accuracy, your speed counts for proportionally less (at 90% accuracy, 80 WPM counts as about 72). The tag only changes when you are 2 WPM past a boundary, so it does not flicker.', 'Only normal text sessions count (not Symbols), and each session is weighted by its length: a 10-word drill barely moves your level, a long run moves it more (up to about 400 characters). A lesson or passage repeated on the same day counts once, with your best run. The five bars show all levels: filled means reached, empty means still to come.']],
  ['pass', 'Passing a lesson', ['A lesson is passed when you reach {pass} (set in Settings).', 'After a pass, Tab or Enter goes to the next lesson. If you did not pass, Tab repeats the lesson. Missed words can be replayed 5 times each.', 'Weak-spot words mixed in do not count towards the pass mark.']],
  ['stages', 'Advanced stages', ['18 optional stages from 45 to 110 WPM: steps of 5 up to 80, then steps of 3. They never affect normal practice.', 'Each lesson is {stageWords} words. To unlock the next stage, finish {stageLessons} lessons where at least 90% reach the stage speed with {stageLow}% accuracy ({stageHigh}% from 86 WPM).', 'The first stage lesson each day is a slow warm-up and does not count.']],
  ['weak', 'Weak keys and automatic practice', ['From your last 20 sessions the app finds weak keys, slow letter pairs and slow words, and mixes them into your lessons automatically.', 'Trigram and tetragram lessons use only real, common letter groups taken from everyday English words.']],
  ['keys', 'Keys and shortcuts', ['Backspace fixes the last letter; mistakes still count against accuracy. In strict mode Backspace only clears the red mark.', 'Esc restarts the lesson. Tab goes to the next lesson after a pass. Enter also continues.', 'You can hide upcoming words (shown as grey blocks) to train looking ahead less.']],
  ['pause', 'Pause when you stop typing', ['{afk} The pause shows "Press any key to continue ...". You can change it in Settings (off, 2, 3, 5 or 10 seconds).', 'Paused time is not counted in WPM, daily minutes or the timed-test clock. {brk}']],
  ['goal', 'Daily goal, streak and calendar', ['Set your daily goal in minutes. Progress resets at midnight.', 'Daily Practice splits the goal: warm-up 15%, lessons 40%, timed tests 25%, real text 20%.', 'A streak counts consecutive days with practice. The 12-week calendar and the road-to-your-goal forecast appear in Progress; the forecast needs at least 5 practice days.']],
  ['update', 'Updating the app', ['Open Help → Check for updates… in the menu bar. If a newer version exists, choose Install and restart: the app downloads it, replaces itself and reopens. Your progress is kept.', 'It needs an internet connection. The very first update-capable version has to be installed by hand; after that, updates are automatic.']],
  ['safe', 'Backups, sync, passwords and Touch ID', ['A backup is saved automatically every week in Documents\\Afrad Typer\\Backups. You can also choose a sync folder (for example OneDrive) in Progress.', 'Passwords are per user and cannot be recovered. They keep other people out of your profile but are not encryption.', 'Touch ID is available in the Mac app only.']]
];
let guideOpen = 'level';
function guideFill(x) {
  const s = S_();
  return x.replace('{pass}', s.minWPM + ' WPM and ' + s.minAccuracy + '% accuracy').replace('{stageWords}', s.stageMinWords).replace('{stageLessons}', s.stageMinLessons)
    .replace('{stageLow}', 97).replace('{stageHigh}', 96)
    .replace('{afk}', s.afkSeconds > 0 ? 'If you stop typing for ' + s.afkSeconds + ' seconds the app pauses.' : 'Pausing is currently off.')
    .replace('{brk}', s.breakReminder ? 'A break reminder appears after 25 minutes of typing.' : 'Break reminders are currently off.');
}
function renderGuide(p) {
  p.innerHTML = '<h2>How it works</h2><p class="muted">All the rules the app follows, in one place.</p>' + GUIDE.map(g =>
    '<details class="gd" data-gid="' + g[0] + '"' + (g[0] === guideOpen ? ' open' : '') + '><summary>' + g[1] + '</summary>' + g[2].map(x => '<p>' + guideFill(x) + '</p>').join('') + '</details>').join('');
}
let goalEdit = false;
function renderGoal() {
  const g = Math.max(1, S_().dailyGoalMinutes || 20), done = secondsToday() / 60, reached = done >= g;
  const el = $('#goal'); el.className = 'goal' + (reached ? ' done' : '');
  el.innerHTML = '<div class="gt">Today\'s goal <a class="qm" data-help="goal" title="How the daily goal works">?</a></div><div class="gv">' + Math.floor(done) + ' <small>/ ' + g + ' min</small></div><div class="gb"><i style="width:' + Math.min(100, done / g * 100).toFixed(0) + '%"></i></div>' +
    '<div class="gs">' + (reached ? 'Goal reached ✓' : Math.max(1, g - Math.floor(done)) + ' min to go') + '</div>' +
    (goalEdit ? '<div class="gs"><input type="number" data-input="dailyGoalMinutes" min="5" max="480" step="5" value="' + g + '" style="width:60px"> min <a data-act="goal">Done</a></div>' : '<div class="gs"><a data-act="goal">Change goal</a></div>');
}
function renderTabs() { $('#nav').innerHTML = TABS.map(t => '<button class="navbtn' + (t[0] === tab ? ' on' : '') + '" data-tab="' + t[0] + '">' + t[1] + '</button>').join(''); }

function renderPractice() {
  const s = S_(), mode = T.mode, focus = s.focusMode;
  $('#pane-practice').classList.toggle('focus', focus);
  // top row
  const modes = [['lessons', 'Lessons'], ['timed', 'Timed'], ['passages', 'Passages'], ['symbols', 'Symbols']];
  $('#top').innerHTML =
    (mode === 'stages' ? '<span class="modelabel">Advanced stages</span>' :
      '<select data-input="mode">' + modes.map(m => '<option value="' + m[0] + '"' + (m[0] === mode ? ' selected' : '') + '>' + m[1] + '</option>').join('') + '</select>') +
    '<span class="lesson">' + esc(T.label) + '</span><span class="sp"></span>' +
    '<button class="small' + (s.sounds ? ' on' : '') + '" data-act="sounds">Sounds</button>' +
    '<button class="small" data-act="smaller">A−</button><button class="small" data-act="bigger">A+</button>' +
    '<button class="small' + (optsOpen ? ' on' : '') + '" data-act="opts">Settings</button>' +
    '<button class="small' + (focus ? ' on' : '') + '" data-act="focus">Focus</button>';
  // stats
  $('#stats').hidden = focus;
  // options area
  const opts = $('#opts');
  const showOpts = focus ? optsOpen : true;
  opts.hidden = !showOpts; opts.classList.toggle('pop', focus);
  let h = '';
  h += '<div class="row"><b>Words ahead</b>' + (mode === 'stages' ? '<span class="muted"> always visible in stage lessons</span>' :
    '<div class="radios">' + [[0, 'Always visible'], [1, 'Hide next word'], [2, 'Hide next two words']].map(o => '<button class="opt' + (s.hideAhead === o[0] ? ' on' : '') + '" data-set="hideAhead" data-val="' + o[0] + '" data-num="1">' + o[1] + '</button>').join('') + '</div>') + '</div>';
  if (mode === 'lessons') h += lessonPanelHtml(s);
  if (mode === 'stages') h += advancedPanelHtml(s);
  if (optsOpen) h += settingsHtml(s);
  opts.innerHTML = h;
  renderTyping();
  updateStats();
}
function lessonPanelHtml(s) {
  return '<div class="panel"><div class="grid">' +
    '<div><h4>Source</h4>' + radio('source', ['Words', 'Common words', 'Trigrams', 'Tetragrams', 'Custom'], s.source) + '</div>' +
    (s.source === 'Custom' ? '<div><h4>Custom words</h4><textarea data-input="customWords" rows="3" placeholder="Type or paste words separated by spaces">' + esc(s.customWords) + '</textarea></div>' :
      '<div><h4>Scope (Top N)</h4>' + radio('scope', SCOPES, s.scope, true) + '</div>') +
    '<div><h4>Generator</h4>' + radio('generator', ['Combination', 'Repetition'], s.generator) + '</div>' +
    '<div><h4>Threshold</h4><span class="muted">pass at</span> <input type="number" class="num" data-input="minWPM" min="5" max="200" value="' + s.minWPM + '"> WPM <input type="number" class="num" data-input="minAccuracy" min="50" max="100" value="' + s.minAccuracy + '"> % accuracy</div>' +
    '<div><h4>Per lesson</h4><input type="number" class="num" data-input="itemsPerLesson" min="1" max="50" value="' + s.itemsPerLesson + '"> items × <input type="number" class="num" data-input="repetition" min="1" max="20" value="' + s.repetition + '"> repeats</div>' +
    '<div><h4>Options</h4>' + toggle('mixedOrder', s.mixedOrder, 'Mixed order') + ' ' + toggle('autoFocus', s.autoFocus, 'Automatic weak-spot practice') + '</div>' +
    '</div></div>';
}
function settingsHtml(s) {
  const sel = (key, vals, cur, fmt) => '<select data-input="' + key + '" data-num="1">' + vals.map(v => '<option value="' + v + '"' + (v === cur ? ' selected' : '') + '>' + (fmt ? fmt(v) : v) + '</option>').join('') + '</select>';
  return '<div class="panel"><h4>Settings</h4><div class="grid">' +
    '<div>Capital letters <input type="range" min="0" max="30" data-input="capitalPercent" value="' + s.capitalPercent + '"> <b>' + s.capitalPercent + '%</b></div>' +
    '<div>Punctuation <input type="range" min="0" max="30" data-input="punctuationPercent" value="' + s.punctuationPercent + '"> <b>' + s.punctuationPercent + '%</b></div>' +
    '<div>Timed test ' + sel('timedSeconds', [15, 30, 60, 120, 180], s.timedSeconds, v => v + ' s') + '</div>' +
    '<div>Word pool ' + sel('wordPool', [200, 500, 1000, 2000, 2883], s.wordPool, v => 'top ' + v) + '</div>' +
    '<div>Words per round ' + sel('wordCount', [15, 20, 30, 40, 60], s.wordCount) + '</div>' +
    '<div>Lines shown ' + sel('linesShown', [2, 3, 4, 5, 6], s.linesShown) + '</div>' +
    '<div>Pace marker ' + sel('paceWPM', [0, 30, 40, 50, 60, 70, 80, 90, 100, 110], s.paceWPM, v => v ? v + ' WPM' : 'off') + '</div>' +
    '<div>Pause when I stop typing for ' + sel('afkSeconds', [0, 2, 3, 5, 10], s.afkSeconds, v => v ? v + ' s' : 'off') + '</div>' +
    '<div>' + toggle('strictMode', s.strictMode, 'Strict mode (must press the right key)') + '</div>' +
    '<div>' + toggle('breakReminder', s.breakReminder, 'Break reminder every 25 min') + '</div>' +
    '</div></div>';
}
function advancedPanelHtml(s) {
  const cur = TARGETS.includes(s.stageSelected) ? s.stageSelected : 45;
  const mix = stageMix(s, cur);
  let h = '<div class="panel"><h4>Advanced stage ladder</h4><p class="muted">Each lesson is ' + s.stageMinWords + ' words. Clear a stage when at least 90% of your latest ' + s.stageMinLessons + ' lessons reach the stage speed with accuracy ' + 97 + '% (up to 85 WPM) or ' + 96 + '% (from 86 WPM). Only lessons typed here count. The first lesson each day is a slow warm-up that does not count.</p>';
  h += '<div class="grid"><div>My current stage <select data-input="stageSelected" data-num="1">' + TARGETS.map(t => '<option value="' + t + '"' + (t === cur ? ' selected' : '') + '>' + t + ' WPM' + (t <= s.stageCleared ? ' ✓' : '') + '</option>').join('') + '</select></div>' +
    '<div>Lessons needed <input type="number" class="num" data-input="stageMinLessons" min="5" max="100" value="' + s.stageMinLessons + '"></div>' +
    '<div>Words per lesson <input type="number" class="num" data-input="stageMinWords" min="50" max="500" step="10" value="' + s.stageMinWords + '"></div>' +
    '<div>' + toggle('stageAutoMix', s.stageAutoMix, 'Capitals & punctuation ramp up automatically (now ' + mix.caps + '% / ' + mix.punct + '%)') + '</div>' +
    (s.stageAutoMix ? '' : '<div>Capitals <input type="range" min="0" max="30" data-input="stageCapitals" value="' + s.stageCapitals + '"> <b>' + s.stageCapitals + '%</b></div><div>Punctuation <input type="range" min="0" max="30" data-input="stagePunctuation" value="' + s.stagePunctuation + '"> <b>' + s.stagePunctuation + '%</b></div>') +
    '<div>' + toggle('warmupEnabled', s.warmupEnabled, 'Daily slow warm-up') + '</div></div>';
  h += '<div class="ladder">' + TARGETS.map(t => {
    const r = stageReport(t), done = t <= s.stageCleared, here = t === cur;
    return '<button class="step' + (done ? ' done' : '') + (here ? ' here' : '') + '" data-set="stageSelected" data-val="' + t + '" data-num="1" title="' + esc(r.text) + '"><b>' + t + '</b><small>' + (done ? 'cleared' : r.passed + '/' + s.stageMinLessons) + '</small></button>';
  }).join('') + '</div></div>';
  return h;
}

function renderTyping() {
  const s = S_();
  $('#info').textContent = T.info; $('#info').hidden = !T.info;
  const box = $('#box'), inner = $('#inner');
  const fs = Math.min(s.textSize, Math.max(16, box.clientWidth / 24));
  inner.style.fontSize = fs + 'px'; inner.style.lineHeight = Math.round(fs * 1.7) + 'px';
  box.style.height = Math.round(fs * 1.7 * s.linesShown + 24) + 'px';
  inner.style.transform = 'translateY(0)';
  inner.innerHTML = T.chars.map((c, i) => '<span' + (T.states[i] === 1 ? ' class="ok"' : T.states[i] === 2 ? ' class="bad"' : '') + '>' + esc(c) + '</span>').join('');
  setCaret(); applyHide();
  if (T.pace > 0) markPace(Math.floor(elapsedSecs() * T.pace * 5 / 60));
  setPauseBar();
  const r = T.result, rc = $('#result');
  rc.hidden = !r;
  $('#hint').textContent = r ? '' : (T.started ? 'Backspace fixes a mistake  ·  Esc / Tab: restart' : 'Start typing…  (Backspace fixes mistakes  ·  Esc / Tab: new text)');
  if (r) {
    let h = '<div class="tiles">' + tile('WPM', r.wpm.toFixed(0)) + tile('Accuracy', r.acc.toFixed(1) + '%') + tile('Raw', r.raw.toFixed(0)) + tile('Consistency', r.consistency ? r.consistency.toFixed(0) + '%' : '—') + tile('Time', r.secs.toFixed(0) + ' s') + '</div>';
    if (r.passed !== null) h += '<p class="verdict ' + (r.passed ? 'pass' : 'fail') + '">' + (r.passed ? 'Passed' : 'Not passed — try again') + '</p>';
    if (r.note) h += '<p class="note">' + esc(r.note) + '</p>';
    if (r.missed.length) h += '<p>Words you slipped on: <b>' + r.missed.map(esc).join(', ') + '</b></p><button class="primary" data-act="replay">Retype them 5 times</button> ';
    h += '<button class="primary" data-act="next">Next (Enter' + (r.passed === true ? ' or Tab' : '') + ')</button> <button data-act="retry">Retry (Esc' + (r.passed === true ? '' : ' or Tab') + ')</button>';
    rc.innerHTML = h;
    T.result.missed = r.missed;
  }
}
const tile = (t, v, c) => '<div class="tile"><div class="v"' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</div><div class="t">' + t + '</div></div>';
function updateStats() {
  if (!T) return;
  const s = S_();
  const secs = T.result ? T.result.secs : elapsedSecs();
  const wpm = T.result ? T.result.wpm : (T.started ? T.correctCount / 5 / (Math.max(secs, 1) / 60) : 0);
  const acc = T.totalKeys ? T.correctKeys / T.totalKeys * 100 : 100;
  const showTh = T.mode === 'lessons' || T.mode === 'passages';
  const wc = showTh && T.started ? (wpm >= s.minWPM ? 'var(--good)' : 'var(--bad)') : null;
  const ac = showTh && T.totalKeys ? (acc >= s.minAccuracy ? 'var(--good)' : 'var(--bad)') : null;
  const left = T.timeLimit > 0 ? Math.max(0, T.timeLimit - secs) : secs;
  const avg = sitting.wpms.length ? sitting.wpms.reduce((a, b) => a + b, 0) / sitting.wpms.length : 0;
  $('#stats').innerHTML = tile('WPM', wpm.toFixed(0), wc) + tile('Accuracy', acc.toFixed(1) + '%', ac) + tile(T.timeLimit ? 'Time left' : 'Time', left.toFixed(T.timeLimit ? 0 : 1) + ' s' + (T.pausedAt ? ' ⏸' : '')) +
    tile('Progress', T.chars.length ? Math.round(T.pos / T.chars.length * 100) + '%' : '—') + tile('Sitting avg', avg ? avg.toFixed(0) : '—');
}

/* ---------- rendering: other screens ---------- */
function lineChart(canvas, vals, color, lo, hi, label) {
  const dpr = window.devicePixelRatio || 1, w = canvas.clientWidth, h = canvas.clientHeight;
  canvas.width = w * dpr; canvas.height = h * dpr;
  const g = canvas.getContext('2d'); g.scale(dpr, dpr); g.clearRect(0, 0, w, h);
  const cs = getComputedStyle(document.body);
  g.fillStyle = cs.getPropertyValue('--muted'); g.font = '11px system-ui';
  if (vals.length < 2) { g.fillText('Not enough sessions yet', 10, 20); return; }
  const mn = lo !== null ? lo : Math.min.apply(null, vals) - 2, mx = hi !== null ? hi : Math.max.apply(null, vals) + 2;
  const L = 34, R = 8, Tp = 8, B = 18;
  g.strokeStyle = 'rgba(128,128,128,.25)'; g.lineWidth = 1;
  for (let i = 0; i <= 4; i++) { const y = Tp + (h - Tp - B) * i / 4; g.beginPath(); g.moveTo(L, y); g.lineTo(w - R, y); g.stroke(); g.fillText(Math.round(mx - (mx - mn) * i / 4), 2, y + 4); }
  g.strokeStyle = color; g.lineWidth = 2; g.beginPath();
  vals.forEach((v, i) => { const x = L + (w - L - R) * i / (vals.length - 1), y = Tp + (h - Tp - B) * (1 - (v - mn) / (mx - mn || 1)); i ? g.lineTo(x, y) : g.moveTo(x, y); });
  g.stroke(); g.fillText(label, L + 4, h - 4);
}
function streakDays() {
  const days = new Set(data.history.filter(isCounted).map(r => dayKey(new Date(r.t))));
  let d = new Date(), n = 0;
  if (!days.has(dayKey(d))) d.setDate(d.getDate() - 1);
  while (days.has(dayKey(d))) { n++; d.setDate(d.getDate() - 1); }
  return n;
}
function roadHtml() {
  const target = 100, f = forecast(target), pct = Math.min(100, f.cur / target * 100);
  let msg;
  if (f.state === 'reached') msg = 'You are at <b>' + target + ' WPM or more</b> on average. Goal reached!';
  else if (f.state === 'few') msg = f.span ? 'Practise over a longer stretch (at least 10 days apart) and I will estimate your date.' : 'Practise on ' + f.need + ' more day' + (f.need === 1 ? '' : 's') + ' and I will estimate your date.';
  else if (f.state === 'flat') msg = 'Your average has been flat over the last 6 weeks, so there is no date yet. Short, accurate sessions most days are what move it.';
  else if (f.state === 'far') msg = 'At your recent pace (' + f.perWeek.toFixed(1) + ' WPM a week) it would take more than 2 years. More regular practice will change that.';
  else msg = 'At your recent pace (<b>+' + f.perWeek.toFixed(1) + ' WPM a week</b>) you reach ' + target + ' WPM around <b>' + f.date.toLocaleDateString(undefined, { month: 'long', year: 'numeric' }) + '</b>.';
  return '<h3>Road to ' + target + ' WPM</h3><div class="panel">Current average <b>' + f.cur.toFixed(0) + '</b> (last 10 sessions) → goal <b>' + target + '</b><div class="bar" style="margin:10px 0"><i style="width:' + pct.toFixed(0) + '%"></i></div><div class="muted">' + msg + '</div><div class="muted" style="margin-top:6px">This is an estimate from your own trend, not a promise.</div></div>';
}
function calendarHtml() {
  const by = minutesByDay(), goal = Math.max(1, S_().dailyGoalMinutes || 20), today = new Date(); today.setHours(12, 0, 0, 0);
  const start = new Date(today); start.setDate(start.getDate() - ((start.getDay() + 6) % 7) - 77);
  let cells = '';
  for (let i = 0; i < 84; i++) {
    const d = new Date(start); d.setDate(start.getDate() + i);
    if (d > today) { cells += '<span class="cd fut"></span>'; continue; }
    const m = by[dayKey(d)] || 0, lv = m <= 0 ? 0 : m < goal / 2 ? 1 : m < goal ? 2 : 3;
    cells += '<span class="cd l' + lv + '" title="' + d.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' }) + ': ' + Math.round(m) + ' min"></span>';
  }
  return '<h3>Practice calendar</h3><div class="panel"><div class="cal">' + cells + '</div><div class="muted" style="margin-top:8px">Last 12 weeks, one square per day. Darker orange = more minutes; the darkest means you reached your daily goal. Current streak <b>' + streakDays() + '</b> day(s) · best <b>' + bestStreak() + '</b>.</div></div>';
}
function renderProgress(p) {
  const hs = data.history.filter(isCounted);
  const best = hs.reduce((m, r) => Math.max(m, r.wpm), 0);
  const last = hs.slice(-10), avg = last.length ? last.reduce((a, r) => a + r.wpm, 0) / last.length : 0, avgA = last.length ? last.reduce((a, r) => a + r.accuracy, 0) / last.length : 0;
  const today = dayKey(), mins = data.history.filter(r => dayKey(new Date(r.t)) === today).reduce((a, r) => a + r.seconds, 0) / 60;
  p.innerHTML = '<h2>Progress — ' + esc(user) + '</h2><div class="tiles">' + tile('Sessions', hs.length) + tile('Best WPM', best.toFixed(0)) + tile('Avg WPM (last 10)', avg.toFixed(0)) + tile('Avg accuracy (last 10)', avgA.toFixed(1) + '%') + tile('Typed today', mins.toFixed(0) + ' min') + tile('Day streak', streakDays()) + '</div>' +
    '<div class="two"><div>' + roadHtml() + '</div><div>' + calendarHtml() + '</div></div>' +
    '<div class="charts"><canvas id="c1"></canvas><canvas id="c2"></canvas></div>' +
    '<div class="row"><button id="exp">Export backup</button> <label class="btn">Import backup<input type="file" id="imp" accept=".json" hidden></label> <button id="rst" class="danger">Reset history</button> <button id="del" class="danger">Delete this user</button></div>' +
    '<p class="muted">Your progress is stored on this computer. Export backup saves a copy by hand.</p><div id="deskbox"></div>' +
    '<h3>Recent sessions</h3><table class="tbl"><tr><th>When</th><th>Mode</th><th>Details</th><th>WPM</th><th>Acc</th></tr>' +
    data.history.slice(-40).reverse().map(r => '<tr><td>' + new Date(r.t).toLocaleString() + '</td><td>' + esc(r.mode) + '</td><td>' + esc(r.detail) + '</td><td>' + r.wpm.toFixed(0) + '</td><td>' + r.accuracy.toFixed(1) + '%</td></tr>').join('') + '</table>';
  const series = hs.slice(-80);
  lineChart($('#c1'), series.map(r => r.wpm), getComputedStyle(document.body).getPropertyValue('--accent'), null, null, 'WPM, last ' + series.length + ' sessions');
  if (window.renderDesktopBox) renderDesktopBox();
  lineChart($('#c2'), series.map(r => r.accuracy), '#5fb878', 80, 100, 'Accuracy %');
}
function renderWeak(p) {
  const ks = keyStats(20), ps = pairStats(20), ws = wordStats(20), base = baselineMs(20);
  const n = recentRecords(20).length;
  const rowsK = Object.entries(ks).filter(([k, v]) => v.attempts >= 5 && k.trim()).sort((a, b) => weakScore(b[1]) - weakScore(a[1])).slice(0, 12);
  const rowsP = Object.entries(ps).filter(([k, v]) => v.attempts >= 3).sort((a, b) => pairScore(b[1]) - pairScore(a[1])).slice(0, 12);
  const rowsW = Object.entries(ws).filter(([k, v]) => v.attempts >= 2).sort((a, b) => wordScore(b[1], base) - wordScore(a[1], base)).slice(0, 12);
  const tbl = (title, rows, up) => '<h3>' + title + '</h3>' + (rows.length ? '<table class="tbl"><tr><th>Item</th><th>Presses</th><th>Missed</th><th>Avg speed</th></tr>' + rows.map(([k, v]) => '<tr><td><b>' + esc(up ? k.toUpperCase() : k) + '</b></td><td>' + v.attempts + '</td><td>' + (missRate(v) * 100).toFixed(1) + '%</td><td>' + Math.round(avgMs(v)) + ' ms</td></tr>').join('') + '</table>' : '<p class="muted">Not enough data yet.</p>');
  p.innerHTML = '<h2>Weak spots</h2><p class="muted">A report from your last ' + n + ' sessions. The app already adds extra practice for these inside your lessons automatically — nothing to set up.</p>' + tbl('Weak keys', rowsK, true) + tbl('Slow letter pairs', rowsP, true) + tbl('Slow words', rowsW, false);
}
function renderLibrary(p) {
  const list = allPassages(), s = S_();
  p.innerHTML = '<h2>Library</h2><p class="muted">Pick a passage to practise in the Passages mode, or add your own text.</p>' +
    list.map(x => '<div class="lib' + (x.id === s.selectedPassage ? ' on' : '') + '"><div><b>' + esc(x.title) + '</b><div class="muted">' + esc(x.text.slice(0, 140)) + '…</div></div><div><button data-lib="use" data-id="' + x.id + '">' + (x.id === s.selectedPassage ? 'Selected' : 'Use') + '</button>' + (x.builtin ? '' : ' <button class="danger" data-lib="del" data-id="' + x.id + '">Delete</button>') + '</div></div>').join('') +
    '<h3>Add a passage</h3><input id="ptitle" placeholder="Title" class="wide"><textarea id="ptext" rows="6" class="wide" placeholder="Paste or type the text you want to practise"></textarea><button class="primary" id="padd">Add passage</button>';
}

/* ---------- events ---------- */
function applyInput(key, val) {
  const s = S_(); s[key] = val; save();
  const content = ['mode', 'source', 'scope', 'generator', 'itemsPerLesson', 'repetition', 'mixedOrder', 'autoFocus', 'customWords', 'capitalPercent', 'punctuationPercent', 'timedSeconds', 'wordPool', 'wordCount', 'stageSelected', 'stageMinLessons', 'stageMinWords', 'stageAutoMix', 'stageCapitals', 'stagePunctuation', 'warmupEnabled', 'selectedPassage', 'paceWPM'];
  if (content.includes(key)) newSession(); else renderAll();
}
document.addEventListener('click', e => {
  const t = e.target;
  let b;
  if ((b = t.closest('[data-tab]'))) { tab = b.dataset.tab; optsOpen = false; if (tab === 'practice' || tab === 'advanced') newSession(); else renderAll(); return; }
  if ((b = t.closest('[data-help]'))) { guideOpen = b.dataset.help; tab = 'guide'; renderAll(); return; }
  if ((b = t.closest('[data-go]'))) { S_().mode = b.dataset.go; save(); tab = 'practice'; newSession(); return; }
  if ((b = t.closest('[data-set]'))) { applyInput(b.dataset.set, b.dataset.num ? Number(b.dataset.val) : b.dataset.val); return; }
  if ((b = t.closest('[data-act]'))) {
    const s = S_(), a = b.dataset.act;
    if (a === 'goal') { goalEdit = !goalEdit; renderAll(); }
    else if (a === 'sounds') { s.sounds = !s.sounds; save(); renderAll(); }
    else if (a === 'smaller') { s.textSize = Math.max(16, s.textSize - 2); save(); renderAll(); }
    else if (a === 'bigger') { s.textSize = Math.min(60, s.textSize + 2); save(); renderAll(); }
    else if (a === 'opts') { optsOpen = !optsOpen; renderAll(); }
    else if (a === 'focus') { s.focusMode = !s.focusMode; optsOpen = false; save(); renderAll(); }
    else if (a === 'next') proceed();
    else if (a === 'retry') retry();
    else if (a === 'replay') newSession({ replayWords: T.result.missed });
    else if (a === 'avatar') $('#avfile').click();
    else if (a === 'pw-set') setPasswordFlow(false);
    else if (a === 'pw-change') setPasswordFlow(true);
    else if (a === 'pw-remove') removePasswordFlow();
    else if (a === 'avatar-remove') { localStorage.removeItem(LS + 'avatar.' + user); renderAll(); }
    return;
  }
  if (t.id === 'switch') { stopTimer(); showPicker(); return; }
  if ((b = t.closest('[data-lib]'))) {
    if (b.dataset.lib === 'use') { S_().selectedPassage = b.dataset.id; save(); renderAll(); }
    else if (confirm('Delete this passage?')) { data.passages = data.passages.filter(x => x.id !== b.dataset.id); if (S_().selectedPassage === b.dataset.id) S_().selectedPassage = 'starter0'; save(); renderAll(); }
    return;
  }
  if (t.id === 'padd') {
    const title = $('#ptitle').value.trim() || 'My passage', text = $('#ptext').value.trim();
    if (text) { data.passages.push({ id: 'p' + Date.now(), title, text }); save(); renderAll(); }
    return;
  }
  if (t.id === 'exp') {
    const blob = new Blob([JSON.stringify(exportPayload(), null, 1)], { type: 'application/json' });
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'afrad-typer-' + user + '-' + dayKey() + '.json'; a.click(); return;
  }
  if (t.id === 'rst') { if (confirm('Delete ALL practice history for ' + user + '? This cannot be undone.')) { data.history = []; data.resetAt = Date.now(); save(); renderAll(); } return; }
  if (t.id === 'del') { if (confirm('Delete the user "' + user + '" and all their data from this browser?')) { localStorage.removeItem(LS + 'data.' + user); localStorage.removeItem(LS + 'avatar.' + user); localStorage.removeItem(LS + 'pw.' + user); profiles = profiles.filter(x => x !== user); saveJSON('profiles', profiles); showPicker(); } return; }
});
document.addEventListener('change', e => {
  const t = e.target;
  if (t.id === 'avfile') { setAvatarFromFile(t.files[0]); t.value = ''; return; }
  if (t.id === 'imp' && t.files[0]) {
    const rd = new FileReader();
    rd.onload = () => {
      try {
        const j = JSON.parse(rd.result), d = j.data || j;
        if (j.avatar && !avatarOf(user)) saveJSON('avatar.' + user, j.avatar);
        mergeInto(data, d);
        save(); renderAll(); alert('Backup imported: ' + (d.history || []).length + ' sessions merged.');
      } catch (err) { alert('That file could not be read as an Afrad Typer backup.'); }
    };
    rd.readAsText(t.files[0]); return;
  }
  if (t.tagName === 'SELECT') setTimeout(() => t.blur(), 0);
  const key = t.dataset.input; if (!key) return;
  let v = t.type === 'checkbox' ? t.checked : t.type === 'range' || t.type === 'number' || t.dataset.num ? Number(t.value) : t.value;
  if (t.type === 'number' && (isNaN(v) || v < Number(t.min || 0))) v = Number(t.min || 1);
  applyInput(key, v);
});
document.addEventListener('input', e => { if (e.target.type === 'range') { const b = e.target.nextElementSibling; if (b && b.tagName === 'B') b.textContent = e.target.value + '%'; } });
function nextOrSelf(c) { return nextStage(c) || c; }
window.addEventListener('resize', () => { if (T && !$('#pane-practice').hidden) renderTyping(); });

/* ---------- profile pictures (stored per user, in this browser) ---------- */
const avatarOf = name => loadJSON('avatar.' + name, null);
function avatarHtml(name, cls) {
  const a = avatarOf(name);
  return a ? '<img class="av ' + (cls || '') + '" src="' + a + '" alt="">' : '<span class="av ph ' + (cls || '') + '">' + esc((name[0] || '?').toUpperCase()) + '</span>';
}
function setAvatarFromFile(file) {
  if (!file) return;
  const img = new Image(), url = URL.createObjectURL(file);
  img.onload = () => {
    const c = document.createElement('canvas'); c.width = c.height = 160;
    const s = Math.min(img.width, img.height), sx = (img.width - s) / 2, sy = (img.height - s) / 2;
    c.getContext('2d').drawImage(img, sx, sy, s, s, 0, 0, 160, 160);
    URL.revokeObjectURL(url);
    if (!saveJSON('avatar.' + user, c.toDataURL('image/jpeg', 0.88))) alert('The picture could not be saved in this browser.');
    if (window.onUserSaved) window.onUserSaved();
    renderAll();
  };
  img.onerror = () => { URL.revokeObjectURL(url); alert('That file could not be read as a picture.'); };
  img.src = url;
}

/* ---------- passwords (optional, per user) ---------- */
const hasPw = n => !!loadJSON('pw.' + n, null);
const b64 = buf => btoa(String.fromCharCode.apply(null, Array.from(new Uint8Array(buf))));
const pwOK = () => !!(window.crypto && crypto.subtle);
async function derive(pw, saltB64, iters) {
  const salt = Uint8Array.from(atob(saltB64), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(pw), 'PBKDF2', false, ['deriveBits']);
  return b64(await crypto.subtle.deriveBits({ name: 'PBKDF2', salt, iterations: iters, hash: 'SHA-256' }, key, 256));
}
async function makePw(pw) { const salt = b64(crypto.getRandomValues(new Uint8Array(16))), iters = 150000; return { salt, iters, hash: await derive(pw, salt, iters) }; }
async function checkPw(name, pw) { const r = loadJSON('pw.' + name, null); return !r || (await derive(pw, r.salt, r.iters)) === r.hash; }
function formModal(title, text, labels, okLabel, validate) {
  return new Promise(resolve => {
    $('#fm-title').textContent = title; $('#fm-text').textContent = text; $('#fm-err').textContent = ''; $('#fm-ok').textContent = okLabel || 'OK';
    $('#fm-fields').innerHTML = labels.map(l => '<input type="password" autocomplete="off" placeholder="' + esc(l) + '">').join('');
    const inputs = $$('#fm-fields input'), box = $('#fmodal'); box.hidden = false; inputs[0].focus();
    const done = v => { box.hidden = true; $('#fm-ok').onclick = $('#fm-cancel').onclick = null; box.onkeydown = null; resolve(v); };
    const ok = async () => { const v = inputs.map(i => i.value); const err = validate ? await validate(v) : ''; if (err) { $('#fm-err').textContent = err; return; } done(v); };
    $('#fm-ok').onclick = ok; $('#fm-cancel').onclick = () => done(null);
    box.onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); ok(); } else if (e.key === 'Escape') done(null); };
  });
}
async function askUnlock(name, why) {
  const v = await formModal('Password for ' + name, why || 'Enter the password to open this user.', ['Password'], 'Open', async v => (await checkPw(name, v[0])) ? '' : 'Wrong password.');
  return !!v;
}
async function setPasswordFlow(change) {
  if (!pwOK()) { alert('Passwords need a secure browser context; open the app from the .exe, the installed app or a https page.'); return; }
  if (change && !(await askUnlock(user, 'Enter your current password.'))) return;
  const v = await formModal(change ? 'New password' : 'Set a password', 'If you forget it, it cannot be recovered.', ['New password', 'Repeat password'], 'Save',
    async v => v[0].length < 4 ? 'Use at least 4 characters.' : v[0] !== v[1] ? 'The two passwords do not match.' : '');
  if (!v) return;
  saveJSON('pw.' + user, await makePw(v[0])); renderAll();
}
async function removePasswordFlow() {
  if (!(await askUnlock(user, 'Enter your current password to remove it.'))) return;
  localStorage.removeItem(LS + 'pw.' + user); renderAll();
}

/* ---------- picker / start ---------- */
function showPicker() {
  $('#app').hidden = true; $('#picker').hidden = false;
  const last = loadJSON('last', '');
  $('#plist').innerHTML = profiles.length ? profiles.map(n => '<button class="user' + (n === last ? ' last' : '') + '" data-user="' + esc(n) + '">' + avatarHtml(n) + '<span>' + esc(n) + '</span>' + (hasPw(n) ? '<span class="lock" title="Password protected">🔒</span>' : '') + '</button>').join('') : '<p class="muted">No users yet. Add your name below to begin.</p>';
}
function enter(name) {
  openUser(name); tab = 'today'; sitting = { wpms: [], typingSecs: 0, lastBreak: 0 };
  $('#picker').hidden = true; $('#app').hidden = false;
  newSession();
  if (window.onUserEntered) window.onUserEntered();
}
document.addEventListener('click', async e => {
  const b = e.target.closest('[data-user]');
  if (b) { const n = b.dataset.user; if (hasPw(n) && !(await askUnlock(n))) return; enter(n); }
  if (e.target.id === 'padduser') { const n = $('#newuser').value.trim(); if (n) { $('#newuser').value = ''; enter(n); } }
});
document.addEventListener('keydown', e => { if (e.target.id === 'newuser' && e.key === 'Enter') $('#padduser').click(); });
showPicker();
if ('serviceWorker' in navigator && location.protocol.startsWith('http')) navigator.serviceWorker.register('sw.js').catch(() => { });
