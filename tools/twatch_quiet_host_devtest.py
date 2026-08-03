#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for quiet-host handling in tstate readers.

A regression clears when a later run ON THAT HOST passes the job — verdicts are
per host by design. So a host that stops running leaves entries nothing can ever
clear. borg's watcher stopped 2026-07-31 with one open, and every `--status` and
`gate.sh check` since printed `fpc-bootstrap#src:compiler/compiler.pas` as
though it were live: plausible enough that each new agent re-investigated it,
and the habit it trained was skimming open-regression lines — which is how a
real one gets missed (task-t-borg-open-regression-is-permanently-stale).

Quietness is decided by the CLOCK, not by a retire flag, because borg is still
the dev box and may run the watcher again occasionally (user,
decide-t-queue-scope-2026-08-03). So what must hold is as much about reversal
as about suppression:

  * a host that published recently is never quiet;
  * a host past the threshold is quiet, and its entries are HELD (named and
    counted), never silently dropped;
  * a fresh host's entries are untouched, even when a quiet host sits beside it;
  * publishing again un-quiets a host with no other action.

Temp dirs only; the repo's own tstate is not read or written.
Run: python3 tools/twatch_quiet_host_devtest.py
"""
import json
import pathlib
import sys
import tempfile
import time
import types

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import twatch  # noqa: E402

NOW = 1785700000.0            # fixed clock: no Date.now()-style flakiness


def iso(secs_ago):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - secs_ago))


def host_state(host, age_secs, regs=1):
    return {
        "host": host,
        "last": {"sha": "a" * 40, "verdict": "GREEN", "tier": "native",
                 "date": iso(age_secs), "wall": 100},
        "last_full": {"sha": "b" * 40, "verdict": "RED"},
        "jobs": {},
        "history": [],
        "open_regressions": [
            {"job": "fpc-bootstrap#src:compiler/compiler.pas",
             "bad": "b1976742df2c" + "0" * 28, "good": None,
             "range": ["c" * 40]}
        ] * regs,
    }


def index_for(states):
    """Run regen_index over a scratch tstate dir; return the TSTATE.md text."""
    tmp = tempfile.mkdtemp(prefix="twatch-quiet-")
    tdir = pathlib.Path(tmp) / twatch.TSTATE_REL
    tdir.mkdir(parents=True)
    for st in states:
        (tdir / f"{st['host']}.json").write_text(json.dumps(st), encoding="utf-8")
    twatch.regen_index(types.SimpleNamespace(path=tmp))
    return (tdir / "TSTATE.md").read_text(encoding="utf-8")


def case_recent_host_is_never_quiet():
    st = host_state("xeon", 3600)
    assert twatch.host_quiet_secs(st, NOW) is None
    return "1h old -> live"


def case_stopped_host_goes_quiet():
    age = twatch.QUIET_HOST_SECS + 86400
    st = host_state("borg", age)
    got = twatch.host_quiet_secs(st, NOW)
    assert got is not None and abs(got - age) < 2, got
    return f"{twatch.fmt_age(age)} old -> quiet"


def case_threshold_boundary():
    """Just inside the window is still live — the threshold must not make a
    host that ran this morning look abandoned."""
    assert twatch.host_quiet_secs(host_state("h", twatch.QUIET_HOST_SECS - 60),
                                  NOW) is None
    assert twatch.host_quiet_secs(host_state("h", twatch.QUIET_HOST_SECS + 60),
                                  NOW) is not None
    return f"boundary at {twatch.fmt_age(twatch.QUIET_HOST_SECS)}"


def case_never_ran_is_not_quiet():
    """A host with no verdict yet is a DIFFERENT state — being enrolled, not
    abandoned — and must not be reported as having gone quiet."""
    st = host_state("new", 0)
    st["last"] = {}
    assert twatch.host_quiet_secs(st, NOW) is None
    st["last"] = {"date": "not-a-date"}
    assert twatch.host_quiet_secs(st, NOW) is None
    return "no date / bad date -> not quiet"


def case_index_holds_quiet_entries_and_keeps_live_ones():
    quiet = host_state("borg", twatch.QUIET_HOST_SECS + 86400)
    live = host_state("xeon", 600)
    live["open_regressions"] = [
        {"job": "test-core#src:test/live_one.pas", "bad": "d" * 40,
         "good": None, "range": []}]
    text = index_for([quiet, live])

    open_sec, _, held_sec = text.partition("## Held")
    assert "## Held" in text, f"no held section generated:\n{text}"
    assert "live_one.pas" in open_sec, "a LIVE host's regression was held"
    assert "fpc-bootstrap" not in open_sec, \
        "a quiet host's regression is still in the live list"
    assert "fpc-bootstrap" in held_sec, "the held entry was dropped, not held"
    assert "borg" in held_sec and "QUIET" in text, \
        "the quiet host is not named — held must never mean hidden"
    return "quiet held, live kept, host named"


def case_publishing_again_un_quiets():
    """The reversal property that made this time-based rather than a flag."""
    st = host_state("borg", twatch.QUIET_HOST_SECS + 86400)
    assert twatch.host_quiet_secs(st, NOW) is not None
    st["last"]["date"] = iso(60)          # one new publish
    assert twatch.host_quiet_secs(st, NOW) is None, \
        "a host that published again is still marked quiet"
    text = index_for([st])
    assert "## Held" not in text and "fpc-bootstrap" in text, \
        "entries did not return to the live list after the host published"
    return "one publish restores it, no action needed"


CASES = [
    case_recent_host_is_never_quiet,
    case_stopped_host_goes_quiet,
    case_threshold_boundary,
    case_never_ran_is_not_quiet,
    case_index_holds_quiet_entries_and_keeps_live_ones,
    case_publishing_again_un_quiets,
]


def main():
    rc = 0
    for case in CASES:
        name = case.__name__.removeprefix("case_").replace("_", "-")
        try:
            note = case()
        except AssertionError as e:
            print(f"  FAIL {name}: {e}")
            rc = 1
        else:
            print(f"  ok   {name} — {note}")
    print("quiet-host handling OK" if rc == 0 else "quiet-host handling BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
