const { app, BrowserWindow, screen } = require('electron');
const path = require('path');
function create() {
  const wa = screen.getPrimaryDisplay().workAreaSize;
  const win = new BrowserWindow({
    width: Math.min(Math.round(wa.width * 0.92), 1700), height: Math.min(Math.round(wa.height * 0.94), 1250),
    minWidth: 760, minHeight: 480, autoHideMenuBar: true, backgroundColor: '#2b2b2b', title: 'Afrad Typer',
    icon: path.join(__dirname, 'icon.png')
  });
  win.loadFile(path.join(__dirname, 'index.html'));
}
app.whenReady().then(create);
app.on('window-all-closed', () => app.quit());
