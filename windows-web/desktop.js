'use strict';
/* Windows app only: automatic weekly backup and folder sync. Does nothing in a normal browser. */
const DESK = window.desktop || null;
let syncFolder = null, deskCfg = {}, pushTimer = null, syncing = false, lastSync = null;

function emptyData() { return { settings: Object.assign({}, DEF), history: [], passages: [], resetAt: 0 }; }

/* Pull every user found in the sync folder into this computer (new users are created). */
async function syncPullAll() {
  if (!DESK || !syncFolder) return false;
  let changed = false;
  const files = await DESK.syncList();
  for (const f of files) {
    try {
      const j = JSON.parse(f.text), name = j.user, d = j.data || {};
      if (!name) continue;
      if (user === name) { if (mergeInto(data, d)) { changed = true; save(); } }
      else {
        const mine = loadJSON('data.' + name, null) || emptyData();
        mine.settings = Object.assign({}, DEF, mine.settings || {}); mine.history = mine.history || []; mine.passages = mine.passages || [];
        const isNew = !profiles.includes(name);
        if (mergeInto(mine, d) || isNew) { saveJSON('data.' + name, mine); changed = true; }
        if (isNew) { profiles.push(name); saveJSON('profiles', profiles); }
      }
      if (j.avatar && !loadJSON('avatar.' + name, null)) { saveJSON('avatar.' + name, j.avatar); changed = true; }
    } catch (e) { /* skip unreadable file */ }
  }
  lastSync = new Date();
  return changed;
}

async function syncPush() {
  if (!DESK || !syncFolder || !user || syncing) return;
  syncing = true;
  try {
    const remote = await DESK.syncRead(user);
    if (remote) { try { const j = JSON.parse(remote); if (mergeInto(data, j.data || {})) save(); } catch (e) { /* ignore */ } }
    await DESK.syncWrite(user, JSON.stringify(exportPayload()));
    lastSync = new Date();
  } finally { syncing = false; }
}

window.onUserSaved = function () {
  if (!DESK || !syncFolder) return;
  clearTimeout(pushTimer); pushTimer = setTimeout(syncPush, 600);
};
window.onUserEntered = async function () {
  if (!DESK) return;
  // weekly backup, only when there is something to save
  if (data.history.length) DESK.backup(user, JSON.stringify(exportPayload()));
  if (syncFolder) { if (await syncPullAll()) renderAll(); await syncPush(); }
};
window.addEventListener('focus', async () => {
  if (!DESK || !syncFolder || !user || (new Date() - (lastSync || 0)) < 20000) return;
  if (await syncPullAll()) renderAll();
});

window.renderDesktopBox = function () {
  const box = $('#deskbox'); if (!box) return;
  if (!DESK) { box.className = 'deskbox'; box.innerHTML = '<span class="muted">Automatic weekly backups and sync between computers are available in the Windows app (the .exe).</span>'; return; }
  let h = '<b>Automatic backup</b><div class="muted">On. A backup of every user is saved once a week in Documents\\Afrad Typer\\Backups (newest 8 kept).</div><div class="row"><button id="showbk">Show backups</button></div>';
  h += '<b>Sync between Windows computers</b>';
  if (syncFolder) {
    h += '<div class="muted">On. Progress, pictures and passages merge automatically through:<br>' + esc(syncFolder) + (lastSync ? '<br>Last synced ' + lastSync.toLocaleTimeString() : '') + '</div><div class="row"><button id="syncnow">Sync now</button><button id="syncoff">Stop syncing</button></div>';
  } else {
    h += '<div class="muted">Pick a folder that your cloud service keeps in step (OneDrive, Dropbox, Google Drive…). Do the same on the other computer and your progress follows you. Passwords are not copied between computers.</div><div class="row">' + (deskCfg.oneDrive ? '<button class="primary" id="syncone">Use OneDrive</button>' : '') + '<button id="syncpick">Choose a folder…</button></div>';
  }
  box.className = 'deskbox'; box.innerHTML = h;
};

async function afterSyncChange(folder) {
  syncFolder = folder; deskCfg = await DESK.config();
  if (folder) { await syncPullAll(); await syncPush(); }
  renderAll();
}
document.addEventListener('click', async e => {
  if (!DESK) return;
  const id = e.target.id;
  if (id === 'showbk') DESK.showBackups();
  else if (id === 'syncpick') { const f = await DESK.syncChoose(); if (f) afterSyncChange(f); }
  else if (id === 'syncone') { const f = await DESK.syncUseOneDrive(); if (f) afterSyncChange(f); }
  else if (id === 'syncoff') { await DESK.syncStop(); afterSyncChange(null); }
  else if (id === 'syncnow') { await syncPullAll(); await syncPush(); renderAll(); }
});

(async function init() {
  if (!DESK) return;
  deskCfg = await DESK.config(); syncFolder = deskCfg.syncFolder;
  if (syncFolder && await syncPullAll()) { if (!user) showPicker(); }
})();

if (DESK && DESK.onGuide) DESK.onGuide(() => { guideOpen = 'level'; tab = 'guide'; renderAll(); });
if (DESK && DESK.onWelcome) DESK.onWelcome(() => showWelcome());
