# Afrad Typer (personal macOS typing app)

[![Download Afrad Typer](https://img.shields.io/badge/Download-Afrad%20Typer%20for%20Mac-orange?style=for-the-badge&logo=apple)](https://github.com/afrad86/Afrad-Typer/raw/main/release/Afrad-Typer.zip)

Click the button, unzip, and drag "Afrad Typer" into Applications. (If you are not signed in to GitHub and the repo is private, sign in first.)

## Build on your Mac
1. Open Terminal and `cd` into this folder.
2. Make sure Swift is installed: `xcode-select --install` (skip if already installed).
3. Run `./build.sh`
4. Drag `Afrad Typer.app` into Applications.

## First launch
The app is unsigned. Right-click it, choose Open, then confirm.
If macOS still blocks it: `xattr -cr /Applications/Afrad Typer.app`

## Office Mac
Copy `Afrad Typer.zip` over (AirDrop, USB, cloud drive), unzip, drag into Applications.
On the old Mac use Progress > Export backup, on the new one Progress > Import backup to carry your history.
If the office Mac blocks unsigned apps, copy this whole folder there and run `./build.sh` on it instead.

## Data location
~/Library/Application Support/TypingPractice/store.json


## Taking Afrad Typer to another Mac (portable)

1. Run `./build.sh` once. It creates `Afrad Typer.zip` (a universal app for Apple Silicon and Intel, macOS 12 or newer).
2. Copy `Afrad Typer.zip` to the other Mac with a USB stick, AirDrop, iCloud Drive or email. Double-click it to unzip and drag `Afrad Typer.app` into Applications.
3. First launch on that Mac: right-click the app, choose Open, then Open again (it is not notarised). If macOS still refuses, run `xattr -cr "/Applications/Afrad Typer.app"` in Terminal.
4. Your history stays on each Mac. To bring it across: Progress tab, Export backup on one Mac, then Import on the other (do it while signed in as the same user name). Backups merge, so nothing is duplicated.

Advanced stages are a separate optional track (Advanced tab). Each stage lesson is 200 words; finish 30 lessons, and at least 90% of your latest 30 must hit the stage speed at 98%+ accuracy to unlock the next stage, over as many days as you need.

## iCloud sync between Macs

On the "Who is practising?" screen, turn on "Sync my progress between Macs with iCloud Drive" on both Macs (same user names). Data then lives in iCloud Drive/Afrad Typer, and each Mac merges new sessions, passages and stage progress when the app opens or becomes active. Resetting history or deleting a passage is also synced. macOS may ask permission to access iCloud Drive the first time. Turning sync off copies the data back to the Mac.

## Getting the app on another Mac (e.g. the office)

No developer tools needed. The built app is stored in the repo as `release/Afrad-Typer.zip` (works on Apple Silicon and Intel).

    git clone https://github.com/afrad86/Afrad-Typer.git

(or on the GitHub page: Code > Download ZIP). Unzip `release/Afrad-Typer.zip`, drag "Afrad Typer" into Applications and open it. If macOS says it cannot verify the app, right-click it > Open > Open once (or run `xattr -dr com.apple.quarantine "/Applications/Afrad Typer.app"`).

To update: on your own Mac run `./build.sh`, then `git add -A && git commit -m "update" && git push`. At the office, `git pull` and unzip again. Practice data lives in each Mac's own user folder (or iCloud Drive if sync is on), not in the repo.
