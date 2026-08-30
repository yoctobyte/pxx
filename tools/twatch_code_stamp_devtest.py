#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a published report must name the CODE that produced it.

A tstate report already names the sha it TESTED. It said nothing about the
watcher code that produced it — and those two diverge at exactly one moment: when
a watcher fix lands.

A daemon holds its code from start, so `git pull` in the clone does not change
what is running. The clone can be current while the process is hours behind, and
every report it writes looks entirely healthy. Measured 2026-08-30: the
step-routing fix landed at `ae26693a3` (05:06) and IS an ancestor of the tested
sha; at 05:28 the daemon filed five regressions with no failing step and a wrong
lane, because the running process predated it. Two agents then spent an hour
reasoning about whether the CLONE was behind — which is the only staleness the
reports could express. **You reason inside the failure modes your instrument can
name, and the one it cannot name does not read as an omission; it reads as not
having happened.**

WHY A CONTENT HASH OF `__file__` AND NOT A GIT SHA. git answers what is ON DISK,
and the entire failure is on-disk disagreeing with in-memory. Only the bytes this
interpreter actually loaded can answer "what is running", and only at import.

Run: tools/twatch_code_stamp_devtest.py   (exit 0 = pass)
"""
import importlib.util
import io
import json
import os
import re
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def load():
    spec = importlib.util.spec_from_file_location(
        "tw_probe", os.path.join(HERE, "twatch.py"))
    m = importlib.util.module_from_spec(spec)
    argv = sys.argv
    sys.argv = ["twatch.py"]
    try:
        spec.loader.exec_module(m)
    except SystemExit:
        pass
    finally:
        sys.argv = argv
    return m


tw = load()


class FakeClone(object):
    def __init__(self, path):
        self.path = path


def t_the_watcher_can_identify_itself():
    assert re.fullmatch(r"[0-9a-f]{12}", tw.WATCHER_CODE or ""), (
        "WATCHER_CODE is %r — the watcher cannot say what code it is running, "
        "which is the whole hole this closes" % tw.WATCHER_CODE)
    return "WATCHER_CODE = %s" % tw.WATCHER_CODE


def t_it_is_the_hash_of_the_loaded_file():
    """Not of some other file, and not a constant somebody forgot to update."""
    assert tw.WATCHER_CODE == tw.file_id(os.path.join(HERE, "twatch.py")), (
        "WATCHER_CODE does not match tools/twatch.py's content — it is "
        "identifying something other than the code that is running")
    assert tw.WATCHER_CODE != tw.file_id(os.path.join(HERE, "testmgr.py")), \
        "twatch and testmgr hash the same, so the field distinguishes nothing"
    return "matches twatch.py, differs from testmgr.py"


def t_the_id_is_content_based():
    d = tempfile.mkdtemp(prefix="codestamp_")
    try:
        a, b = os.path.join(d, "a"), os.path.join(d, "b")
        io.open(a, "w").write("same\n")
        io.open(b, "w").write("same\n")
        assert tw.file_id(a) == tw.file_id(b), \
            "identical content hashed differently — the id is not content-based"
        io.open(b, "w").write("different\n")
        assert tw.file_id(a) != tw.file_id(b), \
            "changed content did not change the id, so a fix landing is invisible"
    finally:
        shutil.rmtree(d, ignore_errors=True)
    return "same content -> same id; changed -> changed"


def t_an_unreadable_file_does_not_raise():
    """This runs inside the publish path. It must never be the thing that kills
    a daemon mid-report."""
    assert tw.file_id("/nonexistent/twatch.py") == "?", \
        "an unreadable file did not degrade to '?'"
    return "missing file -> '?', no exception"


def t_save_state_stamps_the_report():
    d = tempfile.mkdtemp(prefix="codestamp_")
    try:
        os.makedirs(os.path.join(d, tw.TSTATE_REL))
        os.makedirs(os.path.join(d, "tools"))
        io.open(os.path.join(d, "tools/testmgr.py"), "w").write("# fake\n")
        tw.save_state(FakeClone(d), "testhost", {"host": "testhost"})
        st = json.load(io.open(os.path.join(d, tw.TSTATE_REL, "testhost.json")))
        assert "watcher" in st, (
            "save_state published a report with no producer field — every "
            "publish path goes through here, so this is the one place it "
            "cannot be forgotten")
        assert st["watcher"]["twatch"] == tw.WATCHER_CODE, \
            "the stamped twatch id is not this process's: %r" % st["watcher"]
        assert st["watcher"]["testmgr"] == tw.file_id(
            os.path.join(d, "tools/testmgr.py")), \
            "testmgr was hashed from somewhere other than the clone"
    finally:
        shutil.rmtree(d, ignore_errors=True)
    return "watcher.twatch and watcher.testmgr both published"


def t_the_stamp_carries_no_timestamp():
    """THE DESIGN DECISION MOST LIKELY TO BE UNDONE BY A HELPFUL EDIT.

    The field must change when the CODE changes and at no other moment. Add a
    start time and every restart becomes a state change: the tracked file goes
    dirty, the daemon publishes to un-wedge itself, and the signal ("the code
    changed") drowns in churn ("it restarted"). Two writes of the same state
    must be byte-identical."""
    d = tempfile.mkdtemp(prefix="codestamp_")
    try:
        os.makedirs(os.path.join(d, tw.TSTATE_REL))
        os.makedirs(os.path.join(d, "tools"))
        io.open(os.path.join(d, "tools/testmgr.py"), "w").write("# fake\n")
        p = os.path.join(d, tw.TSTATE_REL, "testhost.json")
        tw.save_state(FakeClone(d), "testhost", {"host": "testhost"})
        first = io.open(p).read()
        tw.save_state(FakeClone(d), "testhost", {"host": "testhost"})
        second = io.open(p).read()
        assert first == second, (
            "two writes of identical state differ, so something time-varying "
            "got into the stamp — every restart now dirties a tracked file")
        blob = json.loads(first)["watcher"]
        for k in blob:
            assert "time" not in k and "start" not in k and "date" not in k, \
                "the stamp gained a time-like field %r" % k
    finally:
        shutil.rmtree(d, ignore_errors=True)
    return "idempotent: identical state -> identical bytes"


def t_a_filed_stub_names_the_code_that_filed_it():
    """The ticket is where a confused reader actually looks."""
    src = io.open(os.path.join(HERE, "twatch.py"), encoding="utf-8").read()
    assert "auto-filed by Track T watcher, host %s, twatch `%s`" in src, (
        "the auto-filed stub header no longer names the twatch code — a "
        "mis-laned ticket then cannot be dated against a known fix")
    return "stub header names twatch"


TESTS = [t_the_watcher_can_identify_itself,
         t_it_is_the_hash_of_the_loaded_file,
         t_the_id_is_content_based,
         t_an_unreadable_file_does_not_raise,
         t_save_state_stamps_the_report,
         t_the_stamp_carries_no_timestamp,
         t_a_filed_stub_names_the_code_that_filed_it]


def main():
    bad = 0
    for t in TESTS:
        try:
            print("  ok   %-50s %s" % (t.__name__, t()))
        except Exception as e:  # noqa: BLE001
            bad += 1
            print("  FAIL %-50s %s" % (t.__name__, fail_detail(e)))
    print("  %d guard(s), %d red" % (len(TESTS), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
