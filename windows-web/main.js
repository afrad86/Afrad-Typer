const { app, BrowserWindow, screen, ipcMain, dialog, shell, Menu } = require('electron');
const https = require('https');
const os = require('os');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const cfgFile = () => path.join(app.getPath('userData'), 'desktop-config.json');
function readCfg() { try { return JSON.parse(fs.readFileSync(cfgFile(), 'utf8')); } catch (e) { return {}; } }
function writeCfg(c) { try { fs.writeFileSync(cfgFile(), JSON.stringify(c)); } catch (e) { /* ignore */ } }
const safe = n => String(n).replace(/[^\w\- ]/g, '_').trim() || 'user';
const backupsDir = () => path.join(app.getPath('documents'), 'Afrad Typer', 'Backups');
const oneDrive = () => process.env.OneDrive || process.env.OneDriveConsumer || process.env.OneDriveCommercial || '';
const syncDir = () => { const c = readCfg(); return c.syncFolder && fs.existsSync(c.syncFolder) ? c.syncFolder : null; };

function useFolder(base) {
  const dir = path.join(base, 'Afrad Typer Sync');
  try { fs.mkdirSync(dir, { recursive: true }); } catch (e) { return null; }
  const c = readCfg(); c.syncFolder = dir; writeCfg(c); return dir;
}

ipcMain.handle('config', () => ({ syncFolder: syncDir(), oneDrive: oneDrive() && fs.existsSync(oneDrive()) ? oneDrive() : '', backupsFolder: backupsDir() }));

// Weekly backup: one file per user, written at most once every 7 days, newest 8 kept.
ipcMain.handle('backup', (e, name, json) => {
  try {
    const dir = backupsDir(); fs.mkdirSync(dir, { recursive: true });
    const prefix = safe(name) + '-';
    const files = fs.readdirSync(dir).filter(f => f.startsWith(prefix) && f.endsWith('.json')).sort();
    if (files.length) {
      const age = Date.now() - fs.statSync(path.join(dir, files[files.length - 1])).mtimeMs;
      if (age < 7 * 86400000) return false;
    }
    const d = new Date(), day = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
    const file = path.join(dir, prefix + day + '.json');
    fs.writeFileSync(file, json);
    const all = files.filter(f => path.join(dir, f) !== file).concat([path.basename(file)]);
    all.slice(0, Math.max(0, all.length - 8)).forEach(f => { try { fs.unlinkSync(path.join(dir, f)); } catch (x) { /* ignore */ } });
    return true;
  } catch (err) { return false; }
});
ipcMain.handle('showBackups', async () => { const dir = backupsDir(); fs.mkdirSync(dir, { recursive: true }); await shell.openPath(dir); return true; });

// Sync through any folder that your cloud service keeps in step (OneDrive, Dropbox, Google Drive...).
ipcMain.handle('syncChoose', async () => {
  const r = await dialog.showOpenDialog({ title: 'Choose a folder that syncs between your computers', properties: ['openDirectory', 'createDirectory'] });
  if (r.canceled || !r.filePaths[0]) return null;
  return useFolder(r.filePaths[0]);
});
ipcMain.handle('syncUseOneDrive', () => (oneDrive() && fs.existsSync(oneDrive()) ? useFolder(oneDrive()) : null));
ipcMain.handle('syncStop', () => { const c = readCfg(); delete c.syncFolder; writeCfg(c); return true; });
ipcMain.handle('syncList', () => {
  const d = syncDir(); if (!d) return [];
  try { return fs.readdirSync(d).filter(f => f.startsWith('AfradTyper-') && f.endsWith('.json')).map(f => ({ file: f, text: fs.readFileSync(path.join(d, f), 'utf8') })); } catch (e) { return []; }
});
ipcMain.handle('syncRead', (e, name) => { const d = syncDir(); if (!d) return null; try { return fs.readFileSync(path.join(d, 'AfradTyper-' + safe(name) + '.json'), 'utf8'); } catch (x) { return null; } });
ipcMain.handle('syncWrite', (e, name, json) => {
  const d = syncDir(); if (!d) return false;
  try { const f = path.join(d, 'AfradTyper-' + safe(name) + '.json'); fs.writeFileSync(f + '.tmp', json); fs.renameSync(f + '.tmp', f); return true; } catch (x) { return false; }
});


