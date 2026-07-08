#!/usr/bin/env python3
"""twatch.py — Track T face 1: standalone continuous test watcher.

Watches the central repo and tests every new master HEAD in its OWN clone,
two-phase: a fast native verdict (--fast-tier, default `native`) lands
within minutes of a push; the full matrix (--tier, default `full`: cross
targets + corpus) backfills while the repo is idle and is ABORTED (SIGINT,
verdict discarded) the moment a new push arrives — pushes always preempt.
Publishes sparse per-SHA regression reports to devdocs/progress/tstate/.
No AI, no judgment: signal only.  Ticket crafting from these reports is
the Track T agent's job (face 2).

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
import tempfile
import time

TSTATE_REL = "devdocs/progress/tstate"
WATCH_REL = ".testmgr/watch.json"     # daemon phase heartbeat for frontends
CONF_NAME = "twatch.conf"             # per-clone config (JSON, untracked)
CONF_DEFAULTS = {"tier": "full", "fast_tier": "native", "interval": 60,
                 "debounce": 20, "no_bisect": False,
                 "autoticket": True,   # stub regression tickets (face 1)
                 "web": True, "web_port": 8377}   # everything ON by default;
                                       # ./trackt flags / config opt OUT
CONF = dict(CONF_DEFAULTS)            # effective config, set in main()


def write_json_atomic(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


def load_conf(clone_path):
    try:
        with open(os.path.join(clone_path, CONF_NAME)) as f:
            user = json.load(f)
    except (OSError, ValueError):
        user = {}
    conf = dict(CONF_DEFAULTS)
    conf.update({k: v for k, v in user.items() if k in CONF_DEFAULTS or
                 k.startswith("anthropic")})
    return conf


def set_phase(clone, host, phase, **kw):
    d = {"ts": time.time(), "pid": os.getpid(), "host": host, "phase": phase}
    d.update(kw)
    write_json_atomic(os.path.join(clone.path, WATCH_REL), d)
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
        # refuse to watch a working dev checkout: we do detached checkouts of
        # arbitrary SHAs — running that under an active agent/dev tree would
        # yank files out from under them.  A watcher clone stays pristine.
        dirty = self.dirty()
        if dirty:
            sys.exit("twatch: %s has uncommitted changes — this looks like a "
                     "dev checkout, not a dedicated watcher clone. Refusing.\n%s"
                     % (path, dirty[:500]))

    def dirty(self):
        """Tracked changes only (-uno): untracked scratch (our own report
        file, corpus trees) is harmless — detached checkouts don't touch it."""
        return sh(["git", "status", "--porcelain", "-uno"], cwd=self.path)

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

    def publish(self, message, paths=None):
        """Commit ONLY the given paths (default: tstate) onto the branch tip
        and push, with rebase-retry so parallel watcher hosts don't fight."""
        paths = list(paths or [TSTATE_REL])
        sh(["git", "checkout", "--quiet", self.branch], cwd=self.path)
        sh(["git", "add", "--"] + paths, cwd=self.path)
        if not sh(["git", "status", "--porcelain", "--"] + paths, cwd=self.path):
            return
        sh(["git", "commit", "--quiet", "-m", message, "--"] + paths,
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
def run_gate(clone, tier, job_glob=None, abort_check=None):
    """Run the CLONE's testmgr (self-versioned with the tested tree).

    abort_check: optional callable polled every ~30s; returning True SIGINTs
    the run (testmgr tears its jobs down) and run_gate returns (None,
    "aborted") — the caller must record NO verdict for an aborted run."""
    # fresh clone has no compiler binary: seed from the committed stable.
    # CRITICAL: backdate the seeded binary — its copy-time mtime would beat
    # every source file and make would never self-host HEAD's compiler, so
    # the whole gate would silently test HEAD sources with the PINNED binary
    # (55 false reds on the first live deploy, 2026-07-07).
    comp = os.path.join(clone.path, "compiler/pascal26")
    if not os.path.exists(comp):
        subprocess.run(["make", "--no-print-directory", "seed-from-stable"],
                       cwd=clone.path, check=True)
        os.utime(comp, (0, 0))
    rep_path = os.path.join(tempfile.gettempdir(),
                            "twatch-report-%d.json" % os.getpid())
    if os.path.exists(rep_path):
        os.unlink(rep_path)
    cmd = [sys.executable, os.path.join(clone.path, "tools/testmgr.py"),
           "--tier", tier, "--report-json", rep_path]
    if job_glob:
        cmd += ["--job", job_glob]
    proc = subprocess.Popen(cmd, cwd=clone.path, start_new_session=True)
    last_check = time.monotonic()
    wp = os.path.join(clone.path, WATCH_REL)
    while proc.poll() is None:
        time.sleep(1)
        if time.monotonic() - last_check >= 30:
            last_check = time.monotonic()
            try:                       # keep the heartbeat fresh mid-run
                with open(wp) as f:
                    w = json.load(f)
                w["ts"] = time.time()
                write_json_atomic(wp, w)
            except (OSError, ValueError):
                pass
            if abort_check and abort_check():
                print("twatch: aborting %s run (new work preempts it)" % tier,
                      flush=True)
                try:
                    os.killpg(proc.pid, signal.SIGINT)
                    proc.wait(timeout=120)
                except (ProcessLookupError, subprocess.TimeoutExpired):
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    proc.wait()
                return None, "aborted"
    if not os.path.exists(rep_path):
        return None, proc.returncode       # testmgr died before reporting
    with open(rep_path) as f:
        return json.load(f), proc.returncode


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
    # "skip" (corpus tree absent on this box) is pass-equivalent: the job is
    # not applicable here, and mapping it to pass closes any open regression
    now = {j["name"]: ("pass" if j["status"] == "skip" else j["status"])
           for j in report["jobs"]}
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
    first = next((j for j in report["jobs"]
                  if j["status"] not in ("pass", "skip")), None)
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
        lf = st.get("last_full") or {}
        rows.append("| %s | `%s` | %s | %s (%s) | %ss | `%s` %s |" %
                    (st["host"], (last.get("sha") or "")[:12],
                     last.get("date", ""), last.get("verdict", "never-ran"),
                     last.get("tier", "?"), last.get("wall", ""),
                     (lf.get("sha") or "")[:12], lf.get("verdict", "")))
        for r in st.get("open_regressions", []):
            regs.append("- **%s** (%s): bad `%s`, last good `%s`, %d commit(s) in range"
                        % (r["job"], st["host"], r["bad"][:12],
                           (r.get("good") or "unknown")[:12],
                           len(r.get("range", []))))
    out = ["# TSTATE — Track T watcher index (generated by tools/twatch.py)", "",
           "| host | last tested | date | verdict | wall | full through |",
           "|------|-------------|------|---------|------|--------------|"] + rows + [""]
    out.append("## Open regressions")
    out += regs if regs else ["- none"]
    out.append("")
    with open(os.path.join(tdir, "TSTATE.md"), "w") as f:
        f.write("\n".join(out))


# ------------------------------------------------------------------ core ---
def test_sha(clone, host, st, sha, tier, full=True, abort_check=None):
    """Gate `sha` at `tier` and publish. full=True replaces the per-job
    status map and records last_full; full=False (fast phase) merges into
    it, so cross/corpus verdicts from earlier full runs aren't forgotten
    and don't flap NEW-RED on the next full run."""
    print("twatch: testing %s (%s%s)" % (sha[:12], tier,
                                         "" if full else ", fast"), flush=True)
    set_phase(clone, host, "testing", sha=sha, tier=tier, fast=not full)
    clone.checkout(sha)
    report, rc = run_gate(clone, tier, abort_check=abort_check)
    clone_head_back(clone)
    if rc == "aborted":
        return "aborted"
    if report is None:
        print("twatch: testmgr produced no report (rc=%s) — infra problem, "
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
    if full:
        st["jobs"] = now
        st["last_full"] = dict(st["last"])
    else:
        st["jobs"] = dict(st["jobs"], **now)
    st["history"] = (st["history"] +
                     [{"sha": sha, "date": st["last"]["date"],
                       "verdict": report["verdict"], "tier": report["tier"],
                       "new_red": new_red, "fixed": fixed}])[-HISTORY_CAP:]
    save_state(clone, host, st)
    # uncapped run archive (host.json history is capped): one ndjson line per
    # run — the web UI's history/regression-frequency source
    with open(os.path.join(clone.path, TSTATE_REL,
                           "runs-%s.ndjson" % host), "a") as f:
        f.write(json.dumps({"sha": sha, "date": st["last"]["date"],
                            "tier": report["tier"], "full": full,
                            "verdict": report["verdict"],
                            "wall": report["wall"], "new_red": new_red,
                            "fixed": fixed}, sort_keys=True) + "\n")
    regen_index(clone)
    msg = "tstate(%s): %s %s (%s)" % (host, sha[:12], report["verdict"],
                                      report["tier"])
    if new_red:
        msg += " NEW-RED:" + ",".join(new_red[:5])
    if fixed:
        msg += " FIXED:" + ",".join(fixed[:5])
    clone.publish(msg)
    if new_red and CONF.get("autoticket"):
        file_stub_tickets(clone, host, st, sha, new_red, report)
    print("twatch: %s %s%s" % (sha[:12], report["verdict"],
                               " report=" + rel if rel else ""), flush=True)
    return True


PROGRESS_BUCKETS = ("urgent", "working", "unfinished", "backlog",
                    "blocked", "done", "rejected")


def file_stub_tickets(clone, host, st, sha, new_red, report):
    """Face-1 auto-ticket: deterministic stub per NEW-RED job — repro command,
    range, log tail.  No analysis (that's face 2); slug = job name, so a job
    never gets a second ticket while one exists in any bucket."""
    filed = []
    for job in new_red:
        slug = "regression-" + re.sub(r"[^a-z0-9]+", "-", job.lower()).strip("-")
        pdir = os.path.join(clone.path, "devdocs/progress")
        if any(os.path.exists(os.path.join(pdir, b, slug + ".md"))
               for b in PROGRESS_BUCKETS):
            continue
        j = next((x for x in report["jobs"] if x["name"] == job), {})
        tail = ""
        if j.get("log") and os.path.exists(j["log"]):
            with open(j["log"], errors="replace") as f:
                tail = f.read()[-2000:]
        reg = next((r for r in st["open_regressions"] if r["job"] == job), {})
        rel = os.path.join("devdocs/progress/backlog", slug + ".md")
        with open(os.path.join(clone.path, rel), "w") as f:
            f.write("""---
prio: 70
---

# regression: %s red at %s (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host %s). Untriaged.
- **Found:** %s

## Repro
`tools/testmgr.py --tier %s --job '%s'` at %s

## Range
bad `%s`, last good `%s`, %d commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
%s
```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
""" % (job, sha[:12], host, utcnow(), report["tier"], job, sha,
                (reg.get("bad") or sha)[:12], (reg.get("good") or "unknown")[:12],
                len(reg.get("range", [])), tail))
        filed.append(rel)
    if filed:
        clone.publish("tstate-ticket(%s): %s" %
                      (host, ", ".join(os.path.basename(p) for p in filed)),
                      paths=filed)
        print("twatch: auto-filed %d stub ticket(s)" % len(filed), flush=True)


def clone_head_back(clone):
    sh(["git", "checkout", "--quiet", clone.branch], cwd=clone.path)


# A commit that only touches tickets/docs/tstate cannot change a test verdict,
# so it needs no gate run.  Without this filter the watcher full-tiers its own
# tstate commits forever: every publish moves the head it then retests
# (observed 2026-07-07: one ~300s full tier every ~5 min on an idle repo).
NOTEST_PREFIXES = ("devdocs/", "docs/")


def needs_test(repo, sha):
    out = sh(["git", "diff-tree", "--no-commit-id", "--name-only", "-r",
              "-m", "--first-parent", sha], cwd=repo)
    files = [f for f in out.splitlines() if f]
    return any(not f.startswith(NOTEST_PREFIXES) for f in files)


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
        red = any(j["status"] not in ("pass", "skip") for j in report["jobs"])
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
        if not needs_test(repo, sha):
            continue        # tickets/docs/tstate-only: no gate run owed
        if now - int(ct) > grace_min * 60:
            untested_old = (sha, int(ct))
            break
    for st in hosts:
        last = st.get("last") or {}
        lf = st.get("last_full") or {}
        print("tstate: host %-12s last %s %s (%s, %s)%s" %
              (st["host"], (last.get("sha") or "")[:12],
               last.get("verdict", "never"), last.get("tier", "?"),
               last.get("date", ""),
               "; full through %s %s" % (lf["sha"][:12], lf["verdict"])
               if lf.get("sha") else ""))
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
    ap.add_argument("--tier", default=None,
                    choices=["quick", "native", "limited", "full"])
    ap.add_argument("--fast-tier", default=None,
                    choices=["quick", "native", "limited", "full", "none"],
                    help="two-phase testing: a new push gets this fast verdict "
                         "immediately, then the full --tier backfills while "
                         "idle (a new push aborts and reclaims the box). "
                         "'none' or same as --tier = single-phase (default "
                         "native)")
    ap.add_argument("--host", default=socket.gethostname().split(".")[0])
    ap.add_argument("--interval", type=float, default=None, help="poll seconds")
    ap.add_argument("--debounce", type=float, default=None,
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

    # config file fills in whatever the CLI didn't say (CLI wins); interval /
    # autoticket / no_bisect reload every cycle so ./trackt config applies to
    # a running daemon without a restart
    conf = load_conf(clone.path)
    CONF.update(conf)
    if args.tier is None:
        args.tier = conf["tier"]
    if args.fast_tier is None:
        args.fast_tier = conf["fast_tier"]
    if args.interval is None:
        args.interval = conf["interval"]
    if args.debounce is None:
        args.debounce = conf["debounce"]
    if not args.no_bisect:
        args.no_bisect = conf["no_bisect"]

    errors = 0
    notest_logged = None
    while not STOP:
        did_work = False
        try:
            CONF.update(load_conf(clone.path))   # autoticket etc. apply live
            # re-check every cycle: an agent editing this checkout mid-run
            # must PAUSE the watcher, not feed it dirty sources (2026-07-07:
            # a dev edit leaked into a run, then killed the daemon on publish)
            dirty = clone.dirty()
            if dirty:
                print("twatch: clone dirty — pausing this cycle (commit or "
                      "stash to resume):\n%s" % dirty[:500], flush=True)
                if args.once:
                    return 1
                time.sleep(int(args.interval))
                continue
            clone.fetch()
            st = load_state(clone, host)
            head = clone.remote_head()
            tested = (st["last"] or {}).get("sha")
            fast = args.fast_tier if args.fast_tier not in ("none", args.tier) \
                else None
            do_test = False
            if head != tested:
                pending = clone.commits_between(tested, head) if tested else [head]
                do_test = not tested or any(needs_test(clone.path, c)
                                            for c in pending)
                if not do_test and head != notest_logged:
                    print("twatch: %s..%s is docs/tstate-only — no gate needed"
                          % ((tested or "")[:12], head[:12]), flush=True)
                    notest_logged = head
            if do_test:
                head = debounce(clone, args.debounce)
                if not STOP:
                    # act fast: a new push gets the fast native verdict first;
                    # the full matrix backfills below when the repo is quiet
                    r = test_sha(clone, host, st, head, fast or args.tier,
                                 full=not fast)
                    if r is False and fast:
                        # e.g. a SHA whose self-versioned testmgr predates the
                        # fast tier: fall back to the full tier, don't wedge
                        print("twatch: fast tier gave no report — falling "
                              "back to %s" % args.tier, flush=True)
                        test_sha(clone, host, st, head, args.tier, full=True)
                    did_work = True
            elif tested and fast and \
                    (st.get("last_full") or {}).get("sha") != tested:
                # idle: backfill the full matrix (cross + corpus) for the
                # newest fast-tested sha; a new push preempts it — the run is
                # SIGINTed and discarded, no verdict recorded
                def preempted():
                    if STOP:
                        return True
                    clone.fetch()
                    h = clone.remote_head()
                    if h == tested:
                        return False
                    # docs/tstate-only movement (e.g. our own fast-phase
                    # publish) must not abort the backfill it queued
                    return any(needs_test(clone.path, c)
                               for c in clone.commits_between(tested, h))
                test_sha(clone, host, st, tested, args.tier,
                         full=True, abort_check=preempted)
                did_work = True
            elif not args.no_bisect:
                st = load_state(clone, host)
                set_phase(clone, host, "bisect-check", head=head[:12])
                if not bisect_step(clone, host, st, args.tier):
                    if args.once:
                        print("twatch: up to date (%s), nothing to do" % head[:12],
                              flush=True)
            if not did_work:
                set_phase(clone, host, "idle", head=head[:12])
            errors = 0
        except (RuntimeError, subprocess.SubprocessError, OSError) as e:
            # transient git/network/infra failure must not kill the daemon;
            # persistent failure (10 straight) should, loudly
            errors += 1
            print("twatch: cycle failed (%d/10): %s" % (errors, e), flush=True)
            try:
                clone_head_back(clone)   # crash mid-test leaves HEAD detached
            except (RuntimeError, subprocess.SubprocessError, OSError):
                pass
            if errors >= 10:
                print("twatch: 10 consecutive failures — giving up", flush=True)
                return 1
            if args.once:
                return 1
        if args.once:
            break
        if did_work:
            continue        # more may be queued (full backfill, new head)
        for _ in range(int(args.interval)):
            if STOP:
                break
            time.sleep(1)
    set_phase(clone, host, "stopped")
    print("twatch: bye", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
