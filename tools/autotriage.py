#!/usr/bin/env python3
"""Gather triage evidence for every open regression the watcher has filed.

Track T's watcher already DETECTS a regression, bisects it to a commit range and
auto-files a stub ticket. What it does not do is the next twenty minutes: work
out which commit in the range is semantic, which lane owns it, and -- the one
that actually matters -- whether this red is a NEW bug or a previously-resolved
ticket coming back. This does that part and writes it into the stub.

It deliberately does NOT decide the fix, and it does NOT compile anything. It
reads git and the ticket tree, and it appends evidence. A human or an agent
still owns the call; they just do not start from zero.

WHY THE REOPEN CHECK EARNS ITS KEEP: on 2026-08-13 a red arrived whose range
held exactly one semantic commit, `feat(N)`. The obvious reading -- "N broke
it" -- was wrong. The failing test belonged to a Track A ticket resolved twelve
days earlier whose fix had never addressed the root cause, so the first new
field added to the affected class re-broke it verbatim. Routing that to N would
have reverted innocent work and re-armed the trap. Matching a red against
resolved tickets is the cheapest way to catch that, and it is pure text search.

Run it as often as you like: it is idempotent (skips stubs already carrying a
TRIAGED marker) and touches only the stub files it has something to say about.
"""

import argparse
import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TSTATE = os.path.join(REPO, "devdocs/progress/tstate")
PROGRESS = os.path.join(REPO, "devdocs/progress")
MARKER = "## AUTO-TRIAGE"

# Commits that are bookkeeping, not code. A range is usually mostly these, and
# saying so is half the triage -- "one semantic commit in range" is a much
# stronger statement than "four commits in range".
NOISE_RE = re.compile(r"^(tstate|tstate-ticket)\(|^docs\(progress\)")

# The repo's own commit-subject discipline (`feat(N):`, `chore(A):`) is a more
# reliable lane signal than any path heuristic, because the author declared it.
SUBJ_LANE_RE = re.compile(r"^[a-z]+\(([A-Za-z]+)\)")

# Fallback: map touched paths to a lane. Order matters -- most specific first.
PATH_LANES = [
    (re.compile(r"^compiler/(pylexer|pyparser)"), "N"),
    (re.compile(r"^compiler/(clexer|cparser|cpreproc)"), "C"),
    (re.compile(r"^compiler/builtin/pylib"), "N"),
    (re.compile(r"^compiler/(ir|symtab|defs)"), "A"),
    (re.compile(r"^compiler/(lexer|parser)\.inc"), "A"),   # P shares these
    (re.compile(r"^compiler/"), "A"),
    (re.compile(r"^lib/(rtl|pcl|crtl)"), "B"),
    (re.compile(r"^lib/"), "B"),
    (re.compile(r"^tools/"), "T"),
    (re.compile(r"^examples/"), "B"),
    (re.compile(r"\.npy$"), "N"),
    (re.compile(r"\.(c|h)$"), "C"),
    (re.compile(r"\.pas$"), "P"),
]


