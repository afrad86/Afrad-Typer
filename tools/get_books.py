#!/usr/bin/env python3
"""Downloads simple public-domain story books from Project Gutenberg, cleans them for typing,
splits them into short parts, and writes:
    Resources/books.json        (used by the Mac app)
    windows-web/books.js        (used by the Windows app)
Run once:  python3 tools/get_books.py
"""
import json, os, re, sys, unicodedata, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# id on gutenberg.org, title, author, level, how many ~200 word parts to keep (None = all)
BOOKS = [
    (21,    "Aesop's Fables",                    "Aesop",          "Easy",   12),
    (14838, "The Tale of Peter Rabbit",          "Beatrix Potter", "Easy",   None),
    (55,    "The Wonderful Wizard of Oz",        "L. Frank Baum",  "Easy",   14),
    (11,    "Alice's Adventures in Wonderland",  "Lewis Carroll",  "Medium", 14),
    (16,    "Peter Pan",                         "J. M. Barrie",   "Medium", 14),
    (2591,  "Grimm's Fairy Tales",               "Brothers Grimm", "Medium", 14),
]
TARGET, MAXW = 200, 260

# small repairs for lines the source files lose (drop-capital letters, a short block of names)
FIXES = [
    ("WOLF, meeting with a Lamb astray", "A WOLF, meeting with a Lamb astray"),
    ("their names were -", "their names were Flopsy, Mopsy, Cotton-tail, and Peter."),
]

# where the story really begins (everything before it - contents, dedications, notices - is dropped)
STARTS = {
    21:    [r"A LION was awakened from sleep by a Mouse"],
    14838: [r"Once upon a time there were four little Rabbits"],
    55:    [r"Dorothy lived in the midst of the great Kansas prairies"],
    11:    [r"Alice was beginning to get very tired"],
    16:    [r"All children, except one, grow up"],
    2591:  [r"A certain king had a beautiful garden"],
}


def download(gid):
    import time
    cache = os.path.join(ROOT, "tools", "cache", f"{gid}.txt")
    if os.path.exists(cache):
        with open(cache, encoding="utf-8") as f:
            return f.read()
    urls = (f"https://www.gutenberg.org/cache/epub/{gid}/pg{gid}.txt",
            f"https://www.gutenberg.org/ebooks/{gid}.txt.utf-8",
            f"https://www.gutenberg.org/files/{gid}/{gid}-0.txt",
            f"https://gutenberg.pglaf.org/cache/epub/{gid}/pg{gid}.txt")
    headers = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
               "Accept": "text/plain,*/*"}
    err = None
    for attempt in range(3):
        for url in urls:
            try:
                req = urllib.request.Request(url, headers=headers)
                with urllib.request.urlopen(req, timeout=60) as r:
                    txt = r.read().decode("utf-8", "replace")
                os.makedirs(os.path.dirname(cache), exist_ok=True)
                with open(cache, "w", encoding="utf-8") as f:
                    f.write(txt)
                return txt
            except Exception as e:
                err = e
        time.sleep(4 * (attempt + 1))
    raise RuntimeError(f"could not download book {gid}: {err}")


def strip_gutenberg(t):
    a = re.search(r"\*\*\* ?START OF (THE|THIS) PROJECT GUTENBERG EBOOK.*?\*\*\*", t, re.S)
    b = re.search(r"\*\*\* ?END OF (THE|THIS) PROJECT GUTENBERG EBOOK", t)
    if a: t = t[a.end():]
    if b: t = t[:t.find(b.group(0))] if b.group(0) in t else t
    return t


def clean(t):
    t = t.replace("\r", "")
    t = re.sub(r"\[Illustration[^\]]*\]", " ", t, flags=re.S)
    t = re.sub(r"\[Footnote[^\]]*\]", " ", t, flags=re.S)
    t = re.sub(r"_([^_\n]+)_", r"\1", t)
    for a, b in (("‘", "'"), ("’", "'"), ("“", '"'), ("”", '"'), ("—", " - "), ("–", "-"),
                 ("…", "..."), (" ", " "), ("æ", "ae"), ("œ", "oe")):
        t = t.replace(a, b)
    t = unicodedata.normalize("NFKD", t)
    t = "".join(ch for ch in t if ord(ch) < 128)
    t = re.sub(r"--+", " - ", t)
    return t


