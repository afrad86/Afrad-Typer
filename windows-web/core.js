'use strict';
/* Afrad Typer (web) - core: data, storage, lesson building, statistics, stage rules.
   Mirrors the Mac app's logic so both versions behave alike. */

const D = window.DATA;
const TARGETS = [45, 50, 55, 60, 65, 70, 75, 80, 83, 86, 89, 92, 95, 98, 101, 104, 107, 110];
const SCOPES = [50, 100, 200, 300, 500, 1000, 2000, 3000];

const $ = (s, r) => (r || document).querySelector(s);
const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const rnd = n => Math.floor(Math.random() * n);
const pick = a => a[rnd(a.length)];
function shuffled(a) { const b = a.slice(); for (let i = b.length - 1; i > 0; i--) { const j = rnd(i + 1); [b[i], b[j]] = [b[j], b[i]]; } return b; }
function dayKey(d) { d = d || new Date(); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); }

/* ---------- settings ---------- */
const DEF = {
  mode: 'lessons', source: 'Words', scope: 200, generator: 'Combination', itemsPerLesson: 10, repetition: 5,
  mixedOrder: true, autoFocus: true, customWords: '', capitalPercent: 0, punctuationPercent: 0,
  minWPM: 30, minAccuracy: 95, timedSeconds: 60, wordPool: 1000, wordCount: 30, linesShown: 4,
  strictMode: false, textSize: 28, hideAhead: 0, sounds: true, focusMode: false, paceWPM: 0,
  breakReminder: true, selectedPassage: 'starter0', lessonByKey: {},
  stageSelected: 45, stageCleared: 0, stageMinLessons: 30, stageMinWords: 200,
  stageAutoMix: true, stageCapitals: 5, stagePunctuation: 5, warmupEnabled: true, warmupDay: ''
};

/* ---------- storage (per user, in this browser) ---------- */
const LS = 'afradTyper.';
function loadJSON(k, def) { try { const v = localStorage.getItem(LS + k); return v ? JSON.parse(v) : def; } catch (e) { return def; } }
function saveJSON(k, v) { try { localStorage.setItem(LS + k, JSON.stringify(v)); return true; } catch (e) { return false; } }
let profiles = loadJSON('profiles', []);
let user = null;
let data = null;

function openUser(name) {
  user = name;
  const d = loadJSON('data.' + name, null) || {};
  data = { settings: Object.assign({}, DEF, d.settings || {}), history: d.history || [], passages: d.passages || [], resetAt: d.resetAt || 0 };
  data.settings.lessonByKey = data.settings.lessonByKey || {};
  if (!profiles.includes(name)) { profiles.push(name); saveJSON('profiles', profiles); }
  saveJSON('last', name);
  save();
}
function save() {
  if (!user) return;
  if (data.history.length > 1200) data.history = data.history.slice(-1200);
  saveJSON('data.' + user, data);
}
const S_ = () => data.settings;

/* ---------- word lists ---------- */
const WORDS = D.words;
function deriveNgrams(n) {
  const w = {};
  WORDS.forEach((word, rank) => {
    if (word.length < n) return;
    const wt = 1 / (rank + 1);
    for (let i = 0; i <= word.length - n; i++) { const g = word.slice(i, i + n); w[g] = (w[g] || 0) + wt; }
  });
  return Object.entries(w).sort((a, b) => b[1] === a[1] ? (a[0] < b[0] ? -1 : 1) : b[1] - a[1]).slice(0, 1000).map(e => e[0]);
}
function extend(site, more) { const seen = new Set(site); const out = site.slice(); more.forEach(x => { if (!seen.has(x)) { seen.add(x); out.push(x); } }); return out; }
const DRILL = {
  Words: extend(D.site.words, WORDS),
  Trigrams: extend(D.site.trigrams, deriveNgrams(3)),
  Tetragrams: extend(D.site.tetragrams, deriveNgrams(4))
};
DRILL['Common words'] = DRILL.Words.filter(w => w.length >= 4);

