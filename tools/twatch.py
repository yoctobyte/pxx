#!/usr/bin/env python3
"""twatch.py — Track T face 1: standalone continuous test watcher.

Watches the central repo, runs the full testmgr gate on every new master
HEAD in its OWN clone, and publishes sparse per-SHA regression reports to
devdocs/progress/tstate/.  No AI, no judgment: signal only.  Ticket
crafting from these reports is the Track T agent's job (face 2).

The watcher relies on tools/testmgr.py's adaptive resource-aware
scheduling, so the same command runs on a dev box, a low-power laptop, or
a big Xeon — several hosts in parallel are fine, they just push
independently (host-tagged files, rebase-retry).

Publish contract (deliberately sparse):
  tstate/<host>.json               rolling machine state: last run, per-job
                                   statuses, open regressions, capped history
  tstate/reports/<utc>-<sha7>-<host>.md   full report, ONLY when something
                                   CHANGED (NEW-RED / FIXED) or verdict RED
  tstate/TSTATE.md                 regenerated index over all host state files
The watcher commits nothing outside devdocs/progress/tstate/.

Typical service:  tools/twatch.py --clone ~/.twatch/frankonpiler \
                      [--remote <url>] [--interval 60] [--debounce 20]
One-shot (cron / smoke):  add --once.  Test a specific ref: --branch <ref>.

Runbook: run under systemd/nohup with the repo's deploy key loaded; SIGINT
tears down cleanly (testmgr kills its process groups).  Offline periods are
harmless — next fetch resumes.  State marker for idempotence = <host>.json.
"""

import argparse
import datetime
import fnmatch
import json
import os
import re
import signal
import socket
import subprocess
import sys
import time

TSTATE_REL = "devdocs/progress/tstate"
HISTORY_CAP = 50
STOP = False


def sh(args, cwd, check=True, capture=True):
    r = subprocess.run(args, cwd=cwd, text=True,
                       capture_output=capture)
    if check and r.returncode != 0:
        raise RuntimeError("cmd failed (%d): %s\n%s" %
                           (r.returncode, " ".join(args), (r.stderr or "")[-2000:]))
    return (r.stdout or "").strip()


def utcnow():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ------------------------------------------------------------------ git ----
class Clone:
    def __init__(self, path, remote, branch):
        self.path = path
        self.remote = remote
        self.branch = branch
        if not os.path.isdir(os.path.join(path, ".git")):
            if not remote:
                sys.exit("twatch: no clone at %s and no --remote to create it" % path)
            os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
            print("twatch: cloning %s -> %s" % (remote, path), flush=True)
            sh(["git", "clone", remote, path], cwd=".", capture=False)

    def fetch(self):
        sh(["git", "fetch", "--quiet", "origin"], cwd=self.path)

    def remote_head(self):
        return sh(["git", "rev-parse", "origin/%s" % self.branch], cwd=self.path)

    def checkout(self, sha):
        sh(["git", "checkout", "--quiet", "--detach", sha], cwd=self.path)

    def commits_between(self, good, bad):
        """SHAs strictly after `good` up to and including `bad`, oldest first."""
        out = sh(["git", "rev-list", "--reverse", "%s..%s" % (good, bad)],
                 cwd=self.path)
        return out.splitlines() if out else []

    def publish(self, message):
        """Commit ONLY tstate files onto the branch tip and push, with
        rebase-retry so parallel watcher hosts don't fight."""
        sh(["git", "checkout", "--quiet", self.branch], cwd=self.path)
        sh(["git", "add", "--", TSTATE_REL], cwd=self.path)
        if not sh(["git", "status", "--porcelain", "--", TSTATE_REL], cwd=self.path):
            return
        sh(["git", "commit", "--quiet", "-m", message, "--", TSTATE_REL],
           cwd=self.path)
        sh(["git", "pull", "--rebase", "--quiet", "origin", self.branch],
           cwd=self.path)
        for attempt in range(5):
            try:
                sh(["git", "push", "--quiet", "origin", self.branch], cwd=self.path)
                return
            except RuntimeError:
                time.sleep(2 + attempt * 3)
                sh(["git", "pull", "--rebase", "--quiet", "origin", self.branch],
                   cwd=self.path)
        raise RuntimeError("twatch: push kept failing after retries")