def cut_start(t, gid):
    for pat in STARTS.get(gid, []):
        ms = list(re.finditer(pat, t))
        if ms:
            # the last match of a heading marker would skip the story, so take the first match that is followed by real prose
            for m in ms:
                after = t[m.start(): m.start() + 900]
                if len(re.findall(r"[.!?]", after)) >= 2:
                    return t[m.start():]
    print("  (warning: start marker not found, front matter may remain)", end="")
    return t


def paragraphs(t):
    out = []
    for blk in re.split(r"\n\s*\n", t):
        lines = [l.strip() for l in blk.split("\n") if l.strip()]
        if not lines: continue
        # a contents list or heading block: several short lines, most without end punctuation
        if len(lines) >= 3 and sum(1 for l in lines if not re.search(r"[.!?\"']$", l)) / len(lines) > 0.6 and sum(len(l.split()) for l in lines) / len(lines) < 9:
            continue
        p = re.sub(r"\s+", " ", " ".join(lines)).strip()
        letters = [c for c in p if c.isalpha()]
        if letters and sum(c.isupper() for c in letters) / len(letters) > 0.8: continue
        if len(p.split()) < 8 and not re.search(r"[.!?\"']$", p): continue
        if re.match(r"^(chapter|contents|illustrations?|by |translated|produced|\*)", p, re.I) and len(p.split()) < 14: continue
        out.append(p)
    return out


def sentences_of(p):
    """Splits a very long paragraph into pieces of about TARGET words at sentence ends."""
    if len(p.split()) <= MAXW: return [p]
    sents = re.split(r"(?<=[.!?]) +|(?<=[.!?][\"']) +", p)
    pieces, cur = [], []
    for sn in sents:
        cur.append(sn)
        if sum(len(x.split()) for x in cur) >= TARGET:
            pieces.append(" ".join(cur)); cur = []
    if cur:
        if pieces and sum(len(x.split()) for x in cur) < 60: pieces[-1] += " " + " ".join(cur)
        else: pieces.append(" ".join(cur))
    return pieces


def split_parts(paras):
    parts, cur, n = [], [], 0
    flat = []
    for p in paras: flat.extend(sentences_of(p))
    for p in flat:
        w = len(p.split())
        if cur and n + w > MAXW and n >= 120:
            parts.append(" ".join(cur)); cur, n = [], 0
        cur.append(p); n += w
        if n >= TARGET and re.search(r"[.!?\"']$", p):
            parts.append(" ".join(cur)); cur, n = [], 0
    if cur and n >= 60: parts.append(" ".join(cur))
    elif cur and parts: parts[-1] += " " + " ".join(cur)
    return parts


def label(text, i):
    w = text.split()[:5]
    return f"Part {i} – “{' '.join(w)}…”"


def build():
    books = []
    for gid, title, author, level, keep in BOOKS:
        print(f"{title} ... ", end="", flush=True)
        try:
            raw = download(gid)
        except Exception as e:
            print("SKIPPED:", e); continue
        paras = paragraphs(cut_start(clean(strip_gutenberg(raw)), gid))
        for i, pp in enumerate(paras):
            for bad, good in FIXES:
                pp = pp.replace(bad, good)
            paras[i] = pp
        parts = split_parts(paras)
        if keep: parts = parts[:keep]
        if len(parts) < 3:
            print("SKIPPED (too little text found)"); continue
        books.append({"id": re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-"), "title": title, "author": author,
                      "level": level, "parts": [{"title": label(p, i + 1), "text": p} for i, p in enumerate(parts)]})
        print(f"{len(parts)} parts")
    return books


if __name__ == "__main__":
    books = build()
    if not books:
        sys.exit("No books were downloaded. Check your internet connection and try again.")
    os.makedirs(os.path.join(ROOT, "Resources"), exist_ok=True)
    with open(os.path.join(ROOT, "Resources", "books.json"), "w", encoding="utf-8") as f:
        json.dump(books, f, ensure_ascii=True, indent=1)
    with open(os.path.join(ROOT, "windows-web", "books.js"), "w", encoding="utf-8") as f:
        f.write("window.BOOKS=" + json.dumps(books, ensure_ascii=True) + ";\n")
    print(f"Done: {len(books)} books written to Resources/books.json and windows-web/books.js")
