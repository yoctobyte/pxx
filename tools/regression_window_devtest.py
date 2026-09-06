#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: `regression_window.py` prefers the verdict log and SAYS when the
other sources disagree.

THE CONTROLS ARE THE POINT, and one of them is the whole reason the tool exists.

The defect this tool was built after was not "a wrong window". It was a source
whose errors are ALL IN ONE DIRECTION and all plausible: `reports/*.md` carries
100% of REDs and 13% of GREENs, and a window's lower bound is a GREEN, so a
window computed from it is always too wide and never obviously empty. Nothing
about a single use looks broken. So the tool earns its keep only if the
disagreement FIRES on the measured shape and is SILENT when the two sources
agree -- a tool that announced a disagreement every run would be scrolled past
within a week, which is the failure this repo names in as many words.

A SECOND ONE-SIGNED SOURCE, found by the tool committing it: a TIER verdict is
an aggregate over jobs, so once any job is red the tier's last GREEN stops
advancing while the watcher's per-job bisect keeps narrowing. A window taken from
the frozen tier bound is too wide by however long the tier has been red -- again
always too wide, again plausible. So a ticket bound AHEAD of the log's GREEN is a
refinement and wins; one BEHIND it is a real conflict; and one git cannot resolve
is neither. All three are asserted below, because collapsing any pair of them
re-creates the defect.

The other shapes, each with its negative control:
  * a window with NO bounding GREEN must say so, never widen to everything;
  * a `full` GREEN must not bound a `native` RED -- different populations;
  * the ticket's own `## Range` field is the first thing printed, and a
    disagreement with it is reported as a finding rather than silently
    overridden (a hand re-derivation beat that field on layout alone, twice in
    one day, which is what put it at the top of the output).

