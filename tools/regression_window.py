#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Compute a regression window from the VERDICT LOG, and say when the other
sources disagree.

WHY THIS EXISTS, AND IT IS NOT "computing a window is hard".

Measured 2026-09-06, by this seat, on
`regression-test-core-test-builtin-type-names-cast-and-declare`. A native RED
arrived at `b6815e5b8`. The window was computed by scanning
`devdocs/progress/tstate/reports/*.md` for the newest preceding native GREEN,
which answered `9046a2fdd` -- 14 commits back, 8 of them code. The real window
was ONE code commit. Four native GREENs sat between them.

**`reports/` is not the verdict log, and what it omits is GREENs.** Counted over
host seven's native tier the same day:

    441 of 441 REDs   have a reports/*.md   (100%)
     43 of 340 GREENs have one              ( 13%)

A window is `last GREEN -> first RED`. The directory is therefore COMPLETE on the
bound that does not move and 13% complete on the bound that does, so every error
runs in one direction: a wider window, more suspects, blame spread onto commits a
verdict has already cleared. **A guard whose errors are all one-signed and all
plausible never looks broken from a single use** -- which is why that scan was
still trusted while being used to correct someone else.

Two further failures from the same hour, both encoded as checks here:

* The completeness check was itself cross-population: 1954 report files against
  1255 ndjson rows read as a surplus. `reports/` holds four hosts, the ndjson
  holds one. Seven's real coverage was 869 of 1256. **A ratio between two sets
  with different populations is not a completeness check** -- so this tool
  compares one host's reports against that host's log, and never the directory
  against a single file.
* **The answer was already on the ticket.** The auto-filed stub carried
  `## Range: bad b6815e5b8675, last good f1148d82c2d4, 1 commit(s) in range`
  in its FIRST commit, correct and naming its own source. A hand re-derivation
  was written in a blockquote ABOVE it, where a re-derivation reads as analysis
  and a generated field reads as footer. Two sessions walked past it the same
  day. **So this tool prints the ticket's own field first, before computing
  anything**, and treats a disagreement with it as a finding rather than as a
  correction.

USAGE
    tools/regression_window.py devdocs/progress/backlog/regression-....md
    tools/regression_window.py --bad b6815e5b8 --tier native --host seven

It REPORTS; it does not gate. Exit is 0 unless the arguments are unusable.
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

# A commit touching only these cannot fail a test. Deliberately short: the cost
# of wrongly calling a commit non-code is an exonerated suspect, so the list
# holds only paths with no build or test input under them at all.
PROSE_PREFIXES = ("devdocs/", "docs/")
PROSE_SUFFIXES = (".md",)


def _read_ndjson(root, host):
    p = root / "devdocs" / "progress" / "tstate" / f"runs-{host}.ndjson"
    if not p.exists():
        return None
    rows = []
    for ln in p.read_text(errors="replace").splitlines():
        ln = ln.strip()
        if not ln:
            continue
        try:
            r = json.loads(ln)
        except ValueError:
            continue
        if r.get("sha") and r.get("date") and r.get("tier"):
            rows.append(r)
    rows.sort(key=lambda r: r["date"])
    return rows


def _read_reports(root, host):
    """The BIASED source, read only so the tool can say how it differs."""
    d = root / "devdocs" / "progress" / "tstate" / "reports"
    if not d.is_dir():
        return []
    rows = []
    for f in sorted(d.glob(f"*-{host}.md")):
        head = f.read_text(errors="replace")[:1200]
        g = {k: re.search(rf"^{k}: (\S+)", head, re.M) for k in
             ("sha", "date", "tier", "verdict")}
        if all(g.values()):
            rows.append({k: m.group(1) for k, m in g.items()})
    rows.sort(key=lambda r: r["date"])
    return rows


def _last_green_before(rows, bad_sha, tier):
    """The bound. Returns (green_row, red_row) or (None, red_row) or (None, None).

    Strictly same tier: a `full` GREEN does not bound a `native` RED, they are
    different populations. Strictly earlier by DATE, not by list position.
    """
    red = None
    for r in rows:
        if r["tier"] == tier and r["sha"].startswith(bad_sha) and r["verdict"] == "RED":
            red = r
            break
    if red is None:
        return None, None
    prior = [r for r in rows
             if r["tier"] == tier and r["date"] < red["date"] and r["verdict"] == "GREEN"]
    return (prior[-1] if prior else None), red


def _parse_ticket_range(text):
    """The watcher's own answer, which is the thing to read before computing."""
    m = re.search(r"^bad `([0-9a-f]+)`,\s*last good `([0-9a-f]+)`,\s*(\d+) commit",
                  text, re.M)
    if not m:
        return None
    return {"bad": m.group(1), "good": m.group(2), "n": int(m.group(3))}


def _git(gitdir, *args):
    r = subprocess.run(("git", "-C", str(gitdir)) + args,
                       capture_output=True, text=True)
    return r.returncode, r.stdout


def _classify(gitdir, good, bad):
    """Split the window into commits that can and cannot physically fail a test."""
    rc, out = _git(gitdir, "log", "--format=%h\t%s", f"{good}..{bad}")
    if rc != 0:
        return None
    code, prose = [], []
    for ln in out.splitlines():
        if "\t" not in ln:
            continue
        sha, subj = ln.split("\t", 1)
        rc2, files = _git(gitdir, "show", "--pretty=", "--name-only", sha)
        paths = [f for f in files.splitlines() if f.strip()]
        is_prose = bool(paths) and all(
            p.startswith(PROSE_PREFIXES) or p.endswith(PROSE_SUFFIXES) for p in paths)
        (prose if is_prose else code).append((sha, subj))
    return code, prose


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("ticket", nargs="?", help="an auto-filed regression ticket")
    ap.add_argument("--bad", help="the RED sha, if no ticket is given")
    ap.add_argument("--tier", default="native")
    ap.add_argument("--host", default="seven")
    ap.add_argument("--root", default=None,
                    help="repo root to read tstate and tickets from")
    ap.add_argument("--git-dir", default=None,
                    help="tree to run git in (default: --root)")
    a = ap.parse_args(argv)

    root = pathlib.Path(a.root) if a.root else pathlib.Path(__file__).resolve().parent.parent
    gitdir = pathlib.Path(a.git_dir) if a.git_dir else root

    bad, tier, ticket_range = a.bad, a.tier, None
    if a.ticket:
        tp = pathlib.Path(a.ticket)
        if not tp.is_absolute():
            tp = root / a.ticket if (root / a.ticket).exists() else tp
        text = tp.read_text(errors="replace")
        ticket_range = _parse_ticket_range(text)
        m = re.search(r"^sha: (\S+)", text, re.M) or re.search(r"at ([0-9a-f]{9,})", text)
        if not bad and (ticket_range or m):
            bad = ticket_range["bad"] if ticket_range else m.group(1)
        mt = re.search(r"--tier (\w+)", text)
        if mt and not a.tier != "native":
            tier = mt.group(1)
    if not bad:
        print("regression-window: no bad sha (give a ticket with a ## Range, or --bad)")
        return 2
    bad = bad[:12]

    print(f"regression-window: bad={bad} tier={tier} host={a.host}")
    print()

    # ---- 1. THE TICKET'S OWN FIELD, BEFORE ANYTHING IS COMPUTED ------------
    print("== the report's own answer (read this first) ==")
    if ticket_range:
        print(f"  ## Range: last good {ticket_range['good']}, "
              f"{ticket_range['n']} commit(s) in range")
        print("  This is the watcher's measurement, not boilerplate -- it has a bisector")
        print("  behind it. Disagreeing with it is a finding, not a correction.")
    elif a.ticket:
        print("  no `## Range` field on this ticket")
    else:
        print("  (no ticket given)")
    print()

    # ---- 2. THE VERDICT LOG ------------------------------------------------
    rows = _read_ndjson(root, a.host)
    if rows is None:
        print(f"== verdict log ==\n  NO runs-{a.host}.ndjson under {root} "
              f"-- cannot compute a window, and will not guess one")
        return 0
    green, red = _last_green_before(rows, bad, tier)
    print(f"== verdict log: runs-{a.host}.ndjson ({len(rows)} rows) ==")
    if red is None:
        print(f"  NO {tier} RED at {bad} in the log. The window is unbounded on the")
        print("  side you are standing on; do not substitute the newest row.")
        return 0
    if green is None:
        print(f"  NO {tier} GREEN precedes {bad} in this log.")
        print("  NO BOUNDING VERDICT -- there is no window, not a window of everything.")
        return 0
    print(f"  last {tier} GREEN  {green['sha'][:9]}  {green['date']}")
    print(f"  first {tier} RED   {red['sha'][:9]}  {red['date']}")
    print(f"  window: {green['sha'][:9]}..{red['sha'][:9]}")
    print()

    # ---- 3. THE BIASED SOURCE, NAMED AS SUCH -------------------------------
    reps = _read_reports(root, a.host)
    rgreen, rred = _last_green_before(reps, bad, tier)
    nred = sum(1 for r in rows if r["tier"] == tier and r["verdict"] == "RED")
    ngrn = sum(1 for r in rows if r["tier"] == tier and r["verdict"] == "GREEN")
    rep_shas = {r["sha"][:12] for r in reps if r["tier"] == tier}
    cred = sum(1 for r in rows
               if r["tier"] == tier and r["verdict"] == "RED" and r["sha"][:12] in rep_shas)
    cgrn = sum(1 for r in rows
               if r["tier"] == tier and r["verdict"] == "GREEN" and r["sha"][:12] in rep_shas)
    print(f"== the write-ups, {a.host} {tier} tier -- the source that is biased ==")
    print(f"  REDs   with a report file: {cred} of {nred}")
    print(f"  GREENs with a report file: {cgrn} of {ngrn}")
    print(f"  proportion OF: host {a.host}, tier {tier}, {len(rows)} log rows as of")
    print(f"     {rows[-1]['date']} -- an APPEND-ONLY log read at one instant, not a")
    print("     terminated producer. Both numerator and denominator still move.")
    print("  (compared against THIS host's log only: the write-up directory holds every")
    print("   host, and a ratio across two populations is not a completeness check)")
    if rgreen is None:
        print("  reports/ has no bounding GREEN at all for this window")
    elif rgreen["sha"][:9] != green["sha"][:9]:
        rc, out = _git(gitdir, "log", "--oneline", f"{rgreen['sha'][:12]}..{red['sha'][:12]}")
        wide = len(out.splitlines()) if rc == 0 else -1
        print(f"  reports/ answers {rgreen['sha'][:9]} ({rgreen['date']}) -- STALE BY "
              f"{sum(1 for r in rows if r['tier'] == tier and r['verdict'] == 'GREEN' and rgreen['date'] < r['date'] < red['date'])} GREEN verdict(s)")
        print(f"  !! DISAGREEMENT: reports/ would give a {wide}-commit window, "
              f"the log gives the one above.")
        print("  !! The error is one-signed: reports/ is complete on REDs and sparse on")
        print("     GREENs, so it is always too WIDE and never obviously empty.")
    else:
        print("  reports/ agrees with the log on this window")
    print()

    # ---- 4. AGAINST THE TICKET'S OWN FIELD ---------------------------------
    if ticket_range:
        if not green["sha"].startswith(ticket_range["good"][:9]) and \
           not ticket_range["good"].startswith(green["sha"][:9]):
            print("== !! THE TICKET AND THE LOG DISAGREE ==")
            print(f"  ticket `## Range` last good: {ticket_range['good'][:9]}")
            print(f"  verdict log last {tier} GREEN: {green['sha'][:9]}")
            print("  One of them is wrong and the ticket is the one with a bisector")
            print("  behind it. Settle this before publishing either.")
            print()
        else:
            print("== the ticket's field and the verdict log agree ==\n")

    # ---- 5. WHAT IN THE WINDOW CAN PHYSICALLY FAIL A TEST ------------------
    cls = _classify(gitdir, green["sha"][:12], red["sha"][:12])
    if cls is None:
        print("== window contents ==\n  git could not walk this range in "
              f"{gitdir} (shallow clone, or a sha not present here)")
        return 0
    code, prose = cls
    print(f"== window contents: {len(code) + len(prose)} commit(s), "
          f"{len(code)} that can fail a test ==")
    for sha, subj in code:
        print(f"  CODE   {sha}  {subj}")
    for sha, subj in prose:
        print(f"  prose  {sha}  {subj}")
    if not code:
        print("  NO CODE COMMIT IN THE WINDOW -- the regression is not in this range.")
        print("  Suspect a flaky job, a toolchain move, or a mis-tiered bound.")
    print()
    print("Do not hand-bisect this. T bisects backwards on its own; the value here is")
    print("the window and the candidate filter, recorded so nobody re-derives them.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
