#!/usr/bin/env python3
"""Cross-reference ticket slugs cited in SOURCE COMMENTS against the ticket tree.

WHY THIS EXISTS (2026-09-06). Four seats filed or worked three tickets on one
mechanism in a day, and the answer to the row that was wrong was sitting in
`compiler/paslexer.inc`, in a comment that NAMED the ticket lineage the reader
was standing in: "likewise inc/dec/halt/exit/... dispatched in ParseStatementAST".
Nothing indexes those citations, so a ticket's own code neighbourhood is the one
place nobody looks before filing.

Two directions, and they have DIFFERENT error properties -- say which you ran:

  --cites <slug>   FORWARD. Every source line citing this ticket. EXACT: it can
                   only match slugs that exist, so it has no false positives and
                   its only failure is a citation spelled differently in source.

  --dangling       INVERSE. Slug-shaped strings in source that resolve to no
                   ticket. INEXACT by construction -- see APERTURE below. A dangle
                   is not automatically a defect: it may be a rename, a ticket
                   that was planned and never filed, or prose that only looks
                   like a slug.

APERTURE, stated because a count here is easy to over-read:
  * A comment WRAPS and the slug is split across two lines. Recovered by
    rejoining with the next line's first word; a slug wrapped twice is not.
  * Slugs contain UPPERCASE segments (decide-...-the-LOAD-be-pruned-at-O0), so a
    lowercase-only character class TRUNCATES them and reports a dangle that is
    really a resolving citation. This cost the tool's own author a wrong number
    before the pattern was widened -- the scanner did not error, it answered
    about a shorter string.
  * `*_devtest.py` and files under a `test/` path use slug-shaped strings as
    FIXTURES. Excluded from --dangling, counted by --stats.
"""
import argparse, collections, pathlib, re, sys

# Uppercase is deliberate: real slugs carry it (`...-the-LOAD-be-pruned-at-O0`).
SLUG_RE = re.compile(r'\b(?:bug|feature|refactor|task|decide|regression)-[A-Za-z0-9-]{10,}')
SRC_SUFFIX = (".pas", ".inc", ".py", ".sh", ".c", ".h")
SRC_DIRS = ("compiler", "lib", "tools")


def known_slugs(root):
    prog = root / "devdocs" / "progress"
    return {f.stem for d in prog.iterdir() if d.is_dir() for f in d.glob("*.md")}


def source_files(root):
    for sub in SRC_DIRS:
        d = root / sub
        if not d.is_dir():
            continue
        for f in sorted(d.rglob("*")):
            if f.is_file() and f.suffix in SRC_SUFFIX:
                yield f


def is_fixture(f):
    return "_devtest" in f.name or "/test/" in str(f).replace("\\", "/")


