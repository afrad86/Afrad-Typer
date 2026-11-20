# Afrad Typer for Windows (and any browser)

The same typing practice as the Mac app, as a web app: Lessons (words, common words, trigrams, tetragrams, custom), automatic weak-spot practice, Timed, Passages, Symbols, the Advanced stage ladder (45 to 110 WPM), progress charts, weak-spot report, Library, Focus mode, separate users and backup export/import.

## Use it now (no install)
Open `windows-web/index.html` in Edge or Chrome. Or turn on GitHub Pages (repo Settings > Pages > Deploy from branch `main`, folder `/ (root)`), then open https://afrad86.github.io/Afrad-Typer/ . Note: Pages on a private repo needs a paid GitHub plan; on a public repo it is free.

**Install as an app:** open the page in Edge or Chrome, then use the install icon in the address bar ("Install Afrad Typer"). It gets its own window and Start menu icon and works offline.

## Windows .exe
Copy `windows-web/build-windows.yml` to `.github/workflows/windows.yml` in the repo (`mkdir -p .github/workflows && cp windows-web/build-windows.yml .github/workflows/windows.yml`), push, then the GitHub workflow "Build Windows app" builds a portable `Afrad-Typer-Windows.exe` (Actions tab > Build Windows app > Run workflow, then download the artifact). Windows may show a SmartScreen warning because the file is unsigned: More info > Run anyway.

## Where is my progress?
In this browser/app on this computer, per user. Use Progress > Export backup to copy it elsewhere, and Import backup to merge it on another computer.

## Differences from the Mac app
Not included yet: Daily Practice tab, iCloud sync (use export/import), weekly auto-backup.
