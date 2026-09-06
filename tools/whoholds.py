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
    tools/whoholds.py --containing='not a record member: expected a field'

A FILENAME IS A CLAIM ABOUT WHERE CODE LIVES; `git grep -l` IS A MEASUREMENT OF
IT -- so `--containing=STRING` takes a string the code OWNS and resolves the
files itself. Added 2026-09-06 after this repo's coordinator reported a topic
quiet because nobody had committed to `compiler/pasparser_class.inc`. That file
exists (481 lines, "class/record member support"), which is why the answer came
back clean and plausible; the code in question was in `pasparser_decl.inc`, which
had eighteen commits in six hours and is one of the busiest files on the board.
frankB's statement of the defect is the reason this mode exists:

    A collision check against the wrong file cannot return anything but "clear".
    It has no failure mode.

The wrong file was chosen by the plausibility of its NAME, and every layer below
it worked perfectly. `report()` cannot detect this -- it is handed a path, the
path exists, nothing errors, and `quiet` is the honest answer to the question it
was actually asked. **So the guard has to sit ABOVE the path, which is what this
mode is.**

ZERO MATCHES IS LOUD AND EXITS NON-ZERO, deliberately. "No tracked file contains
this string" is the wrong-file failure arriving one step earlier, and printing it
as a quiet row would reproduce the exact defect this mode was written to remove:
a clean-looking negative about a population that was never located. It is the
same rule `whokilled.sh` enforces one directory over -- blindness must not read
as clean.

WHAT IT CANNOT TELL YOU, stated because a false clean here is expensive: only 219
of those 607 commits carried a Claude-Session trailer. A file whose recent writers
are all untrailered shows as `session=?`, and `?` is NOT "nobody" -- it is "a
session that did not identify itself". The tool says so per row rather than
printing a blank that reads as absence. Absence prompts a search; a constant does
not, which is the whole reason %an is useless here (it is `yoctobyte` on every
commit, by construction, because every agent commits as the owner).

TO BE SEEN BY THIS TOOL, put a `Lane:` trailer on your commits:

    Lane: frankA

ADOPTION, MEASURED 2026-09-06 SO THE FIELD IS NOT ASSUMED TO BE WORKING: of 722
commits in twelve hours, **0 carried a `Lane:` line**. The field is sound and
nobody uses it, so every row below falls back to the session id -- which names a
transcript and not somebody you can message. That is a real gap and it is NOT
fixed by the fallback repair below; a caller who needs a NAME still has to map
the id themselves (CLAUDE.md's reflog method, which answers WHERE a commit was
authored rather than WHO authored it). Stated here rather than left implicit,
because a tool that prints an id every time looks like it is identifying people.

GRAMMAR, stated because two lanes got it wrong within hours of the field existing
-- which is a docs defect, not two mistakes: letters, digits, `_` `.` `-`, starting
with a letter, at most 32 chars. NO `@`, no spaces, no parentheses in the name
itself (a parenthesised id AFTER the name is fine and is stripped). So
`claude@plexus` is rejected and `claude-plexus` is not.

USE THE NAME `ListAgents` SHOWS, because the field exists to answer "who do I ask"
and that name is what `SendMessage` takes. A ticket's `owner:` or `found-by:` field
is a different thing and may not be reachable.