def scan(root, slugs):
    """-> (resolving: slug -> [(path,line,text)], dangling: slug -> [(path,line,text)], nwrap, nfixture)"""
    hits = collections.defaultdict(list)
    dangling = collections.defaultdict(list)
    nwrap = nfix = 0
    for f in source_files(root):
        try:
            lines = f.read_text(errors="replace").splitlines()
        except OSError:
            continue
        rel = str(f.relative_to(root))
        for i, ln in enumerate(lines):
            for m in SLUG_RE.finditer(ln):
                s = m.group().rstrip("-")
                if s in slugs:
                    hits[s].append((rel, i + 1, ln.strip()))
                    continue
                # A wrapped comment: the slug runs to the end of the line and the
                # next line continues it. Rejoin and retry before calling it a dangle.
                joined = None
                if not ln[m.end():].strip(" }*/#") and i + 1 < len(lines):
                    nxt = lines[i + 1].strip().lstrip("{*#/ ")
                    word = nxt.split()[0].strip(".,;}*") if nxt else ""
                    for cand in (s + "-" + word, s + word):
                        if cand in slugs:
                            joined = cand
                            break
                if joined:
                    nwrap += 1
                    hits[joined].append((rel, i + 1, ln.strip()))
                    continue
                if is_fixture(f):
                    nfix += 1
                    continue
                dangling[s].append((rel, i + 1, ln.strip()))
    return hits, dangling, nwrap, nfix


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=".", help="repo root")
    ap.add_argument("--cites", metavar="SLUG",
                    help="list every source line citing SLUG (exact; no false positives)")
    ap.add_argument("--dangling", action="store_true",
                    help="slug-shaped strings in source resolving to no ticket (inexact -- read the aperture)")
    ap.add_argument("--stats", action="store_true", help="corpus sizes and both exclusion counts")
    ap.add_argument("--self-check", action="store_true",
                    help="positive control: assert the scanner finds a citation it MUST find")
    a = ap.parse_args()
    root = pathlib.Path(a.root).resolve()
    slugs = known_slugs(root)
    hits, dangling, nwrap, nfix = scan(root, slugs)

    if a.self_check:
        # The control is drawn from the population the tool is about: a real
        # citation, in a real compiler source comment, of a ticket that exists.
        # If the scanner ever stops finding THIS, it is not narrowing gracefully.
        ctl = "bug-p-nine-intrinsic-spellings-are-hard-keywords-so-they-cannot-be-user-names"
        ok = ctl in hits and any(h[0].endswith("paslexer.inc") for h in hits[ctl])
        upper = [s for s in hits if any(c.isupper() for c in s)]
        print(f"control citation of {ctl} in paslexer.inc: {'FOUND' if ok else 'MISSING'}")
        print(f"slugs with UPPERCASE segments resolved: {len(upper)}"
              + (f"  e.g. {sorted(upper)[0]}" if upper else ""))
        if not ok:
            print("SELF-CHECK FAILED -- the scanner cannot see its own motivating case")
            return 1
        if not upper:
            print("SELF-CHECK FAILED -- no uppercase slug resolved; the character "
                  "class has narrowed back and is silently truncating")
            return 1
        print("self-check OK")
        return 0

    if a.cites:
        rows = hits.get(a.cites)
        if not rows:
            print(f"no source comment cites {a.cites}")
            print("NOTE: absence here is about the SPELLING, not about the subject -- "
                  "code discussing this defect without naming the slug is invisible to it.")
            return 0
        print(f"{len(rows)} source citation(s) of {a.cites}:")
        for path, line, text in rows:
            print(f"  {path}:{line}")
            print(f"      {text[:150]}")
        return 0

    if a.dangling:
        print(f"{len(dangling)} distinct slug-shaped string(s) in source resolve to no ticket "
              f"({sum(len(v) for v in dangling.values())} citations).")
        print("A dangle is one of: a RENAME, a ticket PLANNED AND NEVER FILED, work "
              "delivered under another name, or prose that merely looks like a slug. "
              "Read it before changing it.")
        for s, rows in sorted(dangling.items(), key=lambda kv: -len(kv[1])):
            print(f"  {len(rows)}x {s}")
            for path, line, _ in rows[:2]:
                print(f"        {path}:{line}")
        return 1 if dangling else 0

    tot = sum(len(v) for v in hits.values())
    print(f"source files scanned: {sum(1 for _ in source_files(root))}")
    print(f"tickets in the tree: {len(slugs)}")
    print(f"resolving citations: {tot} across {len(hits)} distinct ticket(s)")
    print(f"  recovered from a comment line-WRAP: {nwrap}")
    print(f"  devtest/fixture citations excluded from --dangling: {nfix}")
    print(f"dangling: {sum(len(v) for v in dangling.values())} citations, "
          f"{len(dangling)} distinct")
    print("\nMost-cited tickets (the code's own hot spots):")
    for s, rows in sorted(hits.items(), key=lambda kv: -len(kv[1]))[:10]:
        print(f"  {len(rows):3d}x {s}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