/* ---------- updates: Help > Check for updates ---------- */
const BASE = 'https://raw.githubusercontent.com/afrad86/Afrad-Typer/main/release/';
const newer = (a, b) => { const x = String(a).split('.').map(Number), y = String(b).split('.').map(Number); for (let i = 0; i < Math.max(x.length, y.length); i++) { const p = x[i] || 0, q = y[i] || 0; if (p !== q) return p > q; } return false; };
function fetchTo(url, dest, hops) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'AfradTyper' } }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && (hops || 0) < 5) { res.resume(); return resolve(fetchTo(new URL(res.headers.location, url).toString(), dest, (hops || 0) + 1)); }
      if (res.statusCode !== 200) { res.resume(); return reject(new Error('HTTP ' + res.statusCode)); }
      if (dest) { const f = fs.createWriteStream(dest); res.pipe(f); f.on('finish', () => f.close(() => resolve(dest))); f.on('error', reject); }
      else { let s = ''; res.setEncoding('utf8'); res.on('data', d => { s += d; }); res.on('end', () => resolve(s)); }
    }).on('error', reject).setTimeout(30000, function () { this.destroy(new Error('timeout')); });
  });
}
let pendingVersion = null, lastPeek = 0, menuWin = null;
/* Quiet check on start and when the window is focused again (at most every 30 minutes): relabels the Help item. */
async function peekUpdate(win) {
  if (Date.now() - lastPeek < 30 * 60 * 1000) return;
  lastPeek = Date.now();
  try {
    const info = JSON.parse(await fetchTo(BASE + 'version.json?t=' + Date.now()));
    const p = info.version && newer(info.version, app.getVersion()) ? info.version : null;
    if (p !== pendingVersion) { pendingVersion = p; buildMenu(win); }
  } catch (e) { /* offline: keep the plain label */ }
}
async function checkUpdates(win) {
  const box = o => dialog.showMessageBox(win, Object.assign({ type: 'info', buttons: ['OK'] }, o));
  let info;
  try { info = JSON.parse(await fetchTo(BASE + 'version.json?t=' + Date.now())); } catch (e) { return box({ message: 'Could not check for updates', detail: 'Check your internet connection and try again.' }); }
  const cur = app.getVersion();
  const np = info.version && newer(info.version, cur) ? info.version : null;
  if (np !== pendingVersion) { pendingVersion = np; buildMenu(win); }
  if (!info.version || !newer(info.version, cur)) return box({ message: "You're up to date", detail: 'Afrad Typer ' + cur + ' is the latest version.' });
  const r = await box({ type: 'question', buttons: ['Install and restart', 'Later'], defaultId: 0, cancelId: 1, message: 'Update available: ' + info.version, detail: 'You have ' + cur + '. The app will download the update, replace itself and reopen. Your progress is kept.' });
  if (r.response !== 0) return;
  const target = process.env.PORTABLE_EXECUTABLE_FILE;
  if (!target) return box({ message: 'This copy cannot update itself', detail: 'Download the latest Afrad-Typer-Windows.exe from the project page instead.' });
  const tmp = path.join(os.tmpdir(), 'AfradTyper-update.exe');
  try {
    win.setTitle('Afrad Typer — downloading update…');
    await fetchTo(info.windows || (BASE + 'Afrad-Typer-Windows.exe'), tmp);
    if (fs.statSync(tmp).size < 20 * 1024 * 1024) throw new Error('too small');
  } catch (e) { win.setTitle('Afrad Typer'); return box({ type: 'error', message: 'Update failed', detail: 'The download did not finish. Check your internet connection and try again.' }); }
  const bat = path.join(os.tmpdir(), 'afrad-update.bat');
  fs.writeFileSync(bat, ['@echo off', 'set N=0', ':retry', 'timeout /t 1 /nobreak >nul', 'move /Y "' + tmp + '" "' + target + '" >nul 2>&1', 'if errorlevel 1 (', '  set /a N+=1', '  if %N% lss 40 goto retry', '  exit /b 1', ')', 'start "" "' + target + '"', '(goto) 2>nul & del "%~f0"'].join('\r\n'));
  spawn('cmd.exe', ['/c', bat], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
  app.quit();
}
function buildMenu(win) {
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    { role: 'editMenu' },
    { label: 'Help', submenu: [
      { label: 'Getting started', click: () => win.webContents.send('open-welcome') },
      { label: 'How it works', click: () => win.webContents.send('open-guide') },
      { type: 'separator' },
      { label: pendingVersion ? 'Update available v' + pendingVersion + '…' : 'Check for updates…', click: () => checkUpdates(win) },
      { label: 'About Afrad Typer', click: () => dialog.showMessageBox(win, { type: 'info', message: 'Afrad Typer', detail: 'Version ' + app.getVersion() + '\nCopyright © 2026 Hassan Afrad.' }) }
    ] }
  ]));
}

function create() {
  const wa = screen.getPrimaryDisplay().workAreaSize;
  const win = new BrowserWindow({
    width: Math.min(Math.round(wa.width * 0.92), 1700), height: Math.min(Math.round(wa.height * 0.94), 1250),
    minWidth: 760, minHeight: 480, autoHideMenuBar: false, backgroundColor: '#2b2b2b', title: 'Afrad Typer',
    icon: path.join(__dirname, 'icon.png'),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false }
  });
  buildMenu(win);
  win.webContents.setWindowOpenHandler(({ url }) => { if (/^https:\/\//.test(url)) shell.openExternal(url); return { action: 'deny' }; });
  win.webContents.once('did-finish-load', () => peekUpdate(win));
  win.on('focus', () => peekUpdate(win));
  win.loadFile(path.join(__dirname, 'index.html'));
}
app.whenReady().then(create);
app.on('window-all-closed', () => app.quit());
