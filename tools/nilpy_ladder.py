#!/usr/bin/env python3
"""Compile every file of the NilPy third-party corpora and rank what stops them.

The campaign's instrument: it answers "how far up the ladder are we, and what is
the biggest wall" for webencodings / html5lib / tinycss2
(feature-nilpy-thirdparty-libraries-as-targets).

WHY THIS IS A SCRIPT AND NOT A SHELL LOOP. It was a shell loop, and the loop
passed only the scanned file's OWN package directory on -Fu. `tinycss2/bytes.py`
does `from webencodings import ...` -- an ordinary cross-package import -- which
then failed and was recorded as a compiler wall. That single row was the largest
entry in the table and it ranked a non-existent compiler bug as the top lever,
including a Track A ticket filed on the strength of it
(bug-t-the-ladder-scan-passes-only-one-root-so-cross-package-imports-read-as-walls).

A measurement artefact that survives is worse than a missing measurement: it is
actionable and wrong, so it does not merely fail to inform, it dispatches work.
Hence a checked-in tool with the path rule written down, rather than a command
somebody retypes.

THE PATH RULE. For each fetched corpus two directories go on -Fu:

  library_candidates/<name>/            so `import webencodings` finds the package
  library_candidates/<name>/<name>/     so a sibling `from .constants import X`
                                        and a bare `import constants` resolve

That is what CPython's sys.path gives you for a source checkout, and a
cross-package import is ordinary Python rather than an edge case.

Usage:
  tools/nilpy_ladder.py              # compile count + ranked wall table
  tools/nilpy_ladder.py --files      # add the per-file first error
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAND = os.path.join(ROOT, "library_candidates")
PXX = os.path.join(ROOT, "stable_linux_amd64", "default", "pinned")

# The corpora this ladder tracks. Detected rather than hardcoded, but only the
# flat `<name>/<name>/__init__.py` layout counts -- that is what makes a fetched
# tree a Python package we can put on the path. reportlab (src/reportlab/...) is
# an oracle for a different probe, not a rung, and is excluded by this test.
def corpora():
    out = []
    if not os.path.isdir(CAND):
        return out
    for name in sorted(os.listdir(CAND)):
        pkg = os.path.join(CAND, name, name)
        if os.path.isfile(os.path.join(pkg, "__init__.py")):
            out.append((name, os.path.join(CAND, name), pkg))
    return out


def sources(pkg):
    """Every .py under a package except its own test suite."""
    found = []
    for dirpath, dirnames, filenames in os.walk(pkg):
        dirnames[:] = [d for d in dirnames if d not in ("tests", "test")]
        for fn in sorted(filenames):
            if fn.endswith(".py"):
                found.append(os.path.join(dirpath, fn))
    return sorted(found)


ERR = re.compile(r"error: (.*)")
# Collapse the varying part of a message so the table ranks CAUSES, not sites:
# `no unit named constants and no shim mimic_constants` and the same for
# `_utils` are one wall with two victims, and reporting them apart is how a
# long tail hides a big row.
NORM = [
    (re.compile(r"import: no unit named (\S+) and no shim \S+"), r"missing module: \1"),
    (re.compile(r"undefined variable \((\S+)\)"), r"undefined variable (\1)"),
]


def normalise(msg):
    for pat, rep in NORM:
        m = pat.search(msg)
        if m:
            return pat.sub(rep, m.group(0))
    return msg.strip()[:70]


def pin_provenance():
    """Identity of the compiler this run measured, read off disk.

    A ladder result is only interpretable against the pin that produced it, and
    three runs on 2026-08-19 were spent measuring ground that could not contain
    the fix they were looking for. Reading this here rather than being told it
    removes the coordination step, which is where every one of those errors was.
    """
    md5 = base = "?"
    try:
        import hashlib
        h = hashlib.md5()
        with open(PXX, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        md5 = h.hexdigest()
    except OSError:
        pass
    log = os.path.join(ROOT, "stable_linux_amd64", "default", "pin.log")
    try:
        with open(log) as fh:
            last = [ln for ln in fh if ln.strip()][-1]
        base = last.split()[-1]          # trailing field is the pin base commit
    except (OSError, IndexError):
        pass
    return md5, base


def require_ancestor(fix, base):
    """Refuse to run when the pin cannot contain the commit being measured.

    Deliberately a REFUSAL and not a warning: a caveat on a forty-minute run is
    a log line, and the whole point is a check that can stop the thing it
    checks.
    """
    import subprocess
    try:
        rc = subprocess.call(["git", "merge-base", "--is-ancestor", fix, base],
                             cwd=ROOT,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        print("--require-fix: git unavailable; refusing rather than guessing")
        return False
    if rc != 0:
        print("--require-fix %s: NOT an ancestor of pin base %s" % (fix, base))
        print("  the pinned compiler predates that commit, so this run cannot")
        print("  measure it. Refusing to start. Re-pin, or drop --require-fix.")
        return False
    return True


def main():
    show_files = "--files" in sys.argv
    fix = None
    for a in sys.argv[1:]:
        if a.startswith("--require-fix="):
            fix = a.split("=", 1)[1]
    md5, base = pin_provenance()
    if fix and not require_ancestor(fix, base):
        return 2
    corp = corpora()
    if not corp:
        print("no corpora fetched — run: tools/install_lib_candidates.sh webencodings html5lib tinycss2")
        return 77

    incl = []
    for _name, dist, pkg in corp:
        incl += ["-Fu" + dist, "-Fu" + pkg]
    incl.append("-Fu" + os.path.join(ROOT, "lib", "rtl"))

    print("roots: " + ", ".join(os.path.relpath(d, ROOT) for _n, d, _p in corp))
    # Provenance in the artifact, so a result read next week carries the pin it
    # was taken on instead of relying on whoever reads it to remember.
    print("pin:   md5 %s  base %s" % (md5, base))
    ok = 0
    total = 0
    walls = {}
    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        for name, _dist, pkg in corp:
            for src in sources(pkg):
                total += 1
                out = os.path.join(tmp, "o%d" % total)
                # errors="replace": a compiler diagnostic can echo a source
                # line, and these corpora are full of non-UTF-8 bytes (html5lib
                # ships latin-1 test data and entity tables). Decoding strictly
                # made the whole scan die on one file.
                r = subprocess.run([PXX] + incl + [src, out],
                                   capture_output=True, text=True,
                                   errors="replace")
                rel = os.path.relpath(src, CAND)
                if r.returncode == 0:
                    ok += 1
                    rows.append((rel, "OK"))
                    continue
                m = ERR.search(r.stdout + r.stderr)
                wall = normalise(m.group(1)) if m else "(no error line)"
                walls[wall] = walls.get(wall, 0) + 1
                rows.append((rel, wall))

    print("\ncompile: %d/%d" % (ok, total))
    print("\nfirst wall, ranked:")
    for wall, n in sorted(walls.items(), key=lambda kv: (-kv[1], kv[0])):
        print("  %3d  %s" % (n, wall))
    if show_files:
        print("\nper file:")
        for rel, wall in rows:
            print("  %-52s %s" % (rel, wall))
    return 0


if __name__ == "__main__":
    sys.exit(main())
