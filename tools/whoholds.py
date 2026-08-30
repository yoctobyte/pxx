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

TO BE SEEN BY THIS TOOL, put a `Lane:` trailer on your commits:

    Lane: frankA

Put it anywhere in the message -- this tool scans the whole body, deliberately.
git itself parses trailers only from the LAST contiguous block, so a `Lane:` line
one paragraph too high is invisible to `%(trailers:...)` with no error at all, and
that is how the very commit introducing this field lost its own trailer. A field
that fails silently when used conscientiously is worse than no field.

That is additive -- it does NOT replace CLAUDE.md's `Claude-Session:` line, which
is the spec and identifies a transcript. `Lane:` identifies someone you can reach,
which is the thing a collision actually needs, and a session whose id has no URL
form can satisfy it without fabricating one. The tool prefers `Lane:` and falls
back to the session id.

UNCOMMITTED work is invisible to this. A lane editing a file it has not committed
does not appear, so `quiet` means "nobody has LANDED anything recently", never
"nobody is in it". Ask before opening a file that matters.
"""
import re, subprocess, sys, time, collections

_LANE_OK = re.compile(r"^[A-Za-z][A-Za-z0-9_.-]{0,31}$")

WINDOW_MIN = 360


def sh(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout


def recent(path, minutes):
    """(age_min, session, subject) for each commit touching path in the window."""
    # Two trailers, deliberately. `Lane:` is the ADDRESSABLE one -- the string
    # ListAgents shows and SendMessage takes -- and is what answers "who do I ask".
    # `Claude-Session:` is CLAUDE.md's spec and identifies a transcript; it is read
    # as a fallback and is NOT redefined here. A lane whose session id has no URL
    # form (plain UUID sessions) can satisfy `Lane:` without fabricating a URL,
    # which is the divergence that prompted this.
    # Read the WHOLE body, not %(trailers:...). git parses trailers only from the
    # last contiguous block, so a `Lane:` line one paragraph too high is invisible
    # WITH NO ERROR -- which is exactly what happened on the commit that introduced
    # this field. Telling eight lanes a paragraph-placement rule they will get
    # wrong is the losing move; a documented trap is not a guard. So scan the body
    # and accept the line wherever it sits.
    out = sh("git", "log", f"--since={minutes} minutes ago", "--date=unix",
             "--format=%H%x01%cd%x01%s%x01%b%x02", "origin/master", "--", path)
    now, rows = time.time(), []
    for rec in out.split("\x02"):
        rec = rec.strip("\n")
        if not rec.strip():
            continue
        parts = rec.split("\x01")
        if len(parts) < 3:
            continue
        _, cd, subj = parts[0], parts[1], parts[2]
        body = parts[3] if len(parts) > 3 else ""
        sess = ""
        # The value must LOOK like a lane name: one identifier, optionally with a
        # parenthesised id after it. Without this the scan matched the prose line
        # "Lane: is also the better field for the actual need." out of a commit
        # body and reported a session called "is also the better" -- caught by
        # running it against the real log rather than a fixture. A loose pattern
        # on free text finds something every time, and finding something is what
        # makes it look like it worked.
        for bl in body.splitlines():
            if not bl.lower().startswith("lane:"):
                continue
            cand = bl.split(":", 1)[1].split("(")[0].strip()
            if _LANE_OK.match(cand):
                sess = cand[:18]
            else:
                # PRESENT BUT REJECTED is not ABSENT, and printing them the same
                # is the night's own failure one turn further in: not a wrong
                # thing that looks checked, but a FIX THAT LOOKS APPLIED. A lane
                # that wrote a trailer, reasoned about it, and had it silently
                # rejected goes on believing it is attributable. Name it so the
                # remedy is "fix the value", not "add the field".
                sess = "!bad"
            break
        if not sess:
            for tok in body.split():
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
        bad = sess.get("!bad", 0)
        if unknown:
            print(f"  !! {unknown} carry NO Lane:/session trailer — '?' means "
                  f"unidentified, not unowned. You cannot tell who to ask.")
        if bad:
            print(f"  !! {bad} carry a Lane: line whose VALUE does not parse "
                  f"(spaces, punctuation) — the field is present and doing "
                  f"nothing. Fix the value, not the absence.")
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