def git(*args, cwd=REPO):
    r = subprocess.run(["git"] + list(args), cwd=cwd,
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def subject(sha):
    return git("log", "-1", "--format=%s", sha)


def files_of(sha):
    out = git("show", "--format=", "--name-only", sha)
    return [f for f in out.splitlines() if f.strip()]


def lane_of(sha):
    """Declared lane from the commit subject, else inferred from paths."""
    m = SUBJ_LANE_RE.match(subject(sha))
    if m and len(m.group(1)) <= 2:
        return m.group(1).upper(), "declared in the commit subject"
    lanes = []
    for f in files_of(sha):
        for rx, lane in PATH_LANES:
            if rx.search(f):
                if lane not in lanes:
                    lanes.append(lane)
                break
    if not lanes:
        return "?", "no lane signal"
    return "/".join(lanes), "inferred from touched paths"


def test_src(job):
    return job.split("src:")[-1] if "src:" in job else ""


def test_stem(job):
    base = os.path.basename(test_src(job) or job)
    return re.sub(r"\.(pas|npy|c|py|zig|rs)$", "", base)


def stub_for(job):
    """The auto-filed stub ticket for this job, if the watcher wrote one.

    Matched on the test STEM as a substring of the filename. The stub name
    combines the make TARGET and the source path
    (`regression-test-core-test-uses-order-pylib-exception-a.md`), so
    reconstructing it from the source alone does not reproduce it -- an earlier
    attempt to rebuild the whole slug silently matched nothing.
    """
    stem = test_stem(job).replace("_", "-")
    if not stem:
        return None
    for sub in ("urgent", "working", "backlog", "unfinished"):
        d = os.path.join(PROGRESS, sub)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if fn.startswith("regression-") and fn.endswith(".md") and stem in fn[:-3]:
                return os.path.join(d, fn)
    return None


# Ticket slugs cited inside a source file's comments. 984 of this repo's 2026
# test sources carry one, which makes it the strongest cheap signal available.
SLUG_RE = re.compile(r"\b((?:bug|feature|regression|task|compat|decide|chore)-[a-z0-9][a-z0-9-]{8,})")


def find_ticket(slug):
    """Locate a ticket by slug anywhere in the progress tree; return (folder, track)."""
    for sub in os.listdir(PROGRESS):
        d = os.path.join(PROGRESS, sub)
        if not os.path.isdir(d):
            continue
        p = os.path.join(d, slug + ".md")
        if os.path.exists(p):
            track = ""
            m = re.search(r"^track:\s*(\S+)", open(p, errors="replace").read(), re.M)
            if m:
                track = m.group(1)
            return sub, track
    return None, ""


def cited_tickets(job):
    """Ticket slugs the FAILING TEST'S OWN SOURCE names.

    This is the signal that matters, and it is exact rather than heuristic: the
    repo's convention is that a regression test cites the ticket it was written
    for, in a header comment. `test_uses_order_pylib_exception_a.pas` opens with
    `{ bug-pascal-uses-order-breaks-pylib-exception: ... }`.

    The earlier version of this searched done/ for tickets whose TEXT mentioned
    the test filename, and on the 2026-08-13 red that surfaced a Track N feature
    ticket that merely happened to mention the file, while missing the Track A
    bug ticket that actually owned it -- i.e. it pointed at the wrong lane,
    which is worse than staying silent. Keep this ordered first.
    """
    src = test_src(job)
    if not src:
        return []
    try:
        text = open(os.path.join(REPO, src), errors="replace").read()
    except OSError:
        return []
    out = []
    for slug in dict.fromkeys(SLUG_RE.findall(text)):
        folder, track = find_ticket(slug)
        if folder:
            out.append((folder, slug, track))
    return out


def mentioning_tickets(job, exclude=()):
    """Weaker fallback: resolved tickets whose text names this test file."""
    stem, base = test_stem(job), os.path.basename(test_src(job) or "")
    hits = []
    for sub in ("done", "rejected"):
        d = os.path.join(PROGRESS, sub)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".md") or fn[:-3] in exclude:
                continue
            try:
                t = open(os.path.join(d, fn), errors="replace").read()
            except OSError:
                continue
            if (stem and stem in t) or (base and base in t):
                m = re.search(r"^track:\s*(\S+)", t, re.M)
                hits.append((sub, fn[:-3], m.group(1) if m else ""))
    return hits


