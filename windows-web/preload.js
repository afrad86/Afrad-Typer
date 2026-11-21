const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('desktop', {
  config: () => ipcRenderer.invoke('config'),
  backup: (name, json) => ipcRenderer.invoke('backup', name, json),
  showBackups: () => ipcRenderer.invoke('showBackups'),
  syncChoose: () => ipcRenderer.invoke('syncChoose'),
  syncUseOneDrive: () => ipcRenderer.invoke('syncUseOneDrive'),
  syncStop: () => ipcRenderer.invoke('syncStop'),
  syncList: () => ipcRenderer.invoke('syncList'),
  syncRead: name => ipcRenderer.invoke('syncRead', name),
  syncWrite: (name, json) => ipcRenderer.invoke('syncWrite', name, json),
  onGuide: cb => ipcRenderer.on('open-guide', () => cb()),
  onWelcome: cb => ipcRenderer.on('open-welcome', () => cb())
});