THE FAILURE THIS TOOL CANNOT DETECT: a wrong-but-PARSEABLE name. `!bad` is loud;
`Lane: someone-elses-name` is silent and will be believed. That is the one input
error you must catch yourself, and it is the mirror of the state below -- present
and rejected is visible, present and wrong is not.

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
# The id itself, wherever it sits: bare, or at the tail of the URL the spec uses.
_SESSION_RE = re.compile(r"session_([A-Za-z0-9]{6,})")

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
            # MATCH THE ID ANYWHERE IN THE TOKEN, NOT AT ITS START. CLAUDE.md's
            # spec is a URL -- `Claude-Session: https://claude.ai/code/session_01Bk...`
            # -- so the whitespace-delimited token BEGINS with `https://` and a
            # `startswith("session_")` test matched nothing, ever. Measured
            # 2026-09-06: of 722 commits in twelve hours, 509 carried a URL-form
            # trailer and 0 carried a bare `session_` token, so this fallback was
            # dead against the entire corpus the spec produces. The tool then
            # printed `?×27` for a file whose every recent commit names its
            # session, plus "you cannot tell who to ask" -- an honest-sounding
            # warning about a condition that was false.
            #
            # ONE-SIGNED, LIKE EVERY OTHER FAILURE THIS TOOL EXISTS TO CATCH: it
            # can only under-report identification, it never errors, and `?` is
            # the reading that sends a caller to ask a human. The tool's own
            # docstring says "present and rejected is visible, present and wrong
            # is not"; this was the third state -- present and CORRECT, read as
            # absent.
            m = _SESSION_RE.search(body)
            if m:
                sess = m.group(1)[:8]
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


# A string that matches this many files is not locating a topic, it is locating a
# habit -- `Result :=` is in every file here. The list is still printed in full
# (truncating it would hide the very thing that makes it useless), but the caller
# is told the discriminator is weak, because a 40-file "who holds this" answer
# reads as thoroughness rather than as noise.
VAGUE_AT = 12


def files_containing(needle, pathspec):
    """Tracked files whose CONTENT has `needle`. Never guesses a filename.

    Fixed-string, not regex: the caller is pasting a line out of the source or
    out of a peer's message, and a stray `(` or `.` in it must not silently
    change the population. `-F` also makes an empty needle impossible to
    mistake for a match-everything pattern -- it is rejected before we get here.
    """
    cmd = ["git", "grep", "-l", "-F", needle]
    if pathspec:
        cmd += ["--"] + list(pathspec)
    out = subprocess.run(cmd, capture_output=True, text=True)
    # rc 1 is "no match" and is NOT an error; anything else is the instrument
    # failing, and must not be reported as an empty population.
    if out.returncode not in (0, 1):
        print("git grep failed (rc=%d): %s" % (out.returncode, out.stderr.strip()),
              file=sys.stderr)
        sys.exit(3)
    return [l for l in out.stdout.splitlines() if l.strip()]


def report_containing(needle, pathspec, minutes):
    paths = files_containing(needle, pathspec)
    if not paths:
        print("NO TRACKED FILE CONTAINS THAT STRING.")
        print("  %r" % needle)
        print("  This is not 'quiet'. Nothing was measured, because the code you")
        print("  are asking about was never located. Check the string against the")
        print("  source (or ask the peer who quoted it for the exact spelling)")
        print("  before reading any collision answer -- a check aimed at a file")
        print("  that does not hold the code can only come back clear.")
        if pathspec:
            print("  Searched under: %s" % " ".join(pathspec))
        sys.exit(2)
    print("string resolves to %d file(s):" % len(paths))
    for p in paths:
        print("  %s" % p)
    if len(paths) > VAGUE_AT:
        print("  !! %d files is a weak discriminator — this string is probably an"
              % len(paths))
        print("     idiom rather than the code you mean. Narrow it before trusting")
        print("     the holders below; a wide population makes everyone a holder.")
    report(paths, minutes)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    mins = WINDOW_MIN
    needle = None
    for a in sys.argv[1:]:
        if a.startswith("--window="):
            mins = int(a.split("=", 1)[1])
        elif a.startswith("--containing="):
            needle = a.split("=", 1)[1]
    if needle is not None and not needle.strip():
        # An empty needle would match every file and print a confident census of
        # the whole tree. Refuse rather than answer.
        print("--containing= needs a string the code owns, not an empty one.",
              file=sys.stderr)
        sys.exit(2)
    if "--hot" in sys.argv:
        hot(mins)
    elif needle is not None:
        report_containing(needle, args, mins)
    elif args:
        report(args, mins)
    else:
        print(__doc__.split("\n\n")[0])
        print("usage: tools/whoholds.py <file>... | --containing=STRING [pathspec...]"
              " | --hot [--window=MIN]")
