const { app, BrowserWindow, screen, ipcMain, dialog, shell } = require('electron');
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

function create() {
  const wa = screen.getPrimaryDisplay().workAreaSize;
  const win = new BrowserWindow({
    width: Math.min(Math.round(wa.width * 0.92), 1700), height: Math.min(Math.round(wa.height * 0.94), 1250),
    minWidth: 760, minHeight: 480, autoHideMenuBar: true, backgroundColor: '#2b2b2b', title: 'Afrad Typer',
    icon: path.join(__dirname, 'icon.png'),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false }
  });
  win.loadFile(path.join(__dirname, 'index.html'));
}
app.whenReady().then(create);
app.on('window-all-closed', () => app.quit());