# ---------------------------------------------------------------- testing --
def run_gate(clone, tier, job_glob=None):
    """Run the CLONE's testmgr (self-versioned with the tested tree)."""
    # fresh clone has no compiler binary: seed from the committed stable
    if not os.path.exists(os.path.join(clone.path, "compiler/pascal26")):
        subprocess.run(["make", "--no-print-directory", "seed-from-stable"],
                       cwd=clone.path, check=True)
    rep_path = os.path.join(clone.path, ".twatch-report.json")
    if os.path.exists(rep_path):
        os.unlink(rep_path)
    cmd = [sys.executable, os.path.join(clone.path, "tools/testmgr.py"),
           "--tier", tier, "--report-json", rep_path]
    if job_glob:
        cmd += ["--job", job_glob]
    r = subprocess.run(cmd, cwd=clone.path)
    if not os.path.exists(rep_path):
        return None, r.returncode          # testmgr died before reporting
    with open(rep_path) as f:
        return json.load(f), r.returncode


# ----------------------------------------------------------------- state ---
def state_path(clone, host):
    return os.path.join(clone.path, TSTATE_REL, host + ".json")


def load_state(clone, host):
    p = state_path(clone, host)
    if os.path.exists(p):
        with open(p) as f:
            return json.load(f)
    return {"host": host, "last": None, "jobs": {},
            "open_regressions": [], "history": []}


def save_state(clone, host, st):
    os.makedirs(os.path.dirname(state_path(clone, host)), exist_ok=True)
    with open(state_path(clone, host), "w") as f:
        json.dump(st, f, indent=1, sort_keys=True)
        f.write("\n")


def diff_jobs(prev_jobs, report):
    now = {j["name"]: j["status"] for j in report["jobs"]}
    new_red = sorted(n for n, s in now.items()
                     if s != "pass" and prev_jobs.get(n, "pass") == "pass")
    fixed = sorted(n for n, s in now.items()
                   if s == "pass" and prev_jobs.get(n, "pass") != "pass")
    still_red = sorted(n for n, s in now.items()
                       if s != "pass" and prev_jobs.get(n, "pass") != "pass")
    return now, new_red, fixed, still_red