Run: python3 tools/regression_window_devtest.py   (exit 0 = pass)
"""
import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOL = ROOT / "tools" / "regression_window.py"


def _git(cwd, *args, check=True):
    r = subprocess.run(("git",) + args, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise AssertionError(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout


def _repo():
    """A tree with four commits: two prose, two code. Returns (dir, shas)."""
    d = pathlib.Path(tempfile.mkdtemp()) / "repo"
    d.mkdir(parents=True)
    _git(d, "init", "--quiet", "-b", "master")
    _git(d, "config", "user.email", "t@example.invalid")
    _git(d, "config", "user.name", "t")
    (d / "compiler").mkdir()
    (d / "devdocs").mkdir()
    shas = []
    for i, (path, msg) in enumerate([
            ("compiler/base.inc", "base"),
            ("devdocs/note-one.md", "docs(x): a note"),
            ("compiler/pasparser_expr.inc", "fix(P): the code commit"),
            ("devdocs/note-two.md", "tstate(seven): GREEN bookkeeping")]):
        p = d / path
        p.write_text(f"{msg}\n{i}\n")
        _git(d, "add", "-A")
        _git(d, "commit", "--quiet", "-m", msg)
        shas.append(_git(d, "rev-parse", "HEAD").strip())
    return d, shas


def _state(repo, ndjson_rows, report_rows):
    """Lay tstate down inside the repo so --root and --git-dir are the same tree."""
    ts = repo / "devdocs" / "progress" / "tstate"
    (ts / "reports").mkdir(parents=True, exist_ok=True)
    with (ts / "runs-seven.ndjson").open("w") as f:
        for r in ndjson_rows:
            f.write(json.dumps(r) + "\n")
    for r in report_rows:
        name = r["date"].replace("-", "").replace(":", "") + f"-{r['sha'][:7]}-seven.md"
        (ts / "reports" / name).write_text(
            "---\n"
            f"sha: {r['sha']}\ndate: {r['date']}\nhost: seven\n"
            f"tier: {r['tier']}\nverdict: {r['verdict']}\n---\n\nbody\n")
    return ts


def _row(sha, date, tier, verdict):
    return {"sha": sha, "date": date, "tier": tier, "verdict": verdict}


def _run(repo, *extra):
    r = subprocess.run([sys.executable, str(TOOL), "--root", str(repo),
                        "--git-dir", str(repo), *extra],
                       capture_output=True, text=True)
    return r.stdout + r.stderr, r.returncode


def case_the_MEASURED_shape_a_stale_reports_bound_is_reported():
    # reports/ holds only the OLD green (the real coverage bias, in miniature);
    # the log holds a later one. This is b6815e5b8 exactly.
    repo, s = _repo()
    rows = [_row(s[0], "2026-09-06T04:52:57Z", "native", "GREEN"),
            _row(s[2], "2026-09-06T05:09:23Z", "native", "GREEN"),
            _row(s[3], "2026-09-06T05:14:02Z", "native", "RED")]
    _state(repo, rows, [rows[0], rows[2]])          # the middle GREEN has no report
    out, rc = _run(repo, "--bad", s[3][:9], "--tier", "native")
    assert f"window: {s[2][:9]}..{s[3][:9]}" in out, out
    assert "DISAGREEMENT" in out, "took the stale bound without saying so:\n" + out
    assert "STALE BY 1 GREEN" in out, out
    assert rc == 0, rc
    return "a reports/ bound older than the log's is named as a disagreement"


def case_CONTROL_when_reports_agrees_no_disagreement_is_printed():
    # THE CONTROL THAT KEEPS THE ABOVE READABLE. If this fired every run the
    # finding would be noise inside a week and nobody would read the real one.
    repo, s = _repo()
    rows = [_row(s[2], "2026-09-06T05:09:23Z", "native", "GREEN"),
            _row(s[3], "2026-09-06T05:14:02Z", "native", "RED")]
    _state(repo, rows, rows)
    out, _ = _run(repo, "--bad", s[3][:9], "--tier", "native")
    assert "DISAGREEMENT" not in out, "cried disagreement on two agreeing sources:\n" + out
    assert "reports/ agrees with the log" in out, out
    return "two sources that agree produce no disagreement line"


def case_NO_bounding_green_says_so_rather_than_widening_to_everything():
    # The failure that has no natural error: with no GREEN to bound it, an
    # unguarded scan takes the oldest row and reports a window of the whole repo.
    repo, s = _repo()
    rows = [_row(s[1], "2026-09-06T04:00:00Z", "native", "RED"),
            _row(s[3], "2026-09-06T05:14:02Z", "native", "RED")]
    _state(repo, rows, rows)
    out, _ = _run(repo, "--bad", s[3][:9], "--tier", "native")
    assert "NO BOUNDING VERDICT" in out, "invented a window with no GREEN behind it:\n" + out
    assert "\n  window: " not in out, "printed a window it could not bound:\n" + out
    return "no preceding GREEN is reported as no window, not as a wide one"


def case_a_FULL_green_does_not_bound_a_NATIVE_red():
    # Different populations. The `full` GREEN here is LATER than the native one,
    # so a scan that sorts by date and forgets the tier takes it and reports a
    # window of zero commits -- an exoneration, which is the expensive direction.
    repo, s = _repo()
    rows = [_row(s[0], "2026-09-06T04:52:00Z", "native", "GREEN"),
            _row(s[2], "2026-09-06T05:09:00Z", "full", "GREEN"),
            _row(s[3], "2026-09-06T05:14:00Z", "native", "RED")]
    _state(repo, rows, rows)
    out, _ = _run(repo, "--bad", s[3][:9], "--tier", "native")
    assert f"window: {s[0][:9]}..{s[3][:9]}" in out, (
        "let a full-tier GREEN bound a native RED:\n" + out)
    return "the bound is taken from the same tier, not the newest verdict"


def case_the_TICKETS_OWN_RANGE_is_printed_before_anything_is_computed():
    repo, s = _repo()
    rows = [_row(s[2], "2026-09-06T05:09:23Z", "native", "GREEN"),
            _row(s[3], "2026-09-06T05:14:02Z", "native", "RED")]
    _state(repo, rows, rows)
    t = repo / "ticket.md"
    t.write_text(
        "# regression: something\n\n## Range\n"
        f"bad `{s[3][:12]}`, last good `{s[2][:12]}`, 1 commit(s) in range\n")
    out, _ = _run(repo, str(t))
    head = out.split("== verdict log")[0]
    assert "## Range" in head, "computed a window before reading the report's own field:\n" + out
    assert "field and the verdict log agree" in out, out
    return "the report's own Range is the first answer printed"


def case_a_ticket_RANGE_that_contradicts_the_log_is_a_finding():
    # An OLDER ticket bound is a real conflict: a bisect that narrows can only
    # move forward, so a last-good behind the log's GREEN cannot be a refinement.
    repo, s = _repo()
    rows = [_row(s[2], "2026-09-06T05:09:23Z", "native", "GREEN"),
            _row(s[3], "2026-09-06T05:14:02Z", "native", "RED")]
    _state(repo, rows, rows)
    t = repo / "ticket.md"
    t.write_text("# regression\n\n## Range\n"
                 f"bad `{s[3][:12]}`, last good `{s[0][:12]}`, 3 commit(s) in range\n")
    out, _ = _run(repo, str(t))
    assert "THE TICKET AND THE LOG DISAGREE" in out, (
        "overrode the watcher's own field without saying so:\n" + out)
    assert "NARROWER" not in out, "read an older bound as a refinement:\n" + out
    return "a ticket bound OLDER than the log's GREEN is a conflict, not a refinement"


def case_the_TIER_AGGREGATE_trap_a_newer_ticket_bound_is_NARROWER_and_wins():
    # THE DEFECT THIS TOOL COMMITTED ON ITS SECOND REAL TICKET. A tier verdict is
    # an aggregate over jobs, so once ANY job is red the tier's last GREEN stops
    # advancing -- while the watcher's per-job bisect keeps narrowing. Taking the
    # tier bound then gives a window too wide by however long the tier has been
    # red, and the error is one-signed, exactly like the reports/ bias.
    # Here: the log's last GREEN is s[0] and the ticket bisected forward to s[2],
    # so the true window holds no code commit at all besides s[2]..s[3].
    repo, s = _repo()
    rows = [_row(s[0], "2026-09-06T04:00:00Z", "native", "GREEN"),
            _row(s[1], "2026-09-06T04:30:00Z", "native", "RED"),   # a DIFFERENT job
            _row(s[3], "2026-09-06T05:14:02Z", "native", "RED")]
    _state(repo, rows, rows)
    t = repo / "ticket.md"
    t.write_text("# regression\n\n## Range\n"
                 f"bad `{s[3][:12]}`, last good `{s[2][:12]}`, 1 commit(s) in range\n")
    out, _ = _run(repo, str(t))
    assert "NARROWER, and it wins" in out, (
        "took the frozen tier bound over a forward bisect:\n" + out)
    assert "2 commit(s) LATER" in out, out
    assert f"window {s[2][:9]}..{s[3][:9]}" in out, (
        "reported the narrower bound and then used the wide one:\n" + out)
    assert f"CODE   {s[2][:7]}" not in out, (
        "the ticket's own last-good leaked into its window as a suspect:\n" + out)
    return "a ticket bound ahead of a frozen tier GREEN is used, not disputed"


def case_a_ticket_bound_ABSENT_from_the_checkout_is_not_read_as_agreement():
    # git cannot answer, and "cannot compare" must not collapse into "agree" --
    # silence and confirmation are the same output otherwise.
    repo, s = _repo()
    rows = [_row(s[2], "2026-09-06T05:09:23Z", "native", "GREEN"),
            _row(s[3], "2026-09-06T05:14:02Z", "native", "RED")]
    _state(repo, rows, rows)
    t = repo / "ticket.md"
    t.write_text("# regression\n\n## Range\n"
                 f"bad `{s[3][:12]}`, last good `deadbeefcafe`, 1 commit(s) in range\n")
    out, _ = _run(repo, str(t))
    assert "could not be compared" in out, out
    assert "field and the verdict log agree" not in out, (
        "read an unanswerable comparison as agreement:\n" + out)
    assert "NARROWER" not in out and "DISAGREE" not in out, (
        "claimed a relation git could not answer:\n" + out)
    return "a bound git cannot resolve is reported as unknown, never as agreement"


def case_only_code_commits_are_offered_as_suspects():
    repo, s = _repo()
    rows = [_row(s[0], "2026-09-06T04:00:00Z", "native", "GREEN"),
            _row(s[3], "2026-09-06T05:14:02Z", "native", "RED")]
    _state(repo, rows, rows)
    out, _ = _run(repo, "--bad", s[3][:9], "--tier", "native")
    assert "1 that can fail a test" in out, out
    assert f"CODE   {s[2][:7]}" in out, out
    assert f"prose  {s[1][:7]}" in out, "counted a docs-only commit as a suspect:\n" + out
    return "a docs-only commit is filtered out of the suspect list"


def case_a_window_of_ONLY_prose_is_called_out_not_reported_as_a_clean_range():
    # THE POSITIVE CONTROL FOR THE FILTER ITSELF. If the classifier over-filters,
    # the suspect list empties and reads as "narrowed to nothing" -- a false
    # exoneration wearing the shape of a good result.
    repo, s = _repo()
    rows = [_row(s[2], "2026-09-06T05:00:00Z", "native", "GREEN"),
            _row(s[3], "2026-09-06T05:14:02Z", "native", "RED")]
    _state(repo, rows, rows)
    out, _ = _run(repo, "--bad", s[3][:9], "--tier", "native")
    assert "NO CODE COMMIT IN THE WINDOW" in out, (
        "an all-prose window read as a successfully narrowed one:\n" + out)
    return "an empty suspect list is flagged, not presented as a narrow window"


def case_a_missing_verdict_log_refuses_rather_than_falling_back():
    repo, s = _repo()
    (repo / "devdocs" / "progress" / "tstate" / "reports").mkdir(parents=True)
    out, _ = _run(repo, "--bad", s[3][:9], "--tier", "native")
    assert "NO runs-seven.ndjson" in out, out
    assert "will not guess" in out, out
    assert "\n  window: " not in out, "produced a window with no log at all:\n" + out
    return "no verdict log is reported, not silently answered from reports/"


CASES = [case_the_MEASURED_shape_a_stale_reports_bound_is_reported,
         case_CONTROL_when_reports_agrees_no_disagreement_is_printed,
         case_NO_bounding_green_says_so_rather_than_widening_to_everything,
         case_a_FULL_green_does_not_bound_a_NATIVE_red,
         case_the_TICKETS_OWN_RANGE_is_printed_before_anything_is_computed,
         case_a_ticket_RANGE_that_contradicts_the_log_is_a_finding,
         case_the_TIER_AGGREGATE_trap_a_newer_ticket_bound_is_NARROWER_and_wins,
         case_a_ticket_bound_ABSENT_from_the_checkout_is_not_read_as_agreement,
         case_only_code_commits_are_offered_as_suspects,
         case_a_window_of_ONLY_prose_is_called_out_not_reported_as_a_clean_range,
         case_a_missing_verdict_log_refuses_rather_than_falling_back]


def main():
    rc = 0
    for c in CASES:
        name = c.__name__.removeprefix("case_").replace("_", "-")
        try:
            note = c()
        except Exception as e:                  # noqa: BLE001 - report, continue
            print(f"  FAIL {name}: {type(e).__name__}: {e}")
            rc = 1
        else:
            print(f"  ok   {name} — {note}")
    print("regression-window OK" if rc == 0 else "regression-window BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