def report(reg, host):
    job = reg["job"]
    rng = reg.get("range") or []
    semantic = [c for c in rng if not NOISE_RE.match(subject(c))]
    cited = cited_tickets(job)
    mentions = mentioning_tickets(job, exclude={c[1] for c in cited})

    L = []
    L.append("")
    L.append("%s %s — evidence only, no verdict" % (MARKER, reg.get("opened", "")[:10]))
    L.append("")
    L.append("Gathered by `tools/autotriage.py` from tstate on %s. Nothing here was "
             "compiled or run; it is git and the ticket tree. **The routing call is "
             "still yours.**" % host)
    L.append("")
    L.append("- **job:** `%s`" % job)
    L.append("- **last good:** `%s`  → **first bad:** `%s`"
             % (reg.get("good", "?")[:12], reg.get("bad", "?")[:12]))
    L.append("")

    L.append("### Range: %d commit(s), %d semantic" % (len(rng), len(semantic)))
    L.append("")
    if not semantic:
        L.append("**No semantic commits in range** — every commit is tstate or "
                 "progress bookkeeping. That usually means the red is "
                 "environmental (a flake, a host change, a stale binary) rather "
                 "than caused by code in this window. Check the job for "
                 "flakiness before hunting a cause.")
    else:
        L.append("| commit | lane | subject |")
        L.append("|---|---|---|")
        for c in semantic:
            lane, why = lane_of(c)
            L.append("| `%s` | **%s** <br><sub>%s</sub> | %s |"
                     % (c[:12], lane, why, subject(c)[:70].replace("|", "\\|")))
        L.append("")
        if len(semantic) == 1:
            L.append("Exactly one semantic commit in range. That is a strong "
                     "pointer — but see the caution below before treating it as "
                     "the culprit.")
    L.append("")

    if cited:
        done = [c for c in cited if c[0] in ("done", "rejected")]
        L.append("### ⚠ The test itself cites %d ticket(s)" % len(cited))
        L.append("")
        for sub, slug, track in cited:
            flag = "  ← **already resolved**" if sub in ("done", "rejected") else ""
            L.append("- [[%s]] — in `%s/`%s%s"
                     % (slug, sub, (", track %s" % track) if track else "", flag))
        L.append("")
        if done:
            L.append("**Two hypotheses, and this evidence does not rank them for "
                     "you.** Either that resolved fix did not hold — in which "
                     "case the commit in range is the *trigger*, and routing it "
                     "to that commit's lane reverts innocent work while leaving "
                     "the real defect armed — or the range genuinely broke "
                     "something new and the citation is incidental. **Cheapest "
                     "discriminator: re-run the cited ticket's own repro.** If it "
                     "fails, reopen that ticket in its lane (%s). If it passes, "
                     "the range is your answer."
                     % (done[0][2] or "see the ticket"))
            L.append("")
            L.append("<sub>Both outcomes have happened. 2026-08-13, "
                     "test_uses_order_pylib_exception_a: the citation was right "
                     "and the lone `feat(N)` in range was only the trigger. "
                     "2026-08-14, test_managed_block_meta: the citation was a red "
                     "herring and the `perf(A)` in range was the cause. Do not "
                     "let this section talk you out of reading the range.</sub>")
        else:
            L.append("The cited ticket(s) are still open, so this red is likely "
                     "part of that same work rather than a separate regression.")
    else:
        L.append("### The test cites no ticket")
        L.append("")
        L.append("No ticket slug in its source, so the reopen check has nothing "
                 "exact to go on — weigh the commit range above more heavily, and "
                 "consider adding a slug to the test's header when this is "
                 "resolved.")

    if mentions:
        L.append("")
        L.append("<sub>Weaker signal — resolved tickets whose text merely mentions "
                 "this file: %s. These often just record who added the test, so "
                 "do not route on them alone.</sub>"
                 % ", ".join("[[%s]]" % m[1] for m in mentions[:5]))
    L.append("")
    L.append("### Before acting")
    L.append("")
    L.append("`make compiler/pascal26` first, then reproduce. A red that "
             "'does not reproduce' against a compiler predating the range is the "
             "stale-binary trap, and it has cost this repo a wrong conclusion "
             "more than once.")
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default=os.uname().nodename)
    ap.add_argument("--dry-run", action="store_true",
                    help="print what would be written, change nothing")
    ap.add_argument("--rev",
                    help="read tstate from this git rev (e.g. origin/master) "
                         "instead of the working tree — lets a timer see what "
                         "the watcher published without pulling into a tree "
                         "somebody may be working in")
    ap.add_argument("--job", help="only this job")
    a = ap.parse_args()

    if a.rev:
        raw = git("show", "%s:devdocs/progress/tstate/%s.json" % (a.rev, a.host))
        if not raw:
            sys.exit("autotriage: no tstate for %s at %s" % (a.host, a.rev))
        state = json.loads(raw)
    else:
        path = os.path.join(TSTATE, "%s.json" % a.host)
        if not os.path.exists(path):
            sys.exit("autotriage: no tstate for host %s" % a.host)
        state = json.load(open(path))
    opens = state.get("open_regressions") or []
    if not opens:
        print("autotriage: no open regressions on %s" % a.host)
        return 0

    wrote = 0
    for reg in opens:
        job = reg["job"]
        if a.job and a.job not in job:
            continue
        stub = stub_for(job)
        # The report is ALWAYS computed. The stub only decides where it gets
        # written, and whether it does at all -- a monitor wants the evidence in
        # its alert even when the stub is missing or already resolved, which is
        # exactly when a human is most likely to be looking.
        text = report(reg, a.host)
        if not stub:
            print("autotriage: %s — OPEN, no live stub ticket "
                  "(already resolved, or never filed)" % job)
            if a.dry_run:
                print(text)
            continue
        body = open(stub, errors="replace").read()
        if MARKER in body or "## TRIAGED" in body:
            print("autotriage: %s — already triaged (%s)"
                  % (job, os.path.relpath(stub, REPO)))
            continue
        if a.dry_run:
            print("--- would append to %s ---" % os.path.relpath(stub, REPO))
            print(text)
            continue
        with open(stub, "a") as f:
            f.write(text + "\n")
        print("autotriage: %s — evidence written to %s"
              % (job, os.path.relpath(stub, REPO)))
        wrote += 1

    # exit 1 == "something new was triaged", so a timer can notify on it
    return 1 if wrote else 0


if __name__ == "__main__":
    sys.exit(main())
