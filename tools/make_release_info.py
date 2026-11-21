#!/usr/bin/env python3
"""Writes release/version.json and release/web-manifest.json for the update checks.
Big files (the Mac zip and the Windows installer) are downloaded from the GitHub release of this version;
small updates of the Windows app's own pages are downloaded file by file and checked against these fingerprints."""
import hashlib, json, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "afrad86/Afrad-Typer"
WEB_FILES = ["index.html", "style.css", "data.js", "books.js", "core.js", "ui.js", "desktop.js",
             "logo-96.png", "logo-256.png", "icon.png", "fonts/Pacifico.woff2"]
version = open(os.path.join(ROOT, "VERSION")).read().strip()
shell = open(os.path.join(ROOT, "windows-web", "SHELL_VERSION")).read().strip()
files = {}
for f in WEB_FILES:
    with open(os.path.join(ROOT, "windows-web", f), "rb") as fh:
        files[f] = hashlib.sha256(fh.read()).hexdigest()
os.makedirs(os.path.join(ROOT, "release"), exist_ok=True)
manifest = {"version": version, "shell": shell, "base": f"https://raw.githubusercontent.com/{REPO}/main/windows-web/", "files": files}
with open(os.path.join(ROOT, "release", "web-manifest.json"), "w") as fh:
    json.dump(manifest, fh, indent=1)
dl = f"https://github.com/{REPO}/releases/download/v{version}"
info = {"version": version, "shell": shell, "mac": f"{dl}/Afrad-Typer.zip", "windows": f"{dl}/Afrad-Typer-Setup.exe",
        "web": f"https://raw.githubusercontent.com/{REPO}/main/release/web-manifest.json"}
with open(os.path.join(ROOT, "release", "version.json"), "w") as fh:
    json.dump(info, fh)
    fh.write("\n")
print("release/version.json and release/web-manifest.json written for", version)
