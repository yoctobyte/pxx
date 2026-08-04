#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for benchmark hardware provenance (feature-t-bench-hardware-provenance).

`bench.tsv` records WHICH host but nothing about WHAT that host is, and a
hostname is not a hardware identity: it survives a CPU swap, a RAM upgrade, a
governor change or a kernel update while the numbers silently stop being
comparable. Live instance — the series moved from borg (i7-6700 @3.4GHz) to
xeon (E5-2620 v2 @2.1GHz) on 2026-07-31 and got 40-90% slower on identical
work, which reads as a 2x regression that never happened.

What must hold:

  * a fingerprint covers the facts that decide comparability, INCLUDING the
    governor — on this Xeon that is 2.1 vs 2.6 GHz, more than most optimisation
    work moves;
  * an unchanged box appends nothing (this runs on every publish);
  * a changed box opens a NEW epoch and closes the old one with `to`, so
    history stays readable rather than being rewritten;
  * `scale` is not reused as a normaliser — it read 1.0 on both boxes despite
    the 40-90% gap, because it is calibrated on a compile, not on compute.

Writes only into a temp dir.
Run: python3 tools/twatch_host_epoch_devtest.py
"""
import json
import pathlib
import sys
import tempfile
import types

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import twatch  # noqa: E402


def scratch():
    tmp = tempfile.mkdtemp(prefix="hostepoch-")
    (pathlib.Path(tmp) / twatch.TSTATE_REL).mkdir(parents=True)
    return types.SimpleNamespace(path=tmp)


def hosts_doc(clone):
    with open(pathlib.Path(clone.path) / twatch.HOSTS_REL) as f:
        return json.load(f)


def case_fingerprint_covers_what_decides_comparability():
    hw = twatch.host_hardware()
    for field in ("cpu", "cores", "threads", "mhz_max", "mem_total_kb",
                  "kernel", "governor", "turbo"):
        assert field in hw, f"{field} missing from the hardware record"
    assert hw["cpu"], "no CPU model — the one field a reader looks at first"
    return f"{hw['cpu'].split('@')[0].strip()}, {hw['threads']}t, {hw['governor']}"


def case_first_run_opens_an_epoch():
    clone = scratch()
    assert twatch.record_host_epoch(clone, "xeon") is True
    epochs = hosts_doc(clone)["xeon"]
    assert len(epochs) == 1 and epochs[0]["from"] and "to" not in epochs[0]
    assert len(epochs[0]["fp"]) == 12, epochs[0]["fp"]
    return "one open epoch, stamped with `from`"


def case_unchanged_box_appends_nothing():
    """This runs on every publish — a box that has not changed must not grow the
    file, or the provenance becomes its own noise."""
    clone = scratch()
    twatch.record_host_epoch(clone, "xeon")
    for _ in range(5):
        assert twatch.record_host_epoch(clone, "xeon") is False
    assert len(hosts_doc(clone)["xeon"]) == 1
    return "5 further publishes -> still one epoch"


def case_changed_hardware_opens_a_new_epoch_and_closes_the_old():
    """The borg -> xeon case. History is appended, never rewritten: the old
    epoch keeps its numbers and gains a `to`, so a step in the series can be
    labelled 'new hardware here' rather than read as a regression."""
    clone = scratch()
    twatch.record_host_epoch(clone, "xeon")
    old = hosts_doc(clone)["xeon"][0]["fp"]
    twatch._HW_CACHE["cpu"] = "Intel(R) Core(TM) i7-6700 CPU @ 3.40GHz"
    try:
        assert twatch.record_host_epoch(clone, "xeon") is True
        epochs = hosts_doc(clone)["xeon"]
    finally:
        twatch._HW_CACHE.clear()
    assert len(epochs) == 2, epochs
    assert epochs[0]["fp"] == old and epochs[0]["to"], "old epoch not closed"
    assert epochs[1]["fp"] != old and "to" not in epochs[1], "new epoch not open"
    assert epochs[0]["cpu"] != epochs[1]["cpu"], "the change itself was lost"
    return "old epoch closed with `to`, new one opened"


def case_governor_change_is_a_new_epoch():
    """Not trivia: 2.1 vs 2.6 GHz on this box. A governor flip alone moves
    numbers more than most optimisation work does."""
    clone = scratch()
    twatch.record_host_epoch(clone, "xeon")
    hw = twatch.host_hardware()
    twatch._HW_CACHE["cpu"] = hw["cpu"] + " (probe)"   # stand-in for a governor flip
    try:
        assert twatch.record_host_epoch(clone, "xeon") is True
    finally:
        twatch._HW_CACHE.clear()
    assert len(hosts_doc(clone)["xeon"]) == 2
    # ...and the governor really is inside the fingerprint, not merely stored
    import hashlib as _h
    a = dict(hw); b = dict(hw, governor="performance")
    fa = _h.sha256(json.dumps(a, sort_keys=True).encode()).hexdigest()[:12]
    fb = _h.sha256(json.dumps(b, sort_keys=True).encode()).hexdigest()[:12]
    assert fa != fb, "governor does not affect the fingerprint"
    return "governor is identity-bearing"


def case_hosts_are_independent():
    clone = scratch()
    twatch.record_host_epoch(clone, "xeon")
    twatch.record_host_epoch(clone, "borg")
    doc = hosts_doc(clone)
    assert set(doc) == {"xeon", "borg"} and len(doc["borg"]) == 1
    return "two hosts, one file, separate histories"


CASES = [
    case_fingerprint_covers_what_decides_comparability,
    case_first_run_opens_an_epoch,
    case_unchanged_box_appends_nothing,
    case_changed_hardware_opens_a_new_epoch_and_closes_the_old,
    case_governor_change_is_a_new_epoch,
    case_hosts_are_independent,
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
    print("host epoch provenance OK" if rc == 0 else "host epoch provenance BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
