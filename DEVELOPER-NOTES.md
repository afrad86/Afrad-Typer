# Developer notes (for rebuilding everything on a fresh computer)

Everything needed is in this repository: the Mac source (`Sources/`, `Package.swift`, `Resources/`, `build.sh`), the Windows/web version (`windows-web/`), the finished downloads (`release/`) and the logo files.

## Get the project back
    git clone https://github.com/afrad86/Afrad-Typer.git
    cd Afrad-Typer

## Mac app
    xcode-select --install     # once, if Swift is not installed
    ./build.sh                 # makes "Afrad Typer.app" and "Afrad Typer.zip", and copies the zip to release/

## Windows app (.exe)
Run the GitHub workflow: repository > Actions > "Build Windows app" > Run workflow, then download the file it produces and save it as `release/Afrad-Typer-Windows.exe`.
(The workflow file lives in `.github/workflows/windows.yml`; a copy is kept in `windows-web/build-windows.yml`.)
Or on any computer with Node.js: `cd windows-web && npm install && npm run dist`.

## Publish a new version
    ./build.sh
    git add -A
    git commit -m "describe the change"
    git push

## Not stored in the repository (on purpose)
- Practice progress and settings: kept on each computer (Mac: ~/Library/Application Support/TypingPractice, or iCloud Drive/Afrad Typer when sync is on). Use Progress > Export backup, or turn on iCloud sync, to keep a safe copy.
- Your GitHub sign-in: after a fresh install, sign in again (personal access token) the first time you push.

(c) 2026 Hassan Afrad. All rights reserved.
