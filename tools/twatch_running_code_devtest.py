#!/usr/bin/env python3
"""devtest: --status reports when the DAEMON's code is behind its own disk.

A pushed fix is not a live fix. Between `git push` and observable behaviour
sits a resident process that loaded its source at start time, and "landed on
origin, pulled into the clone, passed its guards" is indistinguishable from
live unless something compares the running image.

It hid three fixes on 2026-08-26, noticed only because one added a field whose
absence showed up in a report. It recurred on 2026-08-27: a scheduler fix was
pushed, announced as live, and the daemon had been on older code for hours.

code_fp was already published for exactly this question; the gap was that
somebody had to remember to ask. This guards that --status asks, and — equally
important — that it stays SILENT when it cannot tell, since a confident wrong
answer is worse here than no answer.
"""
import io, json, os, sys, contextlib, tempfile, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

fails = []
checks = 0


def check(cond, what):
    global checks
    checks += 1
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        fails.append(what)


def run(clone):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        tw.report_running_code(clone)
    return buf.getvalue()


def make_clone(tmp, running_fp, source_text):
    os.makedirs(os.path.join(tmp, ".testmgr"), exist_ok=True)
    os.makedirs(os.path.join(tmp, "tools"), exist_ok=True)
    with open(os.path.join(tmp, tw.WATCH_REL), "w") as f:
        d = {"phase": "testing"}
        if running_fp is not None:
            d["code_fp"] = running_fp
        json.dump(d, f)
    with open(os.path.join(tmp, "tools", "twatch.py"), "w") as f:
        f.write(source_text)
    return tw.code_fingerprint(os.path.join(tmp, "tools", "twatch.py"))


def main():
    with tempfile.TemporaryDirectory(prefix="twrc.") as tmp:
        # DRIFT: running image differs from the file on disk -> must warn.
        make_clone(tmp, "deadbeef0000", "print('v2')\n")
        out = run(tmp)
        check("DAEMON is running" in out, "drift is reported")
        check("deadbeef0000" in out, "the RUNNING fingerprint is named")
        check("trackt restart" in out, "the remedy is named, not just the fault")

        # MATCH: no warning at all. A quiet check is the common case and must
        # not add noise, or --status gets skimmed.
        disk = make_clone(tmp, None, "print('v3')\n")
        with open(os.path.join(tmp, tw.WATCH_REL), "w") as f:
            json.dump({"code_fp": disk}, f)
        check(run(tmp) == "", "a matching image prints NOTHING")

    with tempfile.TemporaryDirectory(prefix="twrc2.") as tmp:
        # CANNOT TELL: each of these must stay silent rather than guess.
        check(run(tmp) == "", "no watch.json at all -> silent")
        os.makedirs(os.path.join(tmp, ".testmgr"), exist_ok=True)
        with open(os.path.join(tmp, tw.WATCH_REL), "w") as f:
            f.write("{not json")
        check(run(tmp) == "", "an unreadable watch.json -> silent, not an error")
        with open(os.path.join(tmp, tw.WATCH_REL), "w") as f:
            json.dump({"phase": "testing"}, f)          # no code_fp
        check(run(tmp) == "", "a watch.json with no code_fp -> silent")
        os.makedirs(os.path.join(tmp, "tools"), exist_ok=True)
        with open(os.path.join(tmp, tw.WATCH_REL), "w") as f:
            json.dump({"code_fp": "abc123abc123"}, f)
        check(run(tmp) == "", "code_fp but no twatch.py on disk -> silent")

        # THE RESTART FALSE POSITIVE. watch.json is a RECORD, not live state:
        # the stopping daemon's last write survives it, and a fresh daemon has
        # not called set_phase yet. Measured 2026-08-28, 16 seconds after a
        # restart -- this check printed the OLD daemon's fingerprint and told
        # the operator to restart the daemon they had just restarted. That is
        # the worst moment for it to be wrong: a restart is exactly when
        # somebody runs it, precisely to confirm the fix went live.
        make_clone(tmp, "deadbeef0000", "print('v9')\n")
        with open(os.path.join(tmp, tw.WATCH_REL), "w") as f:
            json.dump({"phase": "stopped", "code_fp": "deadbeef0000"}, f)
        check(run(tmp) == "",
              "phase=stopped -> silent; a farewell note says nothing about a "
              "successor")
        with open(os.path.join(tmp, tw.WATCH_REL), "w") as f:
            json.dump({"phase": "testing", "code_fp": "deadbeef0000",
                       "pid": 2 ** 22 - 1}, f)   # above any live pid_max
        check(run(tmp) == "",
              "a pid that no longer exists -> silent; the record outlived its "
              "writer")
        with open(os.path.join(tmp, tw.WATCH_REL), "w") as f:
            json.dump({"phase": "testing", "code_fp": "deadbeef0000",
                       "pid": os.getpid()}, f)
        check("DAEMON is running" in run(tmp),
              "a LIVE pid with a drifting fingerprint still warns — the pid "
              "check must not swallow the real case")
        with open(os.path.join(tmp, tw.WATCH_REL), "w") as f:
            json.dump({"phase": "testing", "code_fp": "deadbeef0000"}, f)
        check("DAEMON is running" in run(tmp),
              "no pid recorded at all -> still warns, rather than going silent "
              "on every older watch.json")

    check(run("") == "", "an empty clone hint -> silent")
    check(run("/nonexistent/path/xyz") == "", "a bogus clone path -> silent")

    print("\n%s (%d checks, %d failed)"
          % ("FAIL" if fails else "PASS", checks, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
