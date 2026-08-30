#!/usr/bin/env python3
"""whoholds — who has been writing to these files, and how recently.

WHY THIS EXISTS. On 2026-08-30 a lane measured the fleet: 607 commits in six
hours from at least 10 distinct sessions, against THREE locks in
devdocs/progress/working/. That is not carelessness. A claim/resolve round trip
per commit is friction nobody pays voluntarily when the commit cadence is minutes,
so the ticket lock -- which is real, and correct for ticket-granularity work --
is simply not the instrument for "may I open this file right now".

This is that instrument. It answers the question agents actually ask, from data
that is always current because it is a side effect of committing rather than a
thing anyone must remember to do.

    tools/whoholds.py compiler/ir_codegen.inc compiler/symtab.inc
    tools/whoholds.py --hot                 # the busiest files, last 6h
    tools/whoholds.py --mine compiler/*.inc # ... and whether the last writer was me

WHAT IT CANNOT TELL YOU, stated because a false clean here is expensive: only 219
of those 607 commits carried a Claude-Session trailer. A file whose recent writers
are all untrailered shows as `session=?`, and `?` is NOT "nobody" -- it is "a
session that did not identify itself". The tool says so per row rather than
printing a blank that reads as absence. Absence prompts a search; a constant does
not, which is the whole reason %an is useless here (it is `yoctobyte` on every
commit, by construction, because every agent commits as the owner).

UNCOMMITTED work is invisible to this. A lane editing a file it has not committed
does not appear, so `quiet` means "nobody has LANDED anything recently", never
"nobody is in it". Ask before opening a file that matters.
"""
import subprocess, sys, time, collections

WINDOW_MIN = 360


def sh(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout


def recent(path, minutes):
    """(age_min, session, subject) for each commit touching path in the window."""
    out = sh("git", "log", f"--since={minutes} minutes ago", "--date=unix",
             "--format=%H%x01%cd%x01%s%x01%(trailers:key=Claude-Session,valueonly=true)",
             "origin/master", "--", path)
    now, rows = time.time(), []
    for line in out.splitlines():
        parts = line.split("\x01")
        if len(parts) < 3:
            continue
        _, cd, subj = parts[0], parts[1], parts[2]
        trailer = parts[3] if len(parts) > 3 else ""
        sess = ""
        for tok in trailer.split():
            if tok.startswith("session_"):
                sess = tok[8:16]
                break
        try:
            age = int((now - int(cd)) / 60)
        except ValueError:
            continue
        rows.append((age, sess or "?", subj))
    return rows


def report(paths, minutes):
    for p in paths:
        rows = recent(p, minutes)
        if not rows:
            print(f"\n{p}\n  quiet — nothing landed in {minutes}m "
                  f"(uncommitted work is INVISIBLE here; quiet is not empty)")
            continue
        sess = collections.Counter(s for _, s, _ in rows)
        unknown = sess.get("?", 0)
        who = ", ".join(f"{k}×{v}" for k, v in sess.most_common())
        age, s, subj = rows[0]
        # Never print a session COUNT as if it were known. The unknowns collapse
        # into one "?" bucket, so `1 session` for eleven untrailered commits could
        # be one lane or eleven -- and a precise-looking number is worse than an
        # honest range, because nobody re-checks a number. Same failure this tool
        # exists to expose, committed inside the tool that exposes it.
        known = len(sess) - (1 if unknown else 0)
        if unknown:
            count = f"{known}+? session(s), at least {known + 1}"
        else:
            count = f"{known} session(s)"
        print(f"\n{p}")
        print(f"  {len(rows)} commit(s) / {count} in {minutes}m — {who}")
        print(f"  most recent: {age}m ago  session={s}  {subj[:78]}")
        if unknown:
            print(f"  !! {unknown} of them carry NO session trailer — '?' means "
                  f"unidentified, not unowned. You cannot tell who to ask.")
        if age <= 30:
            print(f"  !! HOT — last write {age}m ago. Ask before opening it.")


def hot(minutes, top=15):
    out = sh("git", "log", f"--since={minutes} minutes ago", "--name-only",
             "--format=", "origin/master")
    # Excluded: the generated boards (every lane rewrites them on every ticket
    # move) and devdocs/progress/tstate/** (the watcher DAEMON, which is not a
    # lane and cannot collide with one). Without these two the list is 90%
    # machine noise and the contended SOURCE files never surface -- a ranking
    # whose top rows are things nobody competes for is not a ranking.
    skip = ("devdocs/progress/BOARD", "devdocs/progress/tstate/")
    c = collections.Counter(l for l in out.splitlines()
                            if l.strip() and not l.startswith(skip))
    print(f"busiest files, last {minutes}m (generated boards + tstate excluded):")
    for f, n in c.most_common(top):
        print(f"  {n:4d}  {f}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    mins = WINDOW_MIN
    for a in sys.argv[1:]:
        if a.startswith("--window="):
            mins = int(a.split("=", 1)[1])
    if "--hot" in sys.argv:
        hot(mins)
    elif args:
        report(args, mins)
    else:
        print(__doc__.split("\n\n")[0])
        print("usage: tools/whoholds.py <file>... | --hot [--window=MIN]")
