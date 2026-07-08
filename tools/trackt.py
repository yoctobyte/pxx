#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""trackt — Track T one-stop launcher.

One tool for the whole watcher stack: status, daemon start/stop, live
progress view, manual runs, box setup + git-access verification, config,
log tail, web UI.  Everything is a thin frontend over the state files the
engine publishes (.testmgr/live.json, .testmgr/watch.json,
devdocs/progress/tstate/**) — the daemon (tools/twatch.py) stays the engine.

  trackt                 status; attaches to the live view if a run is active
  trackt start|stop|restart|status
  trackt watch           live progress (Ctrl-C detaches, daemon keeps going)
  trackt run [tier]      manual testmgr run in THIS checkout (default quick)
  trackt setup           box prerequisites + git fetch/push access check
  trackt config [k [v]]  show / set daemon config (applies live where safe)
  trackt log             follow the daemon log
  trackt web on|off      enable/disable the Flask UI (spawned by start)

The watcher clone is found via --clone, $TRACKT_CLONE, ~/.config/trackt.path,
or ~/trackt-watch.  `trackt run` never touches the clone — it tests the
checkout you call it from.
"""

import argparse
import json
import os
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKOUT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import twatch                                            # noqa: E402

TIERS = ("quick", "native", "limited", "full")
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


def daemon_pid(clone):
    w = read_json(os.path.join(clone, twatch.WATCH_REL))
    pid = w.get("pid")
    if pid and w.get("phase") != "stopped" and pid_alive(pid, "twatch.py"):
        return pid, w
    for p in os.listdir("/proc"):     # daemon older than watch.json support
        if p.isdigit() and pid_alive(int(p), "twatch.py") \
                and pid_alive(int(p), clone):
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
        extra = " ".join("%s=%s" % (k, w[k]) for k in ("sha", "tier", "head")
                         if w.get(k))
        print("  daemon : %sRUNNING%s pid %d — %s %s (%s ago)"
              % (GRN, OFF, pid, w.get("phase", "?"), extra, fmt_age(w.get("ts"))))
    else:
        print("  daemon : %sSTOPPED%s — trackt start" % (RED, OFF))
    # tstate summary (same source as twatch --status), from the dev checkout
    # if it has tstate, else from the clone
    repo = CHECKOUT if os.path.isdir(os.path.join(CHECKOUT, "devdocs")) else clone
    twatch.status(repo, grace_min=45)
    if attach_ok and pid and w.get("phase") == "testing":
        print("%s-- run in progress, attaching (Ctrl-C detaches) --%s" % (DIM, OFF))
        cmd_watch(clone)
    return 0


# ----------------------------------------------------------------- watch ---
def render_live(clone, w, live, last_reds):
    phase = w.get("phase", "?")
    if phase != "testing" or not live:
        line = "phase %-12s %s" % (phase, DIM + fmt_age(w.get("ts")) + " ago" + OFF)
        sys.stdout.write("\r\033[K  " + line if ISATTY else "  " + line + "\n")
        sys.stdout.flush()
        return last_reds
    reds = live.get("red", [])
    for r in reds:
        if r not in last_reds:
            print("\r\033[K  %sRED %s%s" % (RED, r, OFF))
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


def cmd_watch(clone):
    print("%s  live view — Ctrl-C detaches (daemon keeps running)%s" % (DIM, OFF))
    seen = set()
    try:
        while True:
            pid, w = daemon_pid(clone)
            live = read_json(os.path.join(clone, ".testmgr", "live.json"))
            if not pid:
                print("\n  daemon not running.")
                return 1
            seen = render_live(clone, w, live, seen)
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n  detached — daemon keeps running (trackt stop to stop it).")
        return 0


# ------------------------------------------------------------- lifecycle ---
def cmd_start(clone, remote=None):
    if not os.path.isdir(clone):
        if not remote:
            print("no clone at %s — trackt setup, or: trackt start --remote <url>"
                  % clone)
            return 1
    pid, _ = daemon_pid(clone)
    if pid:
        print("daemon already running (pid %d)" % pid)
        return 0
    lg = open(logpath(clone), "a")
    cmd = [sys.executable, os.path.join(HERE, "twatch.py"), "--clone", clone]
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
        print("SIGTERM sent (pid %d) — waiting (aborts any running gate)" % pid)
        for _ in range(120):
            if not pid_alive(pid, "twatch.py"):
                break
            time.sleep(1)
        else:
            print("%sstill alive after 120s%s — kill -9 %d by hand" % (RED, OFF, pid))
            rc = 1
        if rc == 0:
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
    ok = subprocess.run(["git", "fetch", "--quiet", "origin"], cwd=clone
                        ).returncode == 0
    print("  fetch : %s" % (GRN + "ok" + OFF if ok else RED + "FAIL" + OFF))
    push = subprocess.run(["git", "push", "--dry-run", "--quiet", "origin",
                           "HEAD:refs/heads/master"], cwd=clone,
                          capture_output=True, text=True)
    print("  push  : %s" % (GRN + "ok" + OFF if push.returncode == 0
                            else RED + "FAIL" + OFF + " — " + push.stderr.strip()[:200]))
    return rc


# ------------------------------------------------------------------ main ---
def main():
    ap = argparse.ArgumentParser(
        prog="trackt", description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    ap.add_argument("cmd", nargs="?", default="status",
                    choices=["status", "start", "stop", "restart", "watch",
                             "run", "setup", "config", "log", "web"])
    ap.add_argument("arg", nargs="*")
    ap.add_argument("--clone", help="watcher clone dir")
    ap.add_argument("--remote", help="start: clone URL if dir missing")
    ap.add_argument("--fetch-corpus", action="store_true",
                    help="setup: also fetch gitignored corpus trees")
    a = ap.parse_args()
    clone = clone_dir(a.clone)

    if a.cmd == "status":
        return cmd_status(clone)
    if a.cmd == "start":
        return cmd_start(clone, a.remote)
    if a.cmd == "stop":
        return cmd_stop(clone)
    if a.cmd == "restart":
        cmd_stop(clone)
        subprocess.run(["git", "-C", clone, "pull", "--rebase", "--quiet"])
        return cmd_start(clone)
    if a.cmd == "watch":
        return cmd_watch(clone)
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