/* ---------- lessons ---------- */
function seededRng(str) {
  let h = 1779033703 ^ str.length;
  for (let i = 0; i < str.length; i++) { h = Math.imul(h ^ str.charCodeAt(i), 3432918353); h = (h << 13) | (h >>> 19); }
  let a = h >>> 0;
  return function () { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
function lessonItems(s) {
  if (s.source === 'Custom') return s.customWords.split(/\s+/).filter(Boolean);
  let list = (DRILL[s.source] || DRILL.Words).slice(0, s.scope);
  if (s.mixedOrder) {
    const r = seededRng(s.source + '|' + s.scope);
    for (let i = list.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [list[i], list[j]] = [list[j], list[i]]; }
  }
  return list;
}
function lessonText(chunk, gen, repeats) {
  const r = Math.max(1, repeats);
  if (gen === 'Repetition') return chunk.flatMap(w => Array(r).fill(w)).join(' ');
  let out = []; for (let i = 0; i < r; i++) out = out.concat(chunk); return out.join(' ');
}
function decorate(text, caps, punct) {
  if (caps <= 0 && punct <= 0) return text;
  const marks = ['.', ',', ';', ':', '!', '?', '-'];
  return text.split(' ').map(t => {
    if (caps > 0 && rnd(100) < caps && /^[a-z]/.test(t)) t = t[0].toUpperCase() + t.slice(1);
    if (punct > 0 && rnd(100) < punct) t += pick(marks);
    return t;
  }).join(' ');
}
function pool(size, minLen) { return WORDS.slice(0, Math.max(size, 100)).filter(w => w.length >= (minLen || 1)); }
function plainWords(size, count) { const p = pool(size, 3); return Array.from({ length: count || 30 }, () => pick(p)).join(' '); }
function timedText(size, count) {
  const p = pool(size); const out = []; let last = '';
  while (out.length < (count || 350)) { const w = pick(p); if (w === last) continue; out.push(w); last = w; }
  return out.join(' ');
}
function symbolsText(size, count) {
  const words = pool(size, 3); const w = () => pick(words); const n = (a, b) => a + rnd(b - a + 1); const t = [];
  for (let i = 0; i < (count || 36); i++) {
    switch (rnd(14)) {
      case 0: t.push('' + n(1, 9999)); break;
      case 1: t.push(n(1, 99) + '.' + n(1, 99)); break;
      case 2: t.push('$' + n(1, 999)); break;
      case 3: t.push(n(1, 100) + '%'); break;
      case 4: t.push(n(1, 28) + '/' + n(1, 12)); break;
      case 5: t.push(n(1, 12) + ':' + String(n(0, 59)).padStart(2, '0')); break;
      case 6: t.push('(' + w() + ')'); break;
      case 7: t.push('"' + w() + '"'); break;
      case 8: t.push('#' + w()); break;
      case 9: t.push('@' + w()); break;
      case 10: { const a = n(1, 50), b = n(1, 50); t.push(a + '+' + b + '=' + (a + b)); break; }
      case 11: t.push(w() + '&' + w()); break;
      case 12: t.push(w() + '/' + w()); break;
      default: t.push(w() + '-' + n(1, 99));
    }
  }
  return t.join(' ');
}

/* ---------- statistics (last N sessions) ---------- */
const isCounted = r => !r.warm && !r.replay;
function recentRecords(n) { return data.history.filter(isCounted).slice(-n); }
function mergeStat(map, k, st) {
  const m = map[k] || (map[k] = { attempts: 0, misses: 0, totalMs: 0, timedCount: 0 });
  m.attempts += st.attempts; m.misses += st.misses; m.totalMs += st.totalMs; m.timedCount += st.timedCount;
}
function agg(field, n) { const out = {}; recentRecords(n).forEach(r => { const o = r[field] || {}; Object.keys(o).forEach(k => mergeStat(out, k, o[k])); }); return out; }
const keyStats = n => agg('keys', n), pairStats = n => agg('pairs', n), wordStats = n => agg('words', n);
const avgMs = st => st.timedCount > 0 ? st.totalMs / st.timedCount : 0;
const missRate = st => st.attempts > 0 ? st.misses / st.attempts : 0;
function baselineMs(n) { let t = 0, c = 0; const ks = keyStats(n); Object.values(ks).forEach(s => { t += s.totalMs; c += s.timedCount; }); return c > 0 ? t / c : 0; }

function weakScore(st) { if (st.attempts < 5) return 0; const slow = avgMs(st) > 0 ? clamp((avgMs(st) - 250) / 750, 0, 1) : 0; return missRate(st) * 3 + slow * 0.5; }
function weakKeys(stats, limit) {
  return Object.entries(stats).filter(([k, v]) => k.length === 1 && /\p{L}/u.test(k) && v.attempts >= 5)
    .map(([k, v]) => [k, weakScore(v)]).filter(e => e[1] > 0.05).sort((a, b) => b[1] - a[1]).slice(0, limit || 5).map(e => e[0]);
}
function pairScore(st) { if (st.attempts < 3) return 0; const slow = avgMs(st) > 0 ? clamp((avgMs(st) - 180) / 600, 0, 1) : 0; return missRate(st) * 3 + slow; }
function slowPairs(stats, limit) { return Object.entries(stats).map(([k, v]) => [k, pairScore(v)]).filter(e => e[1] > 0.05).sort((a, b) => b[1] - a[1]).slice(0, limit || 6).map(e => e[0]); }
function wordScore(st, base) { if (st.attempts < 2 || st.timedCount < 3) return 0; const rel = base > 0 ? Math.max(0, avgMs(st) / base - 1) : 0; return rel + missRate(st) * 3; }
function slowWords(stats, base, limit) { return Object.entries(stats).map(([k, v]) => [k, wordScore(v, base)]).filter(e => e[1] > 0.1).sort((a, b) => b[1] - a[1]).slice(0, limit || 8).map(e => e[0]); }

function weakKeyText(stats, size, count) {
  const keys = weakKeys(stats), words = pool(size, 3);
  if (!keys.length) return { text: plainWords(size, count), keys: [] };
  const weight = {}; keys.forEach((k, i) => { weight[k] = keys.length - i; });
  const top = words.map(w => { let s = 0; for (const ch of w) s += weight[ch] || 0; return [w, s / Math.sqrt(w.length)]; })
    .filter(e => e[1] > 0).sort((a, b) => b[1] - a[1]).slice(0, 80).map(e => e[0]);
  if (!top.length) return { text: plainWords(size, count), keys };
  return { text: Array.from({ length: count }, () => pick(top)).join(' '), keys };
}
function pairText(stats, size, count) {
  const pairs = slowPairs(stats);
  if (!pairs.length) return { text: plainWords(size, count), pairs: [] };
  const weight = {}; pairs.forEach((p, i) => { weight[p] = pairs.length - i; });
  const top = pool(size, 3).map(w => { let s = 0; for (let i = 0; i < w.length - 1; i++) s += weight[w.slice(i, i + 2)] || 0; return [w, s]; })
    .filter(e => e[1] > 0).sort((a, b) => b[1] - a[1]).slice(0, 60).map(e => e[0]);
  if (!top.length) return { text: plainWords(size, count), pairs };
  const tokens = []; pairs.forEach(p => tokens.push(p, p, p));
  for (let i = 0; i < Math.max(8, count - pairs.length * 3); i++) tokens.push(pick(top));
  return { text: tokens.join(' '), pairs };
}
function slowWordText(stats, base, size, count) {
  const words = slowWords(stats, base);
  if (!words.length) { const longer = pool(size, 6); return { text: Array.from({ length: count }, () => pick(longer)).join(' '), words: [] }; }
  const tokens = []; let last = '';
  for (let i = 0; i < Math.max(1, Math.floor(count / words.length)); i++) {
    const round = shuffled(words);
    if (round.length > 1 && round[0] === last) { const t = round[0]; round[0] = round[round.length - 1]; round[round.length - 1] = t; }
    tokens.push(...round); last = round[round.length - 1];
  }
  return { text: tokens.join(' '), words };
}
/* Trigram/tetragram lessons: extra practice is pieces of the same size, never whole words. */
function ngramBoost(n, list, keys, pairs, words, count) {
  const poolArr = [], seen = new Set();
  const add = g => { if (g.length === n && !seen.has(g)) { seen.add(g); poolArr.push(g); } };
  list.slice(0, 1000).forEach(g => { keys.forEach(k => { if (g.includes(k)) add(g); }); pairs.forEach(p => { if (g.includes(p)) add(g); }); });
  words.forEach(w => { for (let i = 0; i + n <= w.length; i++) add(w.slice(i, i + n)); });
  if (!poolArr.length) return [];
  const out = []; let last = '', bag = [];
  while (out.length < Math.max(3, count)) {
    if (!bag.length) bag = shuffled(poolArr);
    const g = bag.pop();
    if (g === last && poolArr.length > 1) continue;
    out.push(g); last = g;
  }
  return out;
}
function interleave(base, extra) {
  if (!extra.length || !base.length) return base.concat(extra);
  const out = [], step = base.length / extra.length; let next = step / 2, e = 0;
  base.forEach((t, i) => { out.push(t); while (e < extra.length && i + 1 >= next) { out.push(extra[e]); e++; next += step; } });
  while (e < extra.length) { out.push(extra[e]); e++; }
  return out;
}
/* Built-in assessment: finds weak keys, slow pairs and slow words in the last 20 sessions. */
function adaptiveBoost(s, baseWords, ngram) {
  const win = 20, ks = keyStats(win), ps = pairStats(win), ws = wordStats(win), base = baselineMs(win);
  const keys = weakKeys(ks, 4), pairs = slowPairs(ps, 4), words = slowWords(ws, base, 6);
  const groups = (keys.length ? 1 : 0) + (pairs.length ? 1 : 0) + (words.length ? 1 : 0);
  if (!groups) return null;
  const flagged = keys.length + pairs.length + words.length;
  const recent = data.history.filter(isCounted).slice(-10);
  const recentAcc = recent.length ? recent.reduce((a, r) => a + r.accuracy, 0) / recent.length : 100;
  let share = 0.15 + 0.04 * flagged; if (recentAcc < 94) share += 0.10; share = Math.min(0.6, share);
  const total = Math.max(9, Math.round(baseWords * share / (1 - share)));
  const each = Math.max(3, Math.floor(total / groups));
  const sm = [];
  if (keys.length) sm.push('keys ' + keys.map(k => k.toUpperCase()).join(' '));
  if (pairs.length) sm.push('pairs ' + pairs.map(k => k.toUpperCase()).join(' '));
  if (words.length) sm.push('words ' + words.join(' '));
  const pct = Math.round(share * 100);
  const summary = sm.join('  ·  ') + '  (' + pct + '% extra, from your last ' + win + ' sessions)';
  if (ngram) {
    const tokens = ngramBoost(ngram, ngram === 3 ? DRILL.Trigrams : DRILL.Tetragrams, keys, pairs, words, total);
    return tokens.length ? { tokens, summary } : null;
  }
  const parts = [];
  if (keys.length) parts.push(weakKeyText(ks, s.wordPool, each).text);
  if (pairs.length) parts.push(pairText(ps, s.wordPool, each).text);
  if (words.length) parts.push(slowWordText(ws, base, s.wordPool, each).text);
  const tokens = shuffled(parts.join(' ').split(' ').filter(Boolean));
  return tokens.length ? { tokens, summary } : null;
}

/* ---------- advanced stages ---------- */
function stageAccuracy(t) { return t <= 85 ? 97 : 96; }
function stageMix(s, t) {
  if (!s.stageAutoMix) return { caps: s.stageCapitals, punct: s.stagePunctuation };
  const p = t < 60 ? 0 : t < 80 ? 3 : t < 95 ? 5 : 8;
  return { caps: p, punct: p };
}
function stageReport(t) {
  const s = S_(), recs = data.history.filter(r => r.stage === t && isCounted(r));
  const win = recs.slice(-s.stageMinLessons);
  const passed = win.filter(r => r.passed).length;
  const need = Math.ceil(s.stageMinLessons * 0.9);
  return {
    attempts: recs.length, window: win.length, passed, need, target: t,
    cleared: win.length >= s.stageMinLessons && passed >= need,
    text: 'Stage ' + t + ' WPM: ' + recs.length + ' lessons finished. In your latest ' + s.stageMinLessons + ', ' + passed + ' passed (you need ' + need + ' of ' + s.stageMinLessons + '). Each lesson is ' + s.stageMinWords + ' words at ' + t + '+ WPM with ' + stageAccuracy(t) + '%+ accuracy.'
  };
}
function nextStage(t) { return TARGETS.find(x => x > t); }

/* ---------- passages ---------- */
function allPassages() {
  const base = D.passages.map((p, i) => ({ id: 'starter' + i, title: p.title, text: p.text, builtin: true }));
  return base.concat(data.passages);
}
function chunkPassage(text, target) {
  const words = text.replace(/\s+/g, ' ').trim().split(' ').filter(Boolean);
  const chunks = []; let cur = '';
  words.forEach(w => {
    if (cur && (cur + ' ' + w).length > target && /[.!?]$/.test(cur)) { chunks.push(cur); cur = w; }
    else if (cur && (cur + ' ' + w).length > target * 1.6) { chunks.push(cur); cur = w; }
    else cur = cur ? cur + ' ' + w : w;
  });
  if (cur) chunks.push(cur);
  return chunks;
}
