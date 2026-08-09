#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""trackt — Track T one-stop launcher.

One tool for the whole watcher stack: status, daemon start/stop, live
progress view, manual runs, box setup + git-access verification, config,
log tail, web UI.  Everything is a thin frontend over the state files the
engine publishes (.testmgr/live.json, .testmgr/watch.json,
devdocs/progress/tstate/**) — the daemon (tools/twatch.py) stays the engine.

  trackt                 ONE STOP: starts daemon + web UI if not running
                         (opt out: --no-daemon / --no-web / --no-attach),
                         prints the local URL, shows status, attaches live
  trackt start|stop|restart|status
  trackt watch           live progress (Ctrl-C detaches, daemon keeps going);
                         each finished suite run leaves a timestamped result
                         line incl. commit hash (--no-sha to omit it)
  trackt run [tier]      manual testmgr run in THIS checkout (default quick)
  trackt setup           box prerequisites + git access + role profile wizard.
                         The role is DETECTED (dedicated / limited /
                         restricted / native-oracle) and proposed with
                         Enter-to-accept; with no TTY the detected role is
                         applied unprompted, never a blanket 'dedicated'.
                         Also run on the first `trackt up` if unconfigured.
  trackt config [k [v]]  show / set daemon config (applies live where safe)
  trackt log             follow the daemon log
  trackt web on|off      enable/disable the Flask UI (spawned by start)
  trackt dashboard       (re)generate the static tstate/*.html pages from the
                         committed data (one-liner; the html is gitignored)
  trackt health [--json] is this watcher trustworthy right now? OK/DEGRADED/
                         DOWN + exit code; detects a daemon that is alive but
                         WEDGED, which coverage-based --status cannot
  trackt install         make the daemon permanent (systemd user unit +
                         linger). EXPLICIT on purpose: the default is an
                         interactive foreground daemon an admin watches.
                         Prints exactly what it changes. `trackt uninstall`
                         reverses it.

The watcher clone is found via --clone, $TRACKT_CLONE, ~/.config/trackt.path,
or ~/trackt-watch.  `trackt run` never touches the clone — it tests the
checkout you call it from.
"""

import argparse
import json
import os
import platform
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKOUT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import twatch                                            # noqa: E402

TIERS = ("quick", "native", "limited", "full", "opt")
ISATTY = sys.stdout.isatty()
RED = "\033[31;1m" if ISATTY else ""
GRN = "\033[32m" if ISATTY else ""
YEL = "\033[33m" if ISATTY else ""
DIM = "\033[2m" if ISATTY else ""
OFF = "\033[0m" if ISATTY else ""


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def clone_dir(cli):
    if cli:
        return os.path.abspath(os.path.expanduser(cli))
    if os.environ.get("TRACKT_CLONE"):
        return os.path.abspath(os.path.expanduser(os.environ["TRACKT_CLONE"]))
    p = os.path.expanduser("~/.config/trackt.path")
    if os.path.exists(p):
        with open(p) as f:
            return os.path.abspath(os.path.expanduser(f.read().strip()))
    return os.path.expanduser("~/trackt-watch")


def logpath(clone):
    return clone.rstrip("/") + ".log"


def pid_alive(pid, needle):
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            return needle in f.read().decode(errors="replace")
    except OSError:
        return False


def is_daemon(pid, clone):
    """Is `pid` REALLY the watcher daemon for `clone`?

    Parse argv rather than substring-matching /proc/<pid>/cmdline. A plain
    `"twatch.py" in cmdline` test matches anything that merely MENTIONS the
    daemon -- a `tail -f`/`grep` on its log, an editor, a monitoring loop that
    greps for it. 2026-07-20 exactly that happened: a health-check loop whose
    own command line contained `twatch.py --clone` was mistaken for the
    daemon, so `trackt restart` printed "daemon already running" and never
    started it. The watcher stayed down and status kept reporting RUNNING --
    a silent outage, which is the one thing this check must never cause.

    The real daemon is `<python> <...>/twatch.py --clone <clone>`, so require
    argv[1] to BE the script and the clone to be a real argument.
    """
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            argv = [a for a in f.read().decode(errors="replace").split("\0") if a]
    except OSError:
        return False
    if len(argv) < 2 or "python" not in os.path.basename(argv[0]):
        return False
    return argv[1].endswith("twatch.py") and clone in argv


def daemon_pid(clone):
    w = read_json(os.path.join(clone, twatch.WATCH_REL))
    pid = w.get("pid")
    if pid and w.get("phase") != "stopped" and is_daemon(pid, clone):
        return pid, w
    for p in os.listdir("/proc"):     # daemon older than watch.json support
        if p.isdigit() and is_daemon(int(p), clone):
            return int(p), w
    return None, w


def web_pid(clone):
    p = read_json(os.path.join(clone, ".testmgr", "web.json")).get("pid")
    return p if p and pid_alive(p, "twatch_web.py") else None


# ---------------------------------------------------------------- status ---
def fmt_age(ts):
    if not ts:
        return "?"
    s = int(time.time() - ts)
    return "%ds" % s if s < 120 else "%dmin" % (s // 60) if s < 7200 \
        else "%dh" % (s // 3600)


def cmd_up(clone, a):
    """Default command: bring everything up FOREGROUND, opt out via flags.
    Ctrl-C / exit stops what we started — running on in the background needs
    explicit permission (the prompt, or `trackt start`)."""
    if not os.path.isdir(clone):
        print("no watcher clone at %s — running setup" % clone)
        if cmd_setup(clone, fetch_corpus=False):
            return 1
    # first run on this box: pick a role profile before the daemon starts, so
    # its very first gate already honours the box's resource ceilings.
    configure_profile(clone)
    preexisting, _ = daemon_pid(clone)
    if not a.no_daemon and not preexisting:
        if cmd_start(clone, a.remote, local_code=a.local_code):
            return 1
    conf = twatch.load_conf(clone)
    if not a.no_web and conf.get("web", True):
        if not web_pid(clone):
            start_web(clone, conf)
        else:
            print("web UI: http://127.0.0.1:%s" % conf["web_port"])
    cmd_status(clone, attach_ok=False)
    if a.no_attach or not ISATTY:
        return 0
    try:
        watch_loop(clone)
        return 0
    except KeyboardInterrupt:
        print()
        # daemon we just started: default STOP.  Daemon that was already
        # running in the background (someone said `trackt start` before):
        # default KEEP — attaching must not kill standing coverage by
        # accident.
        default_keep = bool(preexisting)
        try:
            ans = input("keep daemon + web running in background? [%s] "
                        % ("Y/n" if default_keep else "y/N")).strip().lower()
        except (EOFError, KeyboardInterrupt):
            ans = ""
        keep = (ans or ("y" if default_keep else "n")).startswith("y")
        if keep:
            print("left running — `trackt stop` when done.")
            return 0
        return cmd_stop(clone)


def print_tstate(clone):
    """The tstate summary (verdicts, open regressions, UP/DOWN), from ORIGIN.

    Both obvious sources lie:

      * the DEV CHECKOUT's tstate files are only as fresh as your last `git pull`
        — so trackt cheerfully reported "DOWN — untested for 151 min" while the
        daemon was visibly finishing runs two lines above, because the checkout
        had not pulled since;
      * the CLONE's worktree is DETACHED at the sha under test for most of every
        cycle (and at an ancient one during a bisect), so its tstate files are
        whatever that commit happened to contain.

    The daemon publishes to origin/master, so that is the only honest source. Read
    the tstate blobs straight out of it, and date the commits from it too. Falls
    back to the worktree when there is no network / no origin.
    """
    repo = clone if os.path.isdir(os.path.join(clone, ".git")) else CHECKOUT
    try:
        # --no-write-fetch-head: `trackt status` is run repeatedly (and from
        # watch loops) in a repo where a pull may be in flight; see Clone.fetch.
        subprocess.run(["git", "fetch", "--quiet", "--no-write-fetch-head",
                        "origin"], cwd=repo,
                       timeout=30, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        tmp = tempfile.mkdtemp(prefix="trackt-tstate.")
        dst = os.path.join(tmp, twatch.TSTATE_REL)
        os.makedirs(dst, exist_ok=True)
        names = subprocess.run(
            ["git", "ls-tree", "-r", "--name-only", "origin/master",
             twatch.TSTATE_REL + "/"], cwd=repo, capture_output=True, text=True,
            timeout=30).stdout.split()
        for n in names:
            if not n.endswith(".json") or "/" in n[len(twatch.TSTATE_REL) + 1:]:
                continue        # host state files only; reports/ etc not needed
            blob = subprocess.run(["git", "show", "origin/master:" + n], cwd=repo,
                                  capture_output=True, timeout=30).stdout
            with open(os.path.join(dst, os.path.basename(n)), "wb") as f:
                f.write(blob)
        return twatch.status(repo, grace_min=45, tdir=dst, ref="origin/master")
    except (subprocess.SubprocessError, OSError):
        # offline or no origin: the worktree is all we have. Stale beats silent.
        fallback = CHECKOUT if os.path.isdir(os.path.join(CHECKOUT, "devdocs")) else clone
        return twatch.status(fallback, grace_min=45)


def print_pubhealth(clone):
    """Publish health: the line that was MISSING on 2026-07-15. A running daemon
    that cannot publish (repeated drops from a conflict it can't clear) used to
    look identical to a healthy quiet one — the only hint was the coverage line
    drifting to a vague 'DOWN' while 'daemon RUNNING' sat right above it. Make
    the failure loud and name the reason."""
    h = read_json(os.path.join(clone, twatch.PUBHEALTH_REL))
    if not h:
        return
    drops = h.get("consec_drops", 0)
    behind = h.get("behind")
    behind_txt = "; %d behind origin" % behind if behind else ""
    if drops:
        print("  publish: %s⚠ BLOCKED%s — %d consecutive drop%s over %s "
              "(last: %s)%s"
              % (RED, OFF, drops, "" if drops == 1 else "s",
                 fmt_age(h.get("drops_since")),
                 h.get("last_reason") or "conflict", behind_txt))
        print("           %sstale verdicts are being discarded each cycle — a "
              "human edit to a co-edited tstate file (bench.tsv) usually clears "
              "on its own; if it persists, inspect the clone%s" % (DIM, OFF))
    elif h.get("last_push_ts"):
        print("  publish: %sok%s — last push %s ago%s"
              % (GRN, OFF, fmt_age(h["last_push_ts"]), behind_txt))


def cmd_status(clone, attach_ok=True):
    conf = twatch.load_conf(clone)
    pid, w = daemon_pid(clone)
    print("trackt — Track T (clone %s)" % clone)
    if not os.path.isdir(clone):
        print("  %sclone missing%s — run: trackt setup" % (RED, OFF))
        return 1
    print("  config : tier=%s fast=%s interval=%ss autoticket=%s web=%s%s"
          % (conf["tier"], conf["fast_tier"], conf["interval"],
             "on" if conf["autoticket"] else "off",
             "on(:%s)" % conf["web_port"] if conf["web"] else "off",
             "" if not web_pid(clone) else " [serving]"))
    if pid:
        # The phase in watch.json is only meaningful if the daemon we FOUND is
        # the one that wrote it. On shutdown the old daemon leaves
        # phase="stopped" behind; a freshly started daemon is then discovered by
        # the /proc scan before it has written its own first phase — and the
        # status line reported "RUNNING pid 2616079 — stopped", which is a
        # contradiction, and exactly the kind of thing that makes a watcher
        # untrustworthy to read.
        fresh = w.get("pid") == pid and w.get("phase") not in (None, "stopped")
        phase = w.get("phase", "?") if fresh else "starting…"
        extra = " ".join("%s=%s" % (k, w[k]) for k in ("sha", "tier", "head")
                         if w.get(k)) if fresh else ""
        age = "%s ago" % fmt_age(w.get("ts")) if fresh else "no phase written yet"
        print("  daemon : %sRUNNING%s pid %d — %s %s (%s)"
              % (GRN, OFF, pid, phase, extra, age))
    else:
        print("  daemon : %sSTOPPED%s — trackt start" % (RED, OFF))
    print_pubhealth(clone)
    print_tstate(clone)
    if attach_ok and pid and w.get("phase") == "testing":
        print("%s-- run in progress, attaching (Ctrl-C detaches) --%s" % (DIM, OFF))
        cmd_watch(clone)
    return 0


# ----------------------------------------------------------------- watch ---
def runs_files(clone):
    tsdir = os.path.join(clone, twatch.TSTATE_REL)
    try:
        names = sorted(os.listdir(tsdir))
    except OSError:
        return []
    return [os.path.join(tsdir, n) for n in names
            if n.startswith("runs-") and n.endswith(".ndjson")]


def emit_completions(clone, pos, show_sha=True):
    """Print a persistent timestamped line for every suite run completed
    since the last call — new rows in tstate/runs-<host>.ndjson, the
    per-run archive twatch appends to when a gate finishes.

    Rows are identified by CONTENT, not by byte offset. Offsets cannot survive
    this file: it is git-managed, and every publish does add/commit/pull
    --rebase, during which git rewrites it — briefly shrinking it to the
    remote's version, then regrowing it with our row. A shrink rewinds the
    recorded offset, and the regrow then re-emits every row after that point.
    That is the duplicated blocks in the live view: the same completed runs
    printed again and again, one more copy each publish.
    """
    emitted = False
    for path in runs_files(clone):
        try:
            with open(path) as f:
                rows = f.read().splitlines()
        except OSError:
            continue
        seen = pos.setdefault(path, set())
        first_sight = not seen
        host = os.path.basename(path)[len("runs-"):-len(".ndjson")]
        for ln in rows:
            key = ln.strip()
            if not key or key in seen:
                continue
            seen.add(key)
            if first_sight:
                continue    # prime: report only runs finishing from NOW on
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            col = RED if r.get("verdict") == "RED" else GRN
            line = "[%s] %s %s %s%s%s %ds" % (
                r.get("date", "?"), host, r.get("tier", "?"),
                col, r.get("verdict", "?"), OFF, r.get("wall", 0))
            if show_sha and r.get("sha"):
                line += " " + r["sha"][:12]
            if r.get("new_red"):
                line += " %sNEW-RED:%s%s" % (RED, ",".join(r["new_red"][:5]), OFF)
            if r.get("fixed"):
                line += " %sFIXED:%s%s" % (GRN, ",".join(r["fixed"][:5]), OFF)
            print("\r\033[K  " + line)
            emitted = True
    return emitted


def render_live(clone, w, live, last_reds, seen_phase=None):
    phase = w.get("phase", "?")
    # A phase CHANGE gets a persistent line. The in-place line (\r + erase, no
    # newline) is right for a progress bar that updates every second, but it
    # means a phase the daemon spent four minutes in — bench, fuzz, bisect —
    # is silently overwritten by whatever comes next and leaves no trace at all.
    # The user saw "benchmarking" for minutes and then watched it disappear.
    if seen_phase is not None and phase != seen_phase.get("phase"):
        if seen_phase.get("phase") is not None:
            prev, since = seen_phase["phase"], seen_phase.get("since")
            took = " (%ds)" % int(time.time() - since) if since else ""
            print("\r\033[K  %s%s%s done%s" % (DIM, prev, OFF, DIM + took + OFF))
        seen_phase["phase"] = phase
        seen_phase["since"] = time.time()

    if phase != "testing" or not live:
        line = "phase %-12s %s" % (phase, DIM + fmt_age(w.get("ts")) + " ago" + OFF)
        sys.stdout.write("\r\033[K  " + line if ISATTY else "  " + line + "\n")
        sys.stdout.flush()
        return last_reds
    reds = live.get("red", [])
    srcs = live.get("red_src", {})
    for r in reds:
        if r not in last_reds:
            src = srcs.get(r, "")
            print("\r\033[K  %sRED %s%s%s" % (
                RED, r, OFF, "  " + DIM + src + OFF if src else ""))
    pct = live.get("pct", 0)
    bar = ""
    if ISATTY:
        fill = int(pct / 5)
        bar = "[" + "#" * fill + "-" * (20 - fill) + "] "
    eta = live.get("eta")
    line = "%s %s %s%5.1f%% %s(%d/%d) %ds elapsed%s%s" % (
        w.get("sha", "")[:10], live.get("tier", "?"), bar, pct,
        DIM, live.get("done", 0), live.get("total", 0),
        live.get("elapsed", 0),
        " eta ~%ds" % eta if eta else "", OFF)
    if reds:
        line += " %s%d RED%s" % (RED, len(reds), OFF)
    sys.stdout.write("\r\033[K  " + line if ISATTY else "  " + line + "\n")
    sys.stdout.flush()
    return set(reds) | set(last_reds)


def watch_loop(clone, show_sha=True):
    print("%s  live view — Ctrl-C to leave (you'll be asked about the daemon)%s"
          % (DIM, OFF))
    seen = set()
    pos = {}
    phase = {"phase": None, "since": None}
    emit_completions(clone, pos, show_sha)   # prime: print nothing for old rows
    while True:
        pid, w = daemon_pid(clone)
        live = read_json(os.path.join(clone, ".testmgr", "live.json"))
        if not pid:
            print("\n  daemon not running.")
            return 1
        # A completed gate is exactly when the tstate summary changes (verdict,
        # NEW-RED/FIXED, UP/DOWN). Re-render it then — printing it once at
        # startup left it stale for the whole session, so the "DOWN, untested
        # for 47 min" you were reading could be minutes out of date.
        if emit_completions(clone, pos, show_sha):
            print_tstate(clone)
        seen = render_live(clone, w, live, seen, phase)
        time.sleep(1)


def cmd_watch(clone, show_sha=True):
    """Explicit `trackt watch`: view only — Ctrl-C detaches, never stops."""
    try:
        return watch_loop(clone, show_sha)
    except KeyboardInterrupt:
        print("\n  detached — daemon keeps running (trackt stop to stop it).")
        return 0


# ------------------------------------------------------------- lifecycle ---
def daemon_script(clone, local_code=False):
    """WHICH twatch.py the daemon runs.

    The clone's own copy, not this checkout's. Launching from HERE means the
    daemon's code comes from a working tree that agents edit live, while the
    code under test comes from the clone -- so an uncommitted edit silently
    decides what the watcher executes on its next start. That is the code-side
    twin of the 2026-07-07 dirty-clone incident, which is why the watcher got a
    dedicated clone in the first place; the clone fixed the DATA side only.

    Running the clone's copy makes "restart to pick up a fix" mean "pull, then
    restart" -- the watcher runs committed code that arrived through git like
    everything else. --local-code opts back into this checkout's copy for
    deliberately testing an uncommitted change.
    """
    if local_code:
        return os.path.join(HERE, "twatch.py")
    inclone = os.path.join(clone, "tools", "twatch.py")
    if os.path.exists(inclone):
        return inclone
    # a clone too old (or mid-setup) to carry it: fall back rather than refuse
    # to start, but say so -- a silent fallback would defeat the whole point.
    print("%swarning%s: %s has no tools/twatch.py — falling back to this "
          "checkout's copy (uncommitted edits WILL be live)" % (RED, OFF, clone))
    return os.path.join(HERE, "twatch.py")


def ensure_clone_on_branch(clone, branch="master"):
    """Put the clone back on its branch before the daemon is launched from it.

    `daemon_script` deliberately runs the CLONE's copy of twatch.py, so that
    "restart to pick up a fix" means "pull, then restart" and the watcher runs
    committed code. But the clone is DETACHED at the sha under test for most of
    every cycle — and *always* after a crash, which is exactly when someone
    restarts it. Launching then runs that sha's twatch.py: an arbitrary OLD
    version of the watcher's own code, with none of the fix that prompted the
    restart.

    Measured 2026-08-04: a crash left the clone detached at `ac03897df`, so
    `trackt up` relaunched the very code that had just crashed, which
    re-created the file it crashed on. Two identical outages before the cause
    was visible, because the log's traceback showed the CURRENT file's source
    lines against the OLD file's line numbers.

    Returns False when the clone cannot be made current — the caller should
    refuse rather than start something arbitrary.
    """
    git = ["git", "-C", clone]
    try:
        detached = subprocess.run(git + ["symbolic-ref", "-q", "HEAD"],
                                  capture_output=True, text=True,
                                  timeout=30).returncode != 0
        if detached:
            print("trackt: clone is detached (mid-test, or a crash left it "
                  "there) — returning it to %s so the daemon runs CURRENT "
                  "code, not the tested sha's" % branch)
            r = subprocess.run(git + ["checkout", branch], capture_output=True,
                               text=True, timeout=60)
            if r.returncode:
                print("trackt: cannot check out %s in %s:\n%s"
                      % (branch, clone, (r.stderr or "").strip()))
                return False
        subprocess.run(git + ["pull", "--ff-only", "--quiet", "origin", branch],
                       capture_output=True, timeout=120)
    except (subprocess.SubprocessError, OSError) as e:
        print("trackt: could not verify the clone's checkout (%s) — starting "
              "anyway, but the daemon may be running old code" % e)
    return True


def cmd_start(clone, remote=None, web=True, local_code=False):
    if not os.path.isdir(clone):
        if not remote:
            print("no clone at %s — trackt setup, or: trackt start --remote <url>"
                  % clone)
            return 1
    pid, _ = daemon_pid(clone)
    if pid:
        print("daemon already running (pid %d)" % pid)
        return 0
    if not local_code and os.path.isdir(clone) and \
            not ensure_clone_on_branch(clone):
        print("trackt: refusing to start — the daemon would run whatever sha "
              "the clone happens to be sitting on")
        return 1
    lg = open(logpath(clone), "a")
    script = daemon_script(clone, local_code)
    if local_code:
        print("running THIS checkout's twatch.py (--local-code): %s" % script)
    cmd = [sys.executable, script, "--clone", clone]
    if remote:
        cmd += ["--remote", remote]
    p = subprocess.Popen(cmd, stdout=lg, stderr=subprocess.STDOUT,
                         start_new_session=True)
    lg.close()
    time.sleep(2)
    if p.poll() is not None:
        print("%sdaemon died at startup%s — tail %s" % (RED, OFF, logpath(clone)))
        return 1
    print("daemon started (pid %d, log %s)" % (p.pid, logpath(clone)))
    conf = twatch.load_conf(clone)
    if conf.get("web"):
        start_web(clone, conf)
    return 0


def cmd_stop(clone):
    rc = 0
    pid, _ = daemon_pid(clone)
    if not pid:
        print("daemon not running")
    else:
        os.kill(pid, signal.SIGTERM)
        print("SIGTERM sent (pid %d) — aborting any running gate" % pid)
        for _ in range(60):
            if not pid_alive(pid, "twatch.py"):
                break
            time.sleep(1)
        else:
            # Escalate rather than hand the problem back. "kill -9 N by hand" is
            # not a stop command, it is homework -- and it leaves the user
            # staring at a prompt that looks hung, which is how this started.
            print("%sno exit after 60s — SIGKILL%s" % (RED, OFF))
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
            time.sleep(2)
            # A SIGKILLed daemon cannot tear down its own testmgr child, and a
            # testmgr re-execs itself into a systemd scope (reparented to pid 1),
            # so it would survive as an orphan, hold memory, and starve the next
            # run. Reap it here.
            for p in os.listdir("/proc"):
                if p.isdigit() and pid_alive(int(p), "testmgr.py") \
                        and pid_alive(int(p), clone):
                    try:
                        os.killpg(os.getpgid(int(p)), signal.SIGKILL)
                        print("reaped orphaned testmgr (pid %s)" % p)
                    except OSError:
                        pass
        if pid_alive(pid, "twatch.py"):
            print("%sdaemon still alive (pid %d)%s" % (RED, OFF, pid))
            rc = 1
        else:
            print("daemon stopped")
    wp = web_pid(clone)
    if wp:
        os.kill(wp, signal.SIGTERM)
        print("web UI stopped (pid %d)" % wp)
    return rc


def start_web(clone, conf):
    try:
        import flask  # noqa: F401
    except ImportError:
        print("%sweb: flask not installed%s (pip install flask / apt install "
              "python3-flask) — daemon runs fine without it" % (YEL, OFF))
        return 1
    lg = open(logpath(clone), "a")
    p = subprocess.Popen([sys.executable, os.path.join(HERE, "twatch_web.py"),
                          "--clone", clone, "--port", str(conf["web_port"])],
                         stdout=lg, stderr=subprocess.STDOUT,
                         start_new_session=True)
    lg.close()
    twatch.write_json_atomic(os.path.join(clone, ".testmgr", "web.json"),
                             {"pid": p.pid, "port": conf["web_port"]})
    print("web UI: http://127.0.0.1:%s (pid %d)" % (conf["web_port"], p.pid))
    return 0


# ---------------------------------------------------------------- config ---
def cmd_config(clone, key=None, val=None):
    path = os.path.join(clone, twatch.CONF_NAME)
    conf = twatch.load_conf(clone)
    if key is None:
        print("config %s (missing keys = defaults; interval/autoticket/"
              "no_bisect apply to a running daemon, tier changes need "
              "trackt restart)" % path)
        for k in sorted(conf):
            v = conf[k]
            print("  %-18s = %s" % (k, "<set>" if "key" in k and v else v))
        return 0
    if key not in twatch.CONF_DEFAULTS and not key.startswith("anthropic"):
        print("unknown key %r (known: %s)" % (key, ", ".join(sorted(twatch.CONF_DEFAULTS))))
        return 1
    if val is None:
        print(conf.get(key, ""))
        return 0
    d = twatch.CONF_DEFAULTS.get(key)
    if isinstance(d, bool):
        val = val.lower() in ("1", "true", "on", "yes")
    elif isinstance(d, int):
        val = int(val)
    user = read_json(path)
    user[key] = val
    twatch.write_json_atomic(path, user)
    print("%s = %s" % (key, val))
    if key in ("tier", "fast_tier", "web", "web_port"):
        print("%s(takes effect on trackt restart)%s" % (DIM, OFF))
    return 0


# ----------------------------------------------------------------- setup ---
# Profiles the first-run wizard offers. Each is a set of overrides onto
# CONF_DEFAULTS (everything-on, dedicated). max_cores/max_mem_mb are filled in
# per-box at wizard time (they depend on this box's cpu/ram), so they're None
# here as "compute from the box".
PROFILES = {
    "dedicated": {
        "_blurb": "this box exists to test. Full matrix, all idle work "
                  "(opt/bench/fuzz), all cores. (a borg-style watcher box)",
        # all defaults — the box is ours
    },
    "limited": {
        "_blurb": "shares the box with other work. Full matrix but polite: "
                  "no spare-cycle fuzzing, leaves cores free, slower cadence.",
        "idle_fuzz": False, "interval": 120, "fuzz_backoff_minutes": 180,
        "_leave_cores": 2,          # cap = nproc - 2
    },
    "restricted": {
        "_blurb": "spare cycles only, minimal footprint. Own-arch fast "
                  "verdicts only (no heavy cross-matrix), no idle work, half "
                  "the cores. (a Pi that also serves web, etc.)",
        "tier": "native", "idle_opt": False, "idle_bench": False,
        "idle_fuzz": False, "interval": 300, "web": False,
        "_half_cores": True,        # cap = max(1, nproc//2)
        "_mem_frac": 0.5,           # cap mem to half the box
    },
    "native-oracle": {
        "_blurb": "a non-x86_64 box. Its unique value is running its OWN "
                  "architecture natively — the one thing QEMU cannot verify — "
                  "so: own-arch verdicts, no cross matrix, no idle work. "
                  "(an arm32/arm64 Pi, a riscv board)",
        # Not "restricted with a different name": restricted is a box we are
        # BORROWING (half its cores, it has other work). An oracle is dedicated
        # to this job, so it keeps its cores — what it must not do is spend
        # them on a cross matrix that x86 boxes already cover faster.
        "tier": "native", "idle_opt": False, "idle_bench": False,
        "idle_fuzz": False, "interval": 120, "web": False,
        "_mem_frac": 0.75,
    },
}


# Machines whose native run IS the thing being verified. Everything else is
# "some x86_64 box", where the interesting question is who else is using it.
X86 = ("x86_64", "amd64", "i686", "i386")


def total_ram_mb():
    """This box's RAM in MB, or 0 if /proc/meminfo cannot be read.

    Read here rather than borrowed: the wizard used to call
    `twatch.meminfo()`, which does not exist — that function lives in
    testmgr. The AttributeError was swallowed by a bare `except Exception`,
    so the wizard printed "0 MB" to the user AND `_write_profile`'s
    `if prof.get("_mem_frac") and total_mb` never fired, meaning the
    restricted profile's memory cap silently never existed.
    """
    try:
        with open("/proc/meminfo") as f:
            for ln in f:
                if ln.startswith("MemTotal:"):
                    return int(ln.split()[1]) >> 10        # kB -> MB
    except (OSError, ValueError, IndexError):
        pass
    return 0


def _has_desktop_session():
    """Is somebody logged in graphically on this box?

    Two sources because neither is sufficient: the env vars are absent when
    setup runs from cron or a bare ssh command even on a machine with an active
    desktop, and `loginctl` is absent on non-systemd boxes and inside
    containers. Either one saying yes is enough; both failing is treated as
    headless, which is the conservative answer for a ROLE decision (headless
    implies dedicated, and over-claiming a box the user is sitting at is the
    error that actually annoys anyone).
    """
    if any(os.environ.get(v) for v in
           ("DISPLAY", "WAYLAND_DISPLAY", "XDG_CURRENT_DESKTOP")):
        return True
    try:
        out = subprocess.run(["loginctl", "list-sessions", "--no-legend"],
                             capture_output=True, text=True, timeout=5).stdout
        for line in out.splitlines():
            sid = line.split()[0] if line.split() else ""
            if not sid:
                continue
            t = subprocess.run(["loginctl", "show-session", sid, "-p", "Type",
                                "--value"], capture_output=True, text=True,
                               timeout=5).stdout.strip()
            if t in ("x11", "wayland", "mir"):
                return True
    except (OSError, subprocess.SubprocessError):
        pass
    return False


def detect_role(nproc, total_mb):
    """Pick a profile from what this box IS. Returns (role, [reasons]).

    The discriminator is ARCHITECTURE first, not size. A non-x86_64 box is
    valuable because it runs its own arch natively — a fast ARM server should
    still be an oracle in role, and a weak x86 box makes a poor oracle no
    matter how slow it is; it is just a slow runner.

    Then, among x86_64 boxes, only CAPABILITY is detectable — a box too small
    to run the matrix without thrashing. Whether a big box is dedicated or
    shared is INTENT, and nothing on the machine reports it.

    A graphical session was tried as that proxy and dropped (user, 2026-08-02:
    "this box is considered dedicated. headless has little to do with that").
    It got both fleet boxes wrong in opposite ways for the same reason: xeon
    runs the matrix and has a desktop login, borg is the box a human works at
    and also has one. The signal is real but it answers a different question,
    so it is now REPORTED and never decides.

    Ties break toward `dedicated` deliberately. The two errors are not
    symmetric: dedicated on a shared box is loud and self-correcting — the
    machine gets busy, someone notices within minutes and runs `trackt config`
    — while limited on a watcher box is silent, and costs the fleet cores and
    spare-cycle fuzzing indefinitely, which is exactly what
    meta-t-dev-throughput-and-track-a-t-integration exists to stop.

    Used as the NON-INTERACTIVE default as well as the interactive proposal.
    The old code defaulted to 'dedicated' with no TTY regardless of the box,
    which is how a Pi provisioned headless over ssh — the most likely way one
    is ever set up — enrolled itself as a full-matrix fuzzing box. That case is
    caught by the architecture branch, not by the headless one.
    """
    mach = platform.machine().lower()
    reasons = ["%s, %d cores, %d MB" % (mach or "unknown-arch", nproc, total_mb)]
    model = ""
    try:                                  # Pi/board name, when the DT exposes it
        with open("/proc/device-tree/model", errors="replace") as f:
            model = f.read().strip("\x00 \t\n")
    except OSError:
        pass
    if model:
        reasons.append(model)
    if mach and mach not in X86:
        reasons.append("non-x86_64: its native run is what QEMU cannot verify")
        return "native-oracle", reasons
    if nproc < 4 or (total_mb and total_mb < 4096):
        reasons.append("small box: leave headroom rather than saturate it")
        return "limited", reasons
    reasons.append("x86_64 with room to work")
    if _has_desktop_session():
        # informational: it does NOT change the role, but the operator should
        # know the box will be worked hard while they are sitting at it
        reasons.append("NOTE a graphical session is present — if someone works "
                       "here, choose 'limited' or `trackt config max_cores N`")
    return "dedicated", reasons


def configure_profile(clone):
    """First-run wizard: write <clone>/twatch.conf from a role profile.

    Runs only when no conf exists yet. DETECTS the role and proposes it; the
    prompt is Enter-to-accept. Without a TTY it writes the detected role — not
    a blanket 'dedicated', which is what enrolled a headless Pi as a
    full-matrix fuzzing box.

    Always prints what was detected, why, and the caps that follow: a silently
    auto-configured box is worse than a wrongly prompted one, because nobody
    notices it. Every key stays overridable with `trackt config <key> <val>`.
    """
    conf_path = os.path.join(clone, twatch.CONF_NAME)
    if os.path.exists(conf_path):
        return
    nproc = os.cpu_count() or 1
    ram_mb = total_ram_mb()
    role, reasons = detect_role(nproc, ram_mb)
    detail = "; ".join(reasons)
    order = ["dedicated", "limited", "restricted", "native-oracle"]
    if not ISATTY:
        _write_profile(conf_path, role, nproc, ram_mb)
        print("trackt: no twatch.conf — detected %s (%s)" % (role, detail))
        _print_caps(conf_path, role)
        print("trackt: non-interactive, so this was applied unprompted. "
              "`trackt config <key> <val>` changes any of it.")
        return
    print("\ntrackt: first run on this box.\n  detected: %s\n  role:     "
          "%s%s%s\n" % (detail, GRN, role, OFF))
    for i, name in enumerate(order, 1):
        mark = " <- detected" if name == role else ""
        print("  %d) %-13s %s%s" % (i, name, PROFILES[name]["_blurb"], mark))
    try:
        ans = input("\nEnter to accept %s, or choose [1-%d]: "
                    % (role, len(order))).strip()
    except (EOFError, KeyboardInterrupt):
        ans = ""
    pick = order[int(ans) - 1] if ans in [str(i) for i in
                                          range(1, len(order) + 1)] else role
    _write_profile(conf_path, pick, nproc, ram_mb)
    print("trackt: wrote %s profile -> %s" % (pick, conf_path))
    _print_caps(conf_path, pick)
    print("trackt: tune any key later with `trackt config <key> <val>`")


def _print_caps(conf_path, pick):
    """Say what the profile actually DOES. A role name is not self-explaining,
    and the caps are the part someone re-provisioning a box needs to see."""
    try:
        with open(conf_path) as f:
            conf = json.load(f)
    except (OSError, ValueError):
        return
    eff = dict(twatch.CONF_DEFAULTS, **conf)
    idle = [n for n in ("opt", "bench", "fuzz") if eff.get("idle_" + n)]
    print("  tier %s · %s cores · %s · idle: %s · poll %ss · web %s"
          % (eff.get("tier"),
             conf.get("max_cores", "all"),
             ("%d MB" % conf["max_mem_mb"]) if conf.get("max_mem_mb") else "all RAM",
             ", ".join(idle) or "none",
             eff.get("interval"), "on" if eff.get("web") else "off"))


def _write_profile(conf_path, pick, nproc, total_mb):
    prof = PROFILES[pick]
    conf = {k: v for k, v in prof.items() if not k.startswith("_")}
    if prof.get("_leave_cores"):
        conf["max_cores"] = max(1, nproc - prof["_leave_cores"])
    if prof.get("_half_cores"):
        conf["max_cores"] = max(1, nproc // 2)
    if prof.get("_mem_frac") and total_mb:
        conf["max_mem_mb"] = int(total_mb * prof["_mem_frac"])
    os.makedirs(os.path.dirname(conf_path), exist_ok=True)
    with open(conf_path, "w") as f:
        json.dump(conf, f, indent=1, sort_keys=True)


def cmd_setup(clone, fetch_corpus=False):
    if not os.path.isdir(clone):
        remote = subprocess.run(["git", "-C", CHECKOUT, "remote", "get-url",
                                 "origin"], capture_output=True, text=True
                                ).stdout.strip()
        print("cloning %s -> %s" % (remote, clone))
        subprocess.run(["git", "clone", remote, clone], check=True)
        with open(os.path.expanduser("~/.config/trackt.path"), "w") as f:
            f.write(clone + "\n")
    print("-- box prerequisites --")
    args = ["--fetch-corpus"] if fetch_corpus else []
    rc = subprocess.run([os.path.join(clone, "tools/twatch-setup.sh")] + args,
                        cwd=clone).returncode
    print("-- git access --")
    # Per-checkout, not committable, and silently absent on every fresh clone:
    # .gitattributes marks BOARD.md merge=ours, but without this the driver is
    # unknown and git falls back to a real merge — i.e. a conflict on a file
    # that is generated and whose content is discarded anyway.
    subprocess.run(["git", "config", "merge.ours.driver", "true"], cwd=clone,
                   check=False)
    print("  merge : ok — merge.ours.driver set (generated files self-heal)")
    ok = subprocess.run(["git", "fetch", "--quiet", "--no-write-fetch-head",
                         "origin"], cwd=clone).returncode == 0
    print("  fetch : %s" % (GRN + "ok" + OFF if ok else RED + "FAIL" + OFF))
    push = subprocess.run(["git", "push", "--dry-run", "--quiet", "origin",
                           "HEAD:refs/heads/master"], cwd=clone,
                          capture_output=True, text=True)
    print("  push  : %s" % (GRN + "ok" + OFF if push.returncode == 0
                            else RED + "FAIL" + OFF + " — " + push.stderr.strip()[:200]))
    print("-- role profile --")
    configure_profile(clone)
    return rc


# Wedged detection. testmgr rewrites live.json every second FOR THE WHOLE RUN,
# so during `phase == testing` a stale live.json means the daemon is alive and
# not working — a direct observation, unlike --status, which can only infer a
# problem from coverage and takes up to its grace window to do it.
LIVE_STALE_SECS = 180        # generous: the slowest single job is ~40s
HEARTBEAT_STALE_SECS = 900   # watch.json only moves on phase change, so idle is fine
PUB_DROPS_DEGRADED = 3       # consecutive dropped publishes before we care


def health_check(clone):
    """Is this watcher trustworthy right now? Returns (verdict, exit, reasons).

    Portable ON PURPOSE: reads only files the daemon already writes, makes no
    assumption about a desktop, a display, a mail transport or a network. The
    DELIVERY of an alert is host-specific and deliberately lives outside the
    repo — a box with a graphical session can pipe this into notify-send, a
    headless one into mail or a webhook. See the ticket
    feature-t-watcher-health-verdict-and-host-local-alerting.
    """
    now = time.time()
    reasons = []
    watch = read_json(os.path.join(clone, twatch.WATCH_REL))
    live = read_json(os.path.join(clone, ".testmgr", "live.json"))
    pub = read_json(os.path.join(clone, twatch.PUBHEALTH_REL))
    pid, _ = daemon_pid(clone)

    if not pid:
        return "DOWN", 2, ["no watcher daemon is running"]

    phase = watch.get("phase") or "?"
    # A quiet repo is NOT a fault. Conflating "idle" with "broken" is exactly
    # what made --status untrustworthy, so idle is only checked for a heartbeat.
    if phase == "testing":
        age = now - (live.get("ts") or 0)
        if age > LIVE_STALE_SECS:
            reasons.append("WEDGED: phase=testing but live.json has not moved "
                           "in %ds (pct %s, %s/%s) — the daemon is alive and "
                           "not progressing"
                           % (age, live.get("pct"), live.get("done"),
                              live.get("total")))
            return "DOWN", 2, reasons
    hb = now - (watch.get("ts") or 0)
    if hb > HEARTBEAT_STALE_SECS:
        reasons.append("no phase heartbeat for %dm (phase=%s)"
                       % (hb / 60, phase))
        return "DOWN", 2, reasons

    drops = pub.get("consec_drops") or 0
    if drops >= PUB_DROPS_DEGRADED:
        reasons.append("publishing is dropping verdicts (%d consecutive; last: %s)"
                       % (drops, pub.get("last_reason") or "?"))
    behind = pub.get("behind") or 0
    if behind:
        reasons.append("clone is %s commit(s) behind origin" % behind)

    if reasons:
        return "DEGRADED", 1, reasons
    return "OK", 0, ["daemon %s, phase=%s, publishing clean" % (pid, phase)]


def cmd_health(clone, json_out=False):
    verdict, rc, reasons = health_check(clone)
    if json_out:
        print(json.dumps({"verdict": verdict, "exit": rc, "reasons": reasons,
                          "host": os.uname().nodename, "clone": clone}))
        return rc
    colour = {"OK": GRN, "DEGRADED": YEL, "DOWN": RED}.get(verdict, "")
    print("trackt health: %s%s%s" % (colour, verdict, OFF))
    for r in reasons:
        print("  - %s" % r)
    return rc


UNIT_NAME = "trackt-watcher.service"
UNIT_TEXT = """[Unit]
# Installed by `trackt install`. Edit that, not this file.
Description=Track T watcher daemon (pxx regression matrix)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory={clone}
ExecStart={python} {clone}/tools/twatch.py --clone {clone}

# on-failure, NOT always: a crash or OOM kill restarts, but a deliberate
# `trackt stop` (SIGTERM -> clean exit 0) stays stopped. Supervision must not
# take the decision away from the operator.
Restart=on-failure
RestartSec=30s

# Keep the existing log file so `trackt log` and the run history still work.
StandardOutput=append:{log}
StandardError=append:{log}

# NO resource limits here on purpose: testmgr re-execs into
# `systemd-run --user --scope` for its memory cgroup, and a nested scope under a
# constrained service would inherit the tighter limit and silently undo the
# per-run budget testmgr computes from MemTotal.

[Install]
WantedBy=default.target
"""


def unit_path():
    return os.path.expanduser("~/.config/systemd/user/" + UNIT_NAME)


def cmd_install(clone, uninstall=False):
    """Install (or remove) the watcher as a permanent, reboot-surviving daemon.

    Deliberately EXPLICIT. The default `trackt` / `trackt up` remains an
    interactive foreground thing an admin can watch; making a machine start
    testing by itself forever is a different decision and should be typed out.
    """
    user = os.environ.get("USER") or os.getlogin()
    if not shutil_which("systemctl"):
        print("trackt install: no systemctl on this box — nothing installed.\n"
              "  This box needs its own mechanism (rc.local, cron @reboot, a\n"
              "  supervisor). The watcher itself is portable; only persistence\n"
              "  is platform-specific.")
        return 1
    path = unit_path()
    if uninstall:
        print("trackt uninstall — removing permanent-daemon setup:")
        print("  1. systemctl --user disable --now %s" % UNIT_NAME)
        subprocess.run(["systemctl", "--user", "disable", "--now", UNIT_NAME],
                       check=False)
        if os.path.exists(path):
            os.unlink(path)
            print("  2. removed %s" % path)
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)
        print("  3. linger LEFT AS IS (`loginctl disable-linger %s` to undo) —\n"
              "     other user services may rely on it." % user)
        print("\nThe watcher is no longer permanent. Start it by hand with "
              "`trackt up`.")
        return 0

    print("trackt install — making this box's watcher permanent.")
    print("It will do exactly four things:\n")
    print("  1. write a systemd USER unit:")
    print("       %s" % path)
    print("     ExecStart = %s %s/tools/twatch.py --clone %s"
          % (sys.executable, clone, clone))
    print("  2. Restart=on-failure — a crash or OOM kill restarts after 30s;")
    print("     a deliberate `trackt stop` STAYS stopped. You keep the switch.")
    print("  3. systemctl --user enable %s" % UNIT_NAME)
    print("     => starts on login. With auto-login, that means on boot.")
    print("  4. loginctl enable-linger %s" % user)
    print("     => starts at BOOT even before anyone logs in, AND keeps the")
    print("        systemd user manager alive after logout. That second part")
    print("        matters: testmgr re-execs into `systemd-run --user --scope`")
    print("        for its memory cgroup, and without a user manager that call")
    print("        fails and the run silently loses its memory limit.\n")
    print("  logs stay at %s (so `trackt log` keeps working)" % logpath(clone))
    print("  undo with: trackt uninstall\n")

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(UNIT_TEXT.format(clone=clone, python=sys.executable,
                                 log=logpath(clone)))
    print("wrote %s" % path)
    for cmd in (["systemctl", "--user", "daemon-reload"],
                ["systemctl", "--user", "enable", UNIT_NAME],
                ["loginctl", "enable-linger", user]):
        rc = subprocess.run(cmd, check=False).returncode
        print("  %-52s %s" % (" ".join(cmd), "ok" if rc == 0 else "FAILED"))
    print("\nNOT started. `systemctl --user start %s` now, or it comes up on "
          "the next boot." % UNIT_NAME)
    print("From here on, deploying new twatch.py is:")
    print("  systemctl --user restart %s" % UNIT_NAME)
    return 0


def shutil_which(prog):
    import shutil
    return shutil.which(prog)


# ------------------------------------------------------------------ main ---
# ------------------------------------------------------------ pinstatus ---
# `pinned` is a POINTER, not a label. Status belongs to a SHA, and Track T
# already tracks that per-sha — so "what is the status of the current pin?" is
# a JOIN of pin.log x tstate, never a second copy of the fact stored on the
# artifact (task-t-pin-fast-track-t-owns-verification; the user rejected a
# pinned/verified/release ladder for exactly this reason).
#
# The trade the fast pin makes is that a bad pin is RECOVERED, not prevented.
# Recovery needs somewhere to fall back to, which is why the last fully-green
# pin is the most important line this prints.
PIN_LOG_REL = "stable_linux_amd64/default/pin.log"


def repo_root(cli=None):
    """The checkout to read pin.log and tstate from (not the watcher clone)."""
    if cli:
        return os.path.abspath(os.path.expanduser(cli))
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_pin_log(repo):
    """[{ts, ver, binsha, git}] oldest first.

    Two shapes live in this file: older lines omit the binary sha256
    (`ts pinned v9 (was v9) <gitsha>`), newer ones carry it
    (`ts pinned v249 <binsha> (was xxx) <gitsha>`). The GIT sha is last in
    both, so key off that rather than a field index.
    """
    out = []
    try:
        with open(os.path.join(repo, PIN_LOG_REL)) as f:
            for ln in f:
                w = ln.split()
                if len(w) < 5 or w[1] != "pinned":
                    continue
                git = w[-1]
                if len(git) != 40:
                    continue
                out.append({"ts": w[0], "ver": w[2],
                            "binsha": w[3] if len(w) >= 7 else "",
                            "git": git})
    except OSError:
        pass
    return out


def tstate_runs(repo):
    """{sha: {tier: (verdict, host, date)}} from the UNCAPPED ndjson archives.

    host.json's `history` is capped; runs-<host>.ndjson is not, and a pin can
    easily be older than the cap.
    """
    out = {}
    tdir = os.path.join(repo, twatch.TSTATE_REL)
    try:
        names = sorted(os.listdir(tdir))
    except OSError:
        return out
    for fn in names:
        if not (fn.startswith("runs-") and fn.endswith(".ndjson")):
            continue
        host = fn[5:-7]
        try:
            with open(os.path.join(tdir, fn)) as f:
                for ln in f:
                    ln = ln.strip()
                    if not ln:
                        continue
                    try:
                        r = json.loads(ln)
                    except ValueError:
                        continue
                    sha, tier = r.get("sha"), r.get("tier")
                    if sha and tier:
                        out.setdefault(sha, {})[tier] = (
                            r.get("verdict", "?"), host, r.get("date", ""))
        except OSError:
            continue
    return out


def report_failures(repo, sha, limit=2):
    """The failing job names T published for `sha`, best effort."""
    rdir = os.path.join(repo, twatch.TSTATE_REL, "reports")
    hits = []
    try:
        names = [n for n in sorted(os.listdir(rdir)) if sha[:7] in n]
    except OSError:
        return hits
    for n in names:
        try:
            with open(os.path.join(rdir, n), errors="replace") as f:
                body = f.read()
        except OSError:
            continue
        for ln in body.splitlines():
            if ln.startswith("- ") and ("#" in ln):
                job = ln[2:].split(" — ")[0].strip()
                if job not in hits:
                    hits.append(job)
            if len(hits) >= limit:
                return hits
    return hits


def pin_is_green(runs_for_sha):
    """Judged by T, with a `full` run, and nothing RED in any tier judged."""
    if not runs_for_sha or "full" not in runs_for_sha:
        return False
    return all(v[0] == "GREEN" for v in runs_for_sha.values())


def cmd_pinstatus(repo):
    pins = read_pin_log(repo)
    if not pins:
        print("pinstatus: no %s — nothing pinned here" % PIN_LOG_REL)
        return 1
    runs = tstate_runs(repo)
    cur = pins[-1]
    print("pin %s  %s  %s  %s"
          % (cur["ver"], (cur["binsha"] or "-")[:8], cur["git"][:8], cur["ts"]))

    got = runs.get(cur["git"]) or {}
    if not got:
        # T tests HEAD, not every commit, so the pinned sha may simply not have
        # been judged yet. Say which — "untested" and "green" are not the same
        # answer, and this is the line that must never blur them.
        # NEAREST judged descendant, not an arbitrary one: sort the candidates
        # by when T judged them and take the first that contains the pin. Also
        # keeps this cheap — is_ancestor is a git call per candidate, and there
        # are hundreds of judged shas.
        cands = sorted(((min(v[2] for v in t.values()), sha)
                        for sha, t in runs.items() if sha != cur["git"]),
                       key=lambda x: x[0])
        covered = next((sha for when, sha in cands
                        if when >= cur["ts"]
                        and twatch.is_ancestor(repo, cur["git"], sha)), None)
        print("  NOT JUDGED at this sha%s"
              % ("" if not covered
                 else " — but %s, a descendant, is judged (%s)"
                      % (covered[:8],
                         ", ".join("%s %s" % (t, v[0])
                                   for t, v in sorted(runs[covered].items())))))
    else:
        for tier in sorted(got):
            verdict, host, date = got[tier]
            extra = ""
            if verdict != "GREEN":
                jobs = report_failures(repo, cur["git"])
                if jobs:
                    extra = "  " + ", ".join(jobs)
            print("  %-7s %-6s%s  (%s)" % (tier, verdict, extra, host))

    back = next((p for p in reversed(pins)
                 if pin_is_green(runs.get(p["git"]))), None)
    if back:
        same = " — that is the current pin" if back["git"] == cur["git"] else ""
        print("  last pin T found fully green: %s  (%s)%s"
              % (back["ver"], back["git"][:8], same))
    else:
        print("  last pin T found fully green: NONE in this log — "
              "no fallback target; demote by hand if the current pin is bad")
    print("  (green = a `full` run judged this sha and no tier was RED; "
          "`make revert` demotes)")
    return 0


def main():
    ap = argparse.ArgumentParser(
        prog="trackt", description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    ap.add_argument("cmd", nargs="?", default="up",
                    choices=["up", "status", "start", "stop", "restart",
                             "watch", "run", "setup", "config", "log", "web",
                             "dashboard", "health", "install", "uninstall",
                             "pinstatus"])
    ap.add_argument("arg", nargs="*")
    ap.add_argument("--clone", help="watcher clone dir")
    ap.add_argument("--remote", help="start: clone URL if dir missing")
    ap.add_argument("--local-code", action="store_true",
                    help="start/restart/up: run THIS checkout's twatch.py "
                         "instead of the clone's committed copy (for "
                         "deliberately testing an uncommitted change)")
    ap.add_argument("--json", action="store_true",
                    help="health: machine-readable output for a notifier")
    ap.add_argument("--fetch-corpus", action="store_true",
                    help="setup: also fetch gitignored corpus trees")
    ap.add_argument("--no-web", action="store_true", help="up: skip web UI")
    ap.add_argument("--no-daemon", action="store_true",
                    help="up: don't start the daemon")
    ap.add_argument("--no-sha", action="store_true",
                    help="watch: omit the commit hash from completion lines")
    ap.add_argument("--no-attach", action="store_true",
                    help="up: print status and return (implies daemon may "
                         "keep running — you asked not to supervise it)")
    a = ap.parse_args()
    clone = clone_dir(a.clone)

    if a.cmd == "up":
        return cmd_up(clone, a)
    if a.cmd in ("install", "uninstall"):
        return cmd_install(clone, uninstall=(a.cmd == "uninstall"))
    if a.cmd == "pinstatus":
        return cmd_pinstatus(repo_root(a.clone if a.clone else None))
    if a.cmd == "health":
        return cmd_health(clone, json_out=a.json)
    if a.cmd == "status":
        return cmd_status(clone, attach_ok=False)
    if a.cmd == "start":
        return cmd_start(clone, a.remote, local_code=a.local_code)
    if a.cmd == "stop":
        return cmd_stop(clone)
    if a.cmd == "restart":
        cmd_stop(clone)
        subprocess.run(["git", "-C", clone, "pull", "--rebase", "--quiet"])
        return cmd_start(clone, local_code=a.local_code)
    if a.cmd == "watch":
        return cmd_watch(clone, show_sha=not a.no_sha)
    if a.cmd == "run":
        tier = a.arg[0] if a.arg else "quick"
        if tier not in TIERS:
            print("tier? one of: %s" % ", ".join(TIERS))
            return 1
        os.execv(sys.executable, [sys.executable,
                                  os.path.join(HERE, "testmgr.py"),
                                  "--tier", tier])
    if a.cmd == "setup":
        return cmd_setup(clone, a.fetch_corpus)
    if a.cmd == "config":
        return cmd_config(clone, *(a.arg[:2] or [None]))
    if a.cmd == "dashboard":
        os.execv(sys.executable, [sys.executable,
                                  os.path.join(HERE, "twatch_web.py"),
                                  "--clone", clone, "--static"])
    if a.cmd == "log":
        os.execvp("tail", ["tail", "-n", "50", "-f", logpath(clone)])
    if a.cmd == "web":
        want = (a.arg[0] if a.arg else "on") == "on"
        cmd_config(clone, "web", "on" if want else "off")
        if want:
            return start_web(clone, twatch.load_conf(clone))
        wp = web_pid(clone)
        if wp:
            os.kill(wp, signal.SIGTERM)
            print("web UI stopped")
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
