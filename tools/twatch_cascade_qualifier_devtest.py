#!/usr/bin/env python3
"""`--status`'s "bad touches NO buildable file" caveat must reach CASCADE lines.

Until 2026-08-31 it did not. The qualifier hung off the regression branch only,
so the calm line carried the defusing sentence and the alarming one did not:

    open regression: test-asm#src:test/hello.pas bad=44ec32358394 (1 in range)
      — bad touches NO buildable file: it is the tested upper bound, not a lead
    open CASCADE: 30 of 30 swept job(s) still red, bad=afc0da53c859 (1 in range)

`afc0da53c859` was the watcher's own tstate publish commit. TWO agents read that
cascade line as a fleet emergency the same night and went to chase the sha; the
regression lines directly above would have told them not to bother.

BOTH ARMS ARE ASSERTED, per the polarity rule in debugging-playbook.md: a guard
stuck on the conservative answer produces more work, which reads as diligence
and so is never reported. So the accept-side case — a genuinely buildable bad
must get NO caveat — matters as much as the reject-side one. A qualifier that
annotated everything would be exactly as useless and much harder to notice.
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import twatch                                              # noqa: E402

FAILS = []


def check(name, cond, detail=""):
    print("  %-4s %s%s" % ("ok" if cond else "FAIL", name,
                           "" if cond else "  <- " + detail))
    if not cond:
        FAILS.append(name)


def git(repo, *args):
    return subprocess.run(("git", "-C", repo) + args, capture_output=True,
                          text=True, check=True).stdout.strip()


def make_repo(tmp):
    """A repo with one docs-only commit and one that touches compiler/."""
    git_dir = os.path.join(tmp, "repo")
    os.makedirs(os.path.join(git_dir, "devdocs", "progress", "tstate"))
    os.makedirs(os.path.join(git_dir, "compiler"))
    subprocess.run(["git", "init", "-q", git_dir], check=True)
    git(git_dir, "config", "user.email", "t@example.invalid")
    git(git_dir, "config", "user.name", "devtest")
    open(os.path.join(git_dir, "README"), "w").write("seed\n")
    git(git_dir, "add", "-A")
    git(git_dir, "commit", "-qm", "seed")
    # docs/tstate only — the watcher's own publish shape
    open(os.path.join(git_dir, "devdocs/progress/tstate/seven.json"), "w"
         ).write("{}\n")
    git(git_dir, "add", "-A")
    git(git_dir, "commit", "-qm", "tstate(seven): publish")
    docs_sha = git(git_dir, "rev-parse", "HEAD")
    # a real code commit
    open(os.path.join(git_dir, "compiler", "ir.inc"), "w").write("x\n")
    git(git_dir, "add", "-A")
    git(git_dir, "commit", "-qm", "fix(A): real change")
    code_sha = git(git_dir, "rev-parse", "HEAD")
    return git_dir, docs_sha, code_sha


def main():
    with tempfile.TemporaryDirectory() as tmp:
        repo, docs_sha, code_sha = make_repo(tmp)

        print("the case it MUST annotate — and a CASCADE entry is one of them")
        casc = {"bad": docs_sha, "cascade": True, "range": [docs_sha]}
        why = twatch.bad_qualifier(casc, repo)
        check("a docs-only bad on a CASCADE entry gets the caveat",
              "NO buildable file" in why, repr(why))
        check("...and it says it is the tested upper bound, not a lead",
              "upper bound" in why and "not a lead" in why, repr(why))

        print("the same entry shape without the cascade flag, for parity")
        reg = {"bad": docs_sha, "range": [docs_sha]}
        check("a regression entry gets the identical string",
              twatch.bad_qualifier(reg, repo) == why,
              "cascade and regression must not diverge")

        print("the case it MUST NOT annotate — the arm nobody writes")
        real = {"bad": code_sha, "cascade": True, "range": [code_sha]}
        why2 = twatch.bad_qualifier(real, repo)
        check("a bad that DOES touch compiler/ gets no buildable-file caveat",
              "NO buildable file" not in why2, repr(why2))
        check("...and gets no qualifier at all, so it reads as a real lead",
              why2 == "", repr(why2))

        print("the other two qualifiers still rank below it and are reachable")
        pin = {"bad": code_sha, "pin_axis": True}
        check("pin-built says compiler/ commits cannot be causal",
              "pin-built" in twatch.bad_qualifier(pin, repo))
        first = {"bad": code_sha, "first_seen": True}
        check("a first-ever run says no earlier pass exists",
              "FIRST-ever" in twatch.bad_qualifier(first, repo))
        both = {"bad": docs_sha, "pin_axis": True, "first_seen": True}
        check("a non-buildable bad outranks both — it is the strongest fact",
              "NO buildable file" in twatch.bad_qualifier(both, repo))

        print("an unreadable sha degrades to the stamp, it does not raise")
        try:
            w = twatch.bad_qualifier({"bad": "0" * 40,
                                      "bad_untestable": True}, repo)
            check("falls back to the stored flag", "NO buildable file" in w,
                  repr(w))
        except Exception as exc:              # noqa: BLE001
            check("falls back to the stored flag", False, "raised %r" % exc)

    print()
    if FAILS:
        print("FAILED %d check(s): %s" % (len(FAILS), ", ".join(FAILS)))
        return 1
    print("all cascade-qualifier guards green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
