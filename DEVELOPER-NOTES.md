# Developer notes (for rebuilding everything on a fresh computer)

Everything needed is in this repository: the Mac source (`Sources/`, `Package.swift`, `Resources/`, `build.sh`), the Windows/web version (`windows-web/`), the finished downloads (`release/`) and the logo files.

## Get the project back
    git clone https://github.com/afrad86/Afrad-Typer.git
    cd Afrad-Typer

## Mac app
    xcode-select --install     # once, if Swift is not installed
    ./build.sh                 # makes "Afrad Typer.app" and "Afrad Typer.zip", and copies the zip to release/

## Windows app (installer)
On a computer with Node.js and NSIS (makensis): `cd windows-web && npm install && npm run dist`, then copy
`windows-web/dist/Afrad-Typer-Setup.exe` to `release/Afrad-Typer-Setup.exe`.

## Publish a new version
    ./build.sh
    git add -A
    git commit -m "describe the change"
    gh release create v$(cat VERSION) release/Afrad-Typer.zip release/Afrad-Typer-Setup.exe --title "Afrad Touch Typing $(cat VERSION)" --notes "describe the change"
    git push
(One-time setup for `gh`: `brew install gh`, then `gh auth login`.)

## Not stored in the repository (on purpose)
- Practice progress and settings: kept on each computer (Mac: ~/Library/Application Support/TypingPractice, or iCloud Drive/Afrad Typer when sync is on). Use Progress > Export backup, or turn on iCloud sync, to keep a safe copy.
- Your GitHub sign-in: after a fresh install, sign in again (personal access token) the first time you push.

(c) 2026 Hassan Afrad. All rights reserved.

## Releases
Every release needs a NEW version number in VERSION and windows-web/package.json (kept equal), or Help > Check for Updates will not offer it.
- Big files (Mac zip, Windows installer) are NOT stored in the repository. They are attached to a GitHub Release named v<version>
  (`gh release create v<version> release/Afrad-Typer.zip release/Afrad-Typer-Setup.exe`), created BEFORE `git push`
  so the files exist when the apps see the new version.json.
- build.sh runs tools/make_release_info.py, which writes release/version.json (download links) and release/web-manifest.json
  (fingerprints of the Windows app's own pages).
- Windows small updates: if only the pages change (index.html, style.css, *.js except main.js/preload.js, images, fonts),
  installed apps download just those files. If main.js, preload.js, package.json or the Electron version change, raise
  windows-web/SHELL_VERSION to the new version so apps take the full installer instead.
- The Windows installer is built from electron-builder's "win-unpacked" folder with makensis (windows-web/installer.nsi).