# ---------------------------------------------------------------- reports --
def write_report_md(clone, host, sha, parent, report, new_red, fixed, still_red):
    ts = utcnow().replace(":", "").replace("-", "")
    rel = os.path.join(TSTATE_REL, "reports",
                       "%s-%s-%s.md" % (ts, sha[:7], host))
    path = os.path.join(clone.path, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = ["---",
             "sha: %s" % sha,
             "parent_tested: %s" % (parent or "none"),
             "date: %s" % utcnow(),
             "host: %s" % host,
             "tier: %s" % report["tier"],
             "wall: %s" % report["wall"],
             "scale: %s" % report["scale"],
             "verdict: %s" % report["verdict"],
             "---", ""]
    for title, names in (("NEW-RED", new_red), ("FIXED", fixed),
                         ("STILL-RED", still_red)):
        if names:
            lines.append("## %s" % title)
            lines += ["- %s" % n for n in names]
            lines.append("")
    first = next((j for j in report["jobs"] if j["status"] != "pass"), None)
    if first:
        lines.append("## first failure: %s (%s)" % (first["name"], first["status"]))
        lines.append("repro: `tools/testmgr.py --tier %s --job '%s'` at %s"
                     % (report["tier"], first["name"], sha))
        log = first.get("log")
        if log and os.path.exists(log):
            lines.append("```")
            with open(log, errors="replace") as f:
                lines.append(f.read()[-4000:])
            lines.append("```")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return rel


def regen_index(clone):
    tdir = os.path.join(clone.path, TSTATE_REL)
    rows, regs = [], []
    for fn in sorted(os.listdir(tdir)):
        if not fn.endswith(".json"):
            continue
        with open(os.path.join(tdir, fn)) as f:
            st = json.load(f)
        last = st.get("last") or {}
        rows.append("| %s | `%s` | %s | %s | %ss |" %
                    (st["host"], (last.get("sha") or "")[:12],
                     last.get("date", ""), last.get("verdict", "never-ran"),
                     last.get("wall", "")))
        for r in st.get("open_regressions", []):
            regs.append("- **%s** (%s): bad `%s`, last good `%s`, %d commit(s) in range"
                        % (r["job"], st["host"], r["bad"][:12],
                           (r.get("good") or "unknown")[:12],
                           len(r.get("range", []))))
    out = ["# TSTATE — Track T watcher index (generated by tools/twatch.py)", "",
           "| host | last tested | date | verdict | wall |",
           "|------|-------------|------|---------|------|"] + rows + [""]
    out.append("## Open regressions")
    out += regs if regs else ["- none"]
    out.append("")
    with open(os.path.join(tdir, "TSTATE.md"), "w") as f:
        f.write("\n".join(out))


# ------------------------------------------------------------------ core ---
def test_sha(clone, host, st, sha, tier):
    print("twatch: testing %s (%s)" % (sha[:12], tier), flush=True)
    clone.checkout(sha)
    report, rc = run_gate(clone, tier)
    clone_head_back(clone)
    if report is None:
        print("twatch: testmgr produced no report (rc=%d) — infra problem, "
              "not recording a verdict" % rc, flush=True)
        return False

    parent = (st["last"] or {}).get("sha")
    now, new_red, fixed, still_red = diff_jobs(st["jobs"], report)

    # open-regression bookkeeping
    regs = [r for r in st["open_regressions"] if r["job"] not in fixed]
    for name in new_red:
        rng = clone.commits_between(parent, sha) if parent else [sha]
        regs.append({"job": name, "bad": sha, "good": parent,
                     "range": rng, "opened": utcnow()})
    st["open_regressions"] = regs

    changed = bool(new_red or fixed)
    rel = None
    if changed or report["verdict"] == "RED":
        rel = write_report_md(clone, host, sha, parent, report,
                              new_red, fixed, still_red)

    st["last"] = {"sha": sha, "date": utcnow(), "verdict": report["verdict"],
                  "wall": report["wall"], "tier": report["tier"]}
    st["jobs"] = now
    st["history"] = (st["history"] +
                     [{"sha": sha, "date": st["last"]["date"],
                       "verdict": report["verdict"],
                       "new_red": new_red, "fixed": fixed}])[-HISTORY_CAP:]
    save_state(clone, host, st)
    regen_index(clone)
    msg = "tstate(%s): %s %s" % (host, sha[:12], report["verdict"])
    if new_red:
        msg += " NEW-RED:" + ",".join(new_red[:5])
    if fixed:
        msg += " FIXED:" + ",".join(fixed[:5])
    clone.publish(msg)
    print("twatch: %s %s%s" % (sha[:12], report["verdict"],
                               " report=" + rel if rel else ""), flush=True)
    return True


def clone_head_back(clone):
    sh(["git", "checkout", "--quiet", clone.branch], cwd=clone.path)


def bisect_step(clone, host, st, tier):
    """Idle work: narrow one open regression range by testing its midpoint
    with ONLY the failing job."""
    for reg in st["open_regressions"]:
        rng = reg.get("range", [])
        if len(rng) <= 1:
            continue
        mid = rng[len(rng) // 2 - 1] if len(rng) > 2 else rng[0]
        # skip the known-bad tip
        if mid == reg["bad"] and len(rng) > 1:
            mid = rng[0]
        print("twatch: bisect %s at %s (%d in range)" %
              (reg["job"], mid[:12], len(rng)), flush=True)
        clone.checkout(mid)
        report, _rc = run_gate(clone, tier, job_glob=reg["job"])
        clone_head_back(clone)
        if report is None:
            return False
        red = any(j["status"] != "pass" for j in report["jobs"])
        i = rng.index(mid)
        if red:
            reg["range"] = rng[:i + 1]
            reg["bad"] = mid
        else:
            reg["range"] = rng[i + 1:]
            reg["good"] = mid
        save_state(clone, host, st)
        regen_index(clone)
        clone.publish("tstate(%s): bisect %s -> %d commit(s)"
                      % (host, reg["job"], len(reg["range"])))
        return True
    return False


def debounce(clone, secs, cap=300):
    """Wait until origin/<branch> has been quiet for `secs` (commit bursts
    settle); give up after `cap` and test the newest anyway."""
    t0 = time.monotonic()
    head = clone.remote_head()
    quiet_since = time.monotonic()
    while time.monotonic() - quiet_since < secs:
        if STOP or time.monotonic() - t0 > cap:
            break
        time.sleep(min(5, secs))
        clone.fetch()
        h = clone.remote_head()
        if h != head:
            head, quiet_since = h, time.monotonic()
    return head


# ---------------------------------------------------------------- status ---
def status(repo, grace_min):
    """Is Track T covering this repo?  No ping, no network: a watcher is
    considered UP iff every commit older than the grace window is tested by
    some host (a quiet watcher on a quiet repo is indistinguishable from a
    dead one — and it doesn't matter).  Exit 0 = offload to T; 1 = T is
    down/absent, run your own full gate."""
    tdir = os.path.join(repo, TSTATE_REL)
    tested = set()
    hosts = []
    if os.path.isdir(tdir):
        for fn in os.listdir(tdir):
            if not fn.endswith(".json"):
                continue
            with open(os.path.join(tdir, fn)) as f:
                st = json.load(f)
            hosts.append(st)
            if st.get("last"):
                tested.add(st["last"]["sha"])
            tested.update(h["sha"] for h in st.get("history", []))
    if not hosts:
        print("tstate: DOWN — no watcher state in %s (run your own full gate)"
              % TSTATE_REL)
        return 1
    out = sh(["git", "log", "--format=%H %ct", "-n", "200"], cwd=repo)
    now = time.time()
    untested_old = None
    newest_tested = None
    for ln in out.splitlines():
        sha, ct = ln.split()
        if sha in tested:
            newest_tested = (sha, int(ct))
            break
        if now - int(ct) > grace_min * 60:
            untested_old = (sha, int(ct))
            break
    for st in hosts:
        last = st.get("last") or {}
        print("tstate: host %-12s last %s %s (%s)" %
              (st["host"], (last.get("sha") or "")[:12],
               last.get("verdict", "never"), last.get("date", "")))
        for r in st.get("open_regressions", []):
            print("tstate:   open regression: %s bad=%s (%d in range)"
                  % (r["job"], r["bad"][:12], len(r.get("range", []))))
    if untested_old:
        age = int((now - untested_old[1]) / 60)
        print("tstate: DOWN — %s untested for %d min (> %d min grace); "
              "run your own full gate" % (untested_old[0][:12], age, grace_min))
        return 1
    if newest_tested:
        print("tstate: UP — commits through %s tested; offload the matrix to T"
              % newest_tested[0][:12])
    else:
        print("tstate: UP — only fresh commits pending (within %d min grace)"
              % grace_min)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--clone", help="dedicated clone dir (created if --remote); "
                                    "required except for --status")
    ap.add_argument("--status", action="store_true",
                    help="report watcher liveness from tstate vs git history "
                         "(run in any checkout; exit 0 = T up, 1 = run own gate)")
    ap.add_argument("--grace", type=float, default=45,
                    help="--status: minutes a commit may sit untested before "
                         "T counts as down (default 45)")
    ap.add_argument("--remote", help="clone URL if the clone dir doesn't exist yet")
    ap.add_argument("--branch", default="master")
    ap.add_argument("--tier", default="full", choices=["quick", "limited", "full"])
    ap.add_argument("--host", default=socket.gethostname().split(".")[0])
    ap.add_argument("--interval", type=float, default=60, help="poll seconds")
    ap.add_argument("--debounce", type=float, default=20,
                    help="repo must be quiet this long before testing")
    ap.add_argument("--once", action="store_true",
                    help="single iteration (cron / smoke test)")
    ap.add_argument("--no-bisect", action="store_true")
    args = ap.parse_args()

    if args.status:
        repo = os.path.abspath(os.path.expanduser(args.clone)) if args.clone \
            else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        return status(repo, args.grace)
    if not args.clone:
        ap.error("--clone is required (except with --status)")

    def stop(*_):
        global STOP
        STOP = True
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    clone = Clone(os.path.abspath(os.path.expanduser(args.clone)),
                  args.remote, args.branch)
    host = re.sub(r"[^A-Za-z0-9_-]", "-", args.host)

    while not STOP:
        clone.fetch()
        st = load_state(clone, host)
        head = clone.remote_head()
        tested = (st["last"] or {}).get("sha")
        if head != tested:
            head = debounce(clone, args.debounce)
            if not STOP:
                test_sha(clone, host, st, head, args.tier)
        elif not args.no_bisect:
            st = load_state(clone, host)
            if not bisect_step(clone, host, st, args.tier):
                if args.once:
                    print("twatch: up to date (%s), nothing to do" % head[:12],
                          flush=True)
        if args.once:
            break
        for _ in range(int(args.interval)):
            if STOP:
                break
            time.sleep(1)
    print("twatch: bye", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
