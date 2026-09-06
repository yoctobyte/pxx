#!/usr/bin/env python3
"""Report FPC build artefacts sitting inside source trees, where a stale one
silently poisons every later oracle diff and `git status` says the tree is clean.

WHY THIS IS NOT A HOUSEKEEPING TOOL. A stray `.ppu` is not clutter -- it is an
INSTRUMENT DEFECT with the shape this repo keeps hitting: it does not error, it
answers. The trees it matters in -- `library_candidates/` above all -- are
GITIGNORED, so `git status` reports clean and nothing in the per-fix loop looks
there.

AND THE MECHANISM IS NOT THE ONE EVERYONE ASSUMES, WHICH IS WHY THIS IS WORTH A
TOOL. "A stale .ppu is believed over a changed .pas" is FALSE, measured here:
fpc records the source's timestamp inside the ppu and recompiles on any
mismatch, in either direction --

    ppu recording 2026-08-27, source touched to 2026-08-20 (OLDER)
      -> "File uk.pas is newer than the one used for creating PPU file" and it
         recompiles anyway. The message says newer; the behaviour is
         "not identical, so rebuild".

So a source edit is caught. WHAT IS NOT CAUGHT IS AN OPTION CHANGE, and it is
silent:

    unit uk;  {$ifdef FOO} const K = 1; {$else} const K = 2; {$endif}

    fpc -dFOO t.pas   ; ./t   ->  1        (writes uk.ppu)
    fpc      t.pas    ; ./t   ->  1        (SAME DIRECTORY, ppu reused)
    fpc      t.pas    ; ./t   ->  2        (clean directory)

No error, no warning, no recompile. The ppu carries the DEFINES it was built
with and nothing compares them to the ones you asked for -- so the compile
answers correctly about a configuration you are not in. Every differential
harness that varies flags across rows in one directory has this exposure, and it
is invisible to the source-time check that catches the case people worry about.

Found by frankS, 2026-09-06, after a run of the retry harness reported `fpc=127`
on all nine rows -- command-not-found wearing the shape of a verdict -- and left
sixteen artefacts behind.

They removed their own; seven older ones from an earlier session in the same
checkout remained, including two `.ppu`.

WHERE FPC ACTUALLY PUTS THEM, measured here, three rows, because the rule that
travels ("next to the source") is true in two of the three and the exception is
the one every harness relies on:

    fpc -o/abs/path/p  src/p.pas   ->  binary, .o and .ppu all in /abs/path/
    fpc -op3           src/p.pas   ->  ALL of them in src/  (a RELATIVE -o is
                                       resolved against the SOURCE directory,
                                       not the cwd)
    fpc                src/p.pas   ->  ALL of them in src/

The cwd is not consulted in any row. So an ABSOLUTE `-o` into a scratch
directory already contains the artefacts, which is why `tools/fpc_diff_probe.sh`
has never had this problem, and a relative `-o` gives no protection at all
despite looking like it does. `-FE<dir>` (executable + .o) and `-FU<dir>` (.ppu)
say it explicitly and are what a harness should pass.

REPORT, NEVER A GATE, AND IT DELETES NOTHING. The artefacts in a seat's tree may
belong to a run in progress; only the seat can tell. It prints literal paths so
that whoever owns them can remove them without a glob.
"""
import os
import stat
import subprocess
import sys
import tempfile
import time

# Source trees where a build artefact is always wrong, in this repo's layout.
# `library_candidates/` is third-party source used as an oracle corpus and is
# gitignored, which is exactly why nothing else looks in it.
SCAN = ["library_candidates", "test", "examples", "lib"]

ARTEFACT_EXT = {".ppu": "CARRIES ITS BUILD DEFINES -- reused silently under different flags",
                ".o": "stale object",
                ".a": "stale archive",
                ".s": "left-behind asm",
                ".rsj": "compiler resource string index"}


def is_executable_elf(path):
    try:
        if not (os.stat(path).st_mode & stat.S_IXUSR):
            return False
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def scan(roots):
    """[(path, why, mtime)] -- artefacts under `roots`."""
    out = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for dirpath, _dirs, files in os.walk(root):
            for fn in files:
                p = os.path.join(dirpath, fn)
                ext = os.path.splitext(fn)[1].lower()
                why = ARTEFACT_EXT.get(ext)
                if why is None and is_executable_elf(p):
                    why = "compiled binary"
                if why is None:
                    continue
                try:
                    out.append((p, why, os.path.getmtime(p)))
                except OSError:
                    pass
    return sorted(out, key=lambda r: r[2])


def self_check():
    """The guard must be shown to fire. Plants one of each kind and one file
    that must NOT be reported -- a .pas, which is what these trees are for."""
    work = tempfile.mkdtemp(prefix="strayfpc.")
    sub = os.path.join(work, "tests", "test")
    os.makedirs(sub)
    for fn in ("u1.ppu", "u1.o", "p.pas"):
        open(os.path.join(sub, fn), "w").close()
    binp = os.path.join(sub, "p")
    with open(binp, "wb") as f:
        f.write(b"\x7fELF" + b"\0" * 60)
    os.chmod(binp, 0o755)

    found = {os.path.basename(p) for p, _w, _m in scan([work])}
    for must in ("u1.ppu", "u1.o", "p"):
        if must not in found:
            print("SELF-CHECK FAILED: planted %s and the scan did not report it"
                  % must)
            return 3
    if "p.pas" in found:
        print("SELF-CHECK FAILED: reported a .pas -- this scan would flag the "
              "corpus itself, which is as empty as flagging nothing.")
        return 3
    print("self-check OK: .ppu, .o and an ELF binary reported; the .pas beside "
          "them is not. Scratch left at %s" % work)
    return 0


def main(argv):
    if "--self-check" in argv:
        return self_check()

    roots = [a for a in argv[1:] if not a.startswith("-")] or SCAN
    rows = scan(roots)
    if not rows:
        print("no fpc build artefacts under: %s" % ", ".join(roots))
        print("(a clean answer here is only as wide as those roots -- it says "
              "nothing about a scratch tree elsewhere.)")
        return 0

    now = time.time()
    print("%d fpc build artefact(s) sitting in source trees:\n" % len(rows))
    for p, why, mt in rows:
        age = (now - mt) / 3600.0
        print("  %s\n      %s  --  %s, %.1fh old"
              % (p, time.strftime("%Y-%m-%d %H:%M", time.localtime(mt)),
                 why, age))
    ppus = [p for p, w, _m in rows if p.endswith(".ppu")]
    print("\n%d of these are .ppu, the kind that changes a later answer without "
          "erroring:\na source edit IS caught (fpc records the source time and"
          " rebuilds on any mismatch),\nbut a DIFFERENT -d/-M/-F flag is not --"
          " the ppu is reused and answers correctly\nabout the configuration it"
          " was built in." % len(ppus))
    print("They may belong to a run in progress -- ONLY THE SEAT THAT MADE THEM "
          "KNOWS. This tool\ndeletes nothing and prints literal paths so"
          " whoever owns them can remove them without a glob.")
    print("\nTo stop making them: pass fpc an ABSOLUTE -o into a scratch"
          " directory, or -FE<dir> -FU<dir>.\nA RELATIVE -o resolves against the"
          " SOURCE directory and protects nothing.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
