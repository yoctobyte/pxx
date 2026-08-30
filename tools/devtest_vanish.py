#!/usr/bin/env python3
"""Devtest: the vanished-identifier scan catches a synthesised silent clobber.

WHY THIS EXISTS: `tools/vanish.py` claims to detect another lane's work being
deleted with no conflict and no failing test. That claim had no positive
control — and a detector with no positive control is the same class of claim as
a green from one shape: it reports nothing, and you cannot tell "clean" from
"broken". So this synthesises the real 2026-08-30 near-miss in a scratch repo
and asserts the detector fires on it.

THE SECOND ASSERTION IS THE IMPORTANT ONE. It asserts that the tidier,
declaration-shaped detector — the one that greps removed `function`/`procedure`
lines — MISSES this same clobber. `CUnitOfPascalProgram` is a global `var`, so
the decl-shaped version is blind to it while being ~10x quieter and looking
more correct. That is a trap with a gravitational pull: it is exactly the
"improvement" a future cleanup pass will make. When somebody makes vanish.py
quieter, this is the test that goes red and says why.

Scratch repo only: no compiles, no network, no writes outside a tempdir.

Run: tools/devtest_vanish.py   (exit 0 = pass)
"""
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "vanish", os.path.join(HERE, "vanish.py"))
vanish = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vanish)

fails = []


def check(cond, what, detail=""):
    print("  %-4s %-52s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def git(repo, *args):
    subprocess.run(["git"] + list(args), cwd=repo, check=True,
                   capture_output=True, text=True)


def commit(repo, subject):
    git(repo, "add", "-A")
    git(repo, "-c", "user.email=t@pxx", "-c", "user.name=devtest",
        "commit", "-q", "-m", subject)
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo,
                          capture_output=True, text=True).stdout.strip()


# The shape of the real near-miss, reduced to its essentials: a shared file, a
# global var another lane adds to it, and a park-and-restore that silently
# takes the var back out. Faithful in the one detail that decides the test —
# the clobbered thing is a VAR, not a routine.
BASE = """\
{ defs.inc — shared compiler declarations }
var
  CProgramMode : Boolean;
  CTokenIndex  : LongInt;

procedure ResetCState;
begin
  CProgramMode := False;
end;
"""

WITH_A_WORK = """\
{ defs.inc — shared compiler declarations }
var
  CProgramMode : Boolean;
  CTokenIndex  : LongInt;
  CUnitOfPascalProgram : Boolean; { the C source in front of us is a UNIT }

procedure ResetCState;
begin
  CProgramMode := False;
  CUnitOfPascalProgram := False;
end;
"""


def build_repo(path):
    """Three commits: a base, lane A adding a global, lane S restoring a stale
    whole-file copy over it. The third commit is the clobber and conflicts with
    nothing."""
    os.makedirs(os.path.join(path, "compiler"))
    git(path, "init", "-q", "-b", "master")
    f = os.path.join(path, "compiler", "defs.inc")

    with open(f, "w") as h:
        h.write(BASE)
    commit(path, "chore(A): seed the shared declarations")

    with open(f, "w") as h:
        h.write(WITH_A_WORK)
    sha_a = commit(path, "feat(A): a C unit that is a Pascal program needs a flag")

    # frankS restores its parked whole-file copy. Byte-for-byte the pre-A
    # content: no conflict, no diagnostic, a clean well-formed commit.
    with open(f, "w") as h:
        h.write(BASE)
    sha_s = commit(path, "feat(S): restore the parked include work")
    return sha_a, sha_s


def decl_shaped_scan(repo, paths):
    """The tempting implementation, implemented faithfully so the test can show
    it losing. Removed `function`/`procedure` declarations only."""
    out = vanish.git("log", "--format=@@C %H %s", "-p", "--unified=0",
                     "HEAD", "--", *paths, cwd=repo)
    decl = re.compile(r"^-\s*(function|procedure)\s+([A-Za-z_]\w*)", re.I)
    found = set()
    for line in out.splitlines():
        m = decl.match(line)
        if m:
            found.add(m.group(2))
    return found


def main():
    tmp = tempfile.mkdtemp(prefix="devtest_vanish_")
    try:
        repo = os.path.join(tmp, "repo")
        os.makedirs(repo)
        sha_a, sha_s = build_repo(repo)
        vanish._repo = repo
        paths = ["compiler/"]

        print("positive control — the synthesised clobber")
        cand = vanish.scan_diffs(["HEAD"], paths)
        rows = {}
        for sha, (subj, names) in cand.items():
            gone = names - vanish.still_present(sha, names, paths)
            if gone:
                rows[sha] = (subj, gone)

        check(sha_s in rows, "the clobbering commit is flagged",
              "" if sha_s in rows else "NOT FLAGGED — the detector is broken")
        gone = rows.get(sha_s, ("", set()))[1]
        check("CUnitOfPascalProgram" in gone,
              "the clobbered global var is named", ",".join(sorted(gone)) or "-")

        # git's own conflict machinery is the thing this exists to work around;
        # assert it really is silent here rather than assuming it.
        merged = subprocess.run(["git", "log", "--format=%H", "HEAD"],
                                cwd=repo, capture_output=True, text=True)
        check(merged.returncode == 0 and len(merged.stdout.split()) == 3,
              "the clobber landed as a clean linear commit")

        print()
        print("the trap — the decl-shaped detector must LOSE this case")
        decl_found = decl_shaped_scan(repo, paths)
        check("CUnitOfPascalProgram" not in decl_found,
              "decl-shaped scan misses the clobbered var",
              "found=%s" % (sorted(decl_found) or "nothing"))
        check("CUnitOfPascalProgram" in gone and
              "CUnitOfPascalProgram" not in decl_found,
              "identifier-diffing strictly beats decl-shapes here",
              "this is why vanish.py must not be 'cleaned up'")

        print()
        print("negative control — a MOVE must not be flagged")
        # Same identifier, different file: a refactor that relocates code is
        # not a clobber, and the tree-presence filter is what tells them apart.
        with open(os.path.join(repo, "compiler", "defs.inc"), "w") as h:
            h.write(BASE)
        with open(os.path.join(repo, "compiler", "cdefs.inc"), "w") as h:
            h.write("var\n  CUnitOfPascalProgram : Boolean;\n")
        with open(os.path.join(repo, "compiler", "defs.inc"), "w") as h:
            h.write(WITH_A_WORK.replace(
                "  CUnitOfPascalProgram : Boolean; "
                "{ the C source in front of us is a UNIT }\n", ""))
        sha_move = commit(repo, "refactor(C): move the C-only flag to cdefs")
        cand2 = vanish.scan_diffs([sha_move + "^.." + sha_move], paths)
        moved_gone = set()
        for sha, (subj, names) in cand2.items():
            moved_gone |= names - vanish.still_present(sha, names, paths)
        check("CUnitOfPascalProgram" not in moved_gone,
              "a relocated identifier is not reported",
              "gone=%s" % (sorted(moved_gone) or "nothing"))

        print()
        if fails:
            print("FAIL: %d check(s) failed: %s" % (len(fails), "; ".join(fails)))
            return 1
        print("all checks green")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
