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
import calendar
import datetime
import fnmatch
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time

TSTATE_REL = "devdocs/progress/tstate"
INDEX_REL = TSTATE_REL + "/TSTATE.md"  # generated; the ONE co-written tstate file
WATCH_REL = ".testmgr/watch.json"     # daemon phase heartbeat for frontends
PUBHEALTH_REL = ".testmgr/pubhealth.json"  # publish outcome: quiet vs stuck
CONF_NAME = "twatch.conf"             # per-clone config (JSON, untracked)
CONF_DEFAULTS = {"tier": "full", "fast_tier": "native", "interval": 60,
                 "debounce": 20, "no_bisect": False,
                 "autoticket": True,   # stub regression tickets (face 1)
                 "idle_opt": True,     # idle: O-level differential sweep
                 "idle_bench": True,   # idle: tracked benchmark timings
                 "idle_fuzz": True,    # idle: pasmith/fuzz.sh (endless, lowest prio)
                 "fuzz_minutes": 10,   # time-box per idle fuzz slice
                 # Rate limit. While a finding is OPEN (filed, not yet fixed), fuzz
                 # slices are spaced this far apart instead of running every idle
                 # tick: the lane that owns the bug gets room to fix it, and we stop
                 # re-finding what we already reported. Zero open findings = no
                 # throttle at all. See run_fuzz_idle.
                 "fuzz_backoff_minutes": 90,
                 # resource ceilings for a shared/small box (the wizard's
                 # limited/restricted profiles). 0 = no cap (use the box).
                 "max_cores": 0,       # cap testmgr concurrency (--jobs N)
                 "max_mem_mb": 0,      # cap the cgroup MemoryMax (env override)
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


def kill_child(proc, grace=30):
    """Tear down a running testmgr: SIGINT (clean teardown), then SIGKILL.

    SIGINT first because testmgr handles it and kills its own job process groups
    — that is what stops orphaned qemu/compiler children being left behind. But
    it must not be trusted indefinitely: a testmgr wedged badly enough to ignore
    SIGINT is exactly the case where a stop has to still stop. Hence the grace,
    then the hammer. Group-kill (the child was started with start_new_session,
    so it leads its own group) so nothing under it survives either.
    """
    try:
        os.killpg(proc.pid, signal.SIGINT)
        proc.wait(timeout=grace)
        return
    except ProcessLookupError:
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        pass


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
        """Poll origin WITHOUT touching FETCH_HEAD.

        The daemon fetches every `interval` seconds, forever, in a clone a human
        or agent also runs git in (deploying new tooling, inspecting a report).
        A background fetch that writes FETCH_HEAD while a foreground
        `git pull --rebase` is reading it leaves a truncated/multi-line file and
        the pull dies with `fatal: Cannot rebase onto multiple branches`.
        Nothing here ever reads FETCH_HEAD — we resolve `origin/<branch>` — so
        writing it is pure downside. Explicit refspec for the same reason:
        never depend on the clone's fetch config.  (Diagnosed on borg
        2026-07-31; the rule is in two-box-protocol.md.)"""
        sh(["git", "fetch", "--quiet", "--no-write-fetch-head", "origin",
            "+refs/heads/%s:refs/remotes/origin/%s" % (self.branch, self.branch)],
           cwd=self.path)

    def remote_head(self):
        return sh(["git", "rev-parse", "origin/%s" % self.branch], cwd=self.path)

    def checkout(self, sha):
        sh(["git", "checkout", "--quiet", "--detach", sha], cwd=self.path)

    def commits_between(self, good, bad):
        """SHAs strictly after `good` up to and including `bad`, oldest first."""
        out = sh(["git", "rev-list", "--reverse", "%s..%s" % (good, bad)],
                 cwd=self.path)
        return out.splitlines() if out else []

    def _pull_rebase(self, resolve_index=False):
        """pull --rebase, but never leave a half-applied rebase behind: on any
        conflict/failure, `git rebase --abort` so the daemon can't wedge in a
        UU state (observed 2026-07-11: committed generated html conflicted and
        the publish loop span forever). Returns True on a clean rebase, False
        on conflict/failure (already aborted) — the caller decides how to
        recover; it must NOT strand the local commit (see _drop_to_origin).

        `resolve_index=True` first tries the one conflict that is expected and
        meaningless (the generated TSTATE.md index) before giving up."""
        try:
            sh(["git", "pull", "--rebase", "--quiet", "origin", self.branch],
               cwd=self.path)
            return True
        except RuntimeError:
            if resolve_index and self._resolve_index_conflict():
                return True
            sh(["git", "rebase", "--abort"], cwd=self.path, check=False)
            return False

    def _resolve_index_conflict(self):
        """Regenerate TSTATE.md instead of merging it, then continue the rebase.

        Every watcher host rewrites the WHOLE index table, including the other
        hosts' rows, so with two hosts live the index conflicts on essentially
        every overlapping publish — and `_drop_to_origin` then throws away a
        perfectly good verdict (xeon lost the f3d420def527 RED this way,
        2026-07-31). The per-host `<host>.json` / `runs-<host>.ndjson` files
        never conflict; they are single-writer.

        The index is a PURE FUNCTION of those json files, so there is nothing
        to merge: take origin's side wholesale by rebuilding it from whatever
        state won the race. Deliberately narrow — if anything other than the
        index is unmerged, this refuses and the caller drops as before, because
        a real conflict in published state is a bug we want to see, not
        silently paper over."""
        try:
            unmerged = sh(["git", "diff", "--name-only", "--diff-filter=U"],
                          cwd=self.path).split()
        except RuntimeError:
            return False
        if unmerged != [INDEX_REL]:
            return False
        try:
            regen_index(self)
            sh(["git", "add", "--", INDEX_REL], cwd=self.path)
            # -c core.editor=true: --continue must never wait on an editor
            sh(["git", "-c", "core.editor=true", "rebase", "--continue"],
               cwd=self.path)
        except RuntimeError:
            return False
        print("twatch: regenerated %s over a rebase conflict (expected with "
              "two hosts) — verdict kept" % os.path.basename(INDEX_REL),
              flush=True)
        return True

    def _behind(self):
        """How many commits the clone is behind origin (0 when caught up).
        Cheap health signal; None if it can't be computed."""
        try:
            n = sh(["git", "rev-list", "--count",
                    "HEAD..origin/%s" % self.branch], cwd=self.path)
            return int(n) if n else 0
        except (RuntimeError, ValueError):
            return None

    def _record_pub(self, result, reason=""):
        """Persist a publish outcome to PUBHEALTH_REL so `trackt status` and the
        web UI can tell a HEALTHY-but-quiet daemon from one that is alive but
        UNABLE to publish. Before 2026-07-15 that distinction was invisible: the
        daemon kept running (phase=testing/idle) while every publish failed, and
        the only signal was the coverage line drifting to a vague 'DOWN'.

        result: 'pushed' (clears the drop streak) | 'dropped' (a cycle was
        thrown away — increments the streak that flags a stuck daemon)."""
        p = os.path.join(self.path, PUBHEALTH_REL)
        h = {}
        try:
            with open(p) as f:
                h = json.load(f)
        except (OSError, ValueError):
            pass
        now = time.time()
        if result == "dropped":
            h["consec_drops"] = h.get("consec_drops", 0) + 1
            h.setdefault("drops_since", now)
            h["last_drop_ts"] = now
            h["last_reason"] = reason
        elif result == "pushed":
            h["consec_drops"] = 0
            h.pop("drops_since", None)
            h["last_push_ts"] = now
            h["last_reason"] = ""
        h["ts"] = now
        h["behind"] = self._behind()
        write_json_atomic(p, h)

    def _drop_to_origin(self, reason="rebase conflict onto origin"):
        """A tstate publish couldn't rebase onto origin — typically because a
        co-edited data file (bench.tsv, borg.json) was reformatted by a HUMAN
        commit and our append conflicts line-for-line. Per Track T's
        latest-only model a stale verdict is worthless, so DROP this cycle's
        local tstate commit(s) rather than strand them: `reset --hard` to the
        fresh origin tip. The next cycle recomputes tstate against origin's
        current format and publishes cleanly.

        This is the guard against the 2026-07-15 incident: the old code aborted
        the rebase but LEFT the commit, so every following cycle piled another
        unpushable tstate commit on top (75 stranded, master 94 behind) and
        publishing stalled for ~11h. reset-to-origin also auto-drains any such
        pre-existing pile on the very next publish. The drop is recorded to
        pubhealth so a REPEATED drop (a conflict it can't clear) surfaces as a
        loud health warning instead of a silent quiet daemon."""
        self.fetch()
        sh(["git", "reset", "--hard", "origin/%s" % self.branch], cwd=self.path)
        self._record_pub("dropped", reason)
        print("twatch: publish conflicted with origin (%s) — dropped this "
              "cycle's tstate commit; will republish against fresh origin next "
              "cycle" % reason, flush=True)

    def publish(self, message, paths=None):
        """Commit ONLY the given paths (default: tstate) onto the branch tip
        and push, with rebase-retry so parallel watcher hosts don't fight.
        Only tracked, non-ignored files under `paths` are committed — the
        generated tstate/*.html dashboard is gitignored on purpose (every
        writer would otherwise collide on it), so this publishes just the
        source-of-truth data (bench.tsv, conformance.tsv, runs/regressions).

        A conflict is never fatal and never strands: on any failed rebase the
        local commit is dropped (latest-only), so a busy origin can at worst
        cost this cycle's publish, not wedge the daemon."""
        paths = list(paths or [TSTATE_REL])
        sh(["git", "checkout", "--quiet", self.branch], cwd=self.path)
        sh(["git", "add", "--"] + paths, cwd=self.path)
        if not sh(["git", "status", "--porcelain", "--"] + paths, cwd=self.path):
            return
        sh(["git", "commit", "--quiet", "-m", message, "--"] + paths,
           cwd=self.path)
        if not self._pull_rebase(resolve_index=True):
            self._drop_to_origin("rebase conflict onto origin")
            return
        for attempt in range(5):
            try:
                sh(["git", "push", "--quiet", "origin", self.branch], cwd=self.path)
                self._record_pub("pushed")
                return
            except RuntimeError:
                time.sleep(2 + attempt * 3)
                if not self._pull_rebase(resolve_index=True):
                    self._drop_to_origin("rebase conflict onto origin")
                    return
        # push kept being rejected without a rebase conflict (origin racing us
        # every attempt): drop rather than raise, so the daemon loop survives.
        self._drop_to_origin("push rejected after 5 attempts (origin racing)")


# ---------------------------------------------------------------- testing --
def run_gate(clone, tier, job_glob=None, abort_check=None, _reseeded=False):
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
    # resource ceilings (limited/restricted profiles). Concurrency is a testmgr
    # CLI arg; the mem cap is an env override read by reexec_scoped().
    env = dict(os.environ)
    if CONF.get("max_cores"):
        cmd += ["--jobs", str(int(CONF["max_cores"]))]
    if CONF.get("max_mem_mb"):
        env["TESTMGR_MEM_CAP_MB"] = str(int(CONF["max_mem_mb"]))
    proc = subprocess.Popen(cmd, cwd=clone.path, start_new_session=True, env=env)
    last_check = time.monotonic()
    wp = os.path.join(clone.path, WATCH_REL)
    while proc.poll() is None:
        time.sleep(1)
        # STOP (SIGTERM/SIGINT) must tear the gate down HERE, every second.
        # The signal handler only sets the flag, and the flag was previously only
        # read between cycles -- but the daemon spends nearly all of its life
        # right here, blocked on a testmgr child that can have several minutes of
        # work left. So `trackt stop` would sit through the whole remaining gate,
        # hit its 120s patience, and tell the user to `kill -9` by hand. Its own
        # message ("aborts any running gate") was simply not true.
        if STOP:
            print("twatch: stopping — tearing down the running %s gate" % tier,
                  flush=True)
            kill_child(proc)
            return None, "aborted"
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
                kill_child(proc)
                return None, "aborted"
    if not os.path.exists(rep_path):
        # testmgr died before reporting. One likely cause: a STALE seed
        # binary that cannot compile HEAD's sources (e.g. a since-fixed
        # compiler bug rejects new valid code — WsPos incident 2026-07-11).
        # Recovery: reseed from the committed pinned stable and retry once;
        # without this the watcher wedges retesting the same SHA forever.
        if not _reseeded and proc.returncode:
            print("twatch: no report (rc=%s) — reseeding compiler from "
                  "pinned stable and retrying once" % proc.returncode,
                  flush=True)
            try:
                if os.path.exists(comp):
                    os.unlink(comp)        # unlink works even while running
                subprocess.run(["make", "--no-print-directory",
                                "seed-from-stable"],
                               cwd=clone.path, check=True)
                os.utime(comp, (0, 0))     # backdate: see CRITICAL above
            except (OSError, subprocess.CalledProcessError) as e:
                print("twatch: reseed failed (%s)" % e, flush=True)
                return None, proc.returncode
            return run_gate(clone, tier, job_glob=job_glob,
                            abort_check=abort_check, _reseeded=True)
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


# Corpus trees the full tier expects (same set twatch-setup.sh provisions, plus
# fpc-testsuite for the Pascal conformance suite).  Jobs referencing an absent
# tree SKIP — and a skipped job is invisible in a GREEN verdict, so a watcher
# missing a corpus quietly publishes "green" for tests it never ran.  That is
# how the i386/arm32/riscv32 c-conformance reds stayed hidden on a box without
# c-testsuite.  A watcher must be loud about this on startup.
CORPUS_EXPECTED = ("lua", "sqlite", "zlib", "c-testsuite", "tcc", "cjson",
                   "tiny-regex-c", "fpc-testsuite")


def missing_corpus(path):
    return [t for t in CORPUS_EXPECTED
            if not os.path.isdir(os.path.join(path, "library_candidates", t))]


def warn_missing_corpus(path, fetch=False):
    """Warn (or, with --fetch-corpus, just install) the absent corpus trees."""
    missing = missing_corpus(path)
    if not missing:
        return
    cmd = ["tools/install_lib_candidates.sh"] + missing
    if fetch:
        print("twatch: fetching missing corpus: %s" % " ".join(missing),
              flush=True)
        rc = subprocess.run(cmd, cwd=path).returncode
        if rc == 0 and not missing_corpus(path):
            print("twatch: corpus complete", flush=True)
            return
        print("twatch: corpus fetch failed (rc=%s) — continuing with gaps" % rc,
              flush=True)
        missing = missing_corpus(path)
        if not missing:
            return
    bar = "!" * 72
    print("\n  %s\n"
          "  !! CORPUS MISSING on this watcher: %s\n"
          "  !! Jobs touching these trees will SKIP — and a skipped job looks\n"
          "  !! exactly like a passing one in a GREEN verdict. This watcher is\n"
          "  !! publishing coverage it does not actually have.\n"
          "  !!\n"
          "  !! Fix (gitignored, nothing enters the repo):\n"
          "  !!   cd %s && %s\n"
          "  !! Or re-run twatch with --fetch-corpus to do it now.\n"
          "  %s\n" % (bar, " ".join(missing), path, " ".join(cmd), bar),
          flush=True)


def reg_slug(sel):
    """Ticket slug for a regression, derived from the STABLE selector.

    `test-core#src:test/test_c_gtk_window.pas` -> regression-test-core-gtk-window.
    Slugging the job NUMBER instead (the old behaviour) meant a renumbering
    could file a second ticket for a test that already had one.
    """
    if "#src:" in sel:
        target, path = sel.split("#src:", 1)
        stem = os.path.splitext(os.path.basename(path))[0]
        sel = "%s-%s" % (target, stem)
    return "regression-" + re.sub(r"[^a-z0-9]+", "-", sel.lower()).strip("-")


def covered_tiers(tier):
    """Which tiers' JOBS a run at `tier` actually contains.

    testmgr's tiers nest for the regression matrix — full includes what native
    includes, and so on — but `opt` is DISJOINT: `optdiff#*` / `test-opt#*` are
    built only under `tier == "opt"` and appear in no other tier. That asymmetry
    is the whole reason a full run must not evict opt's verdicts.
    """
    nested = ["quick", "native", "limited", "full"]
    if tier in nested:
        return set(nested[:nested.index(tier) + 1])
    return {tier}                     # opt (and any future disjoint tier)


def job_key(j):
    """Identity of a job ACROSS commits.

    Not j["name"]: `test-core#665` is a positional index into the target's
    recipe lines, so inserting one test renumbers every job after it — and then
    this dict silently compares yesterday's #665 against a different test today,
    manufacturing NEW-RED/FIXED pairs out of nothing.  testmgr publishes "sel"
    (`test-core#src:test/foo.pas`), which names the job by the source it
    compiles.  Fall back to the name for reports written by a testmgr older
    than that field (bisect runs the CLONE's testmgr, at the commit under test).
    """
    return j.get("sel") or j["name"]


def reg_open(r, fixed, authoritative):
    """Is this ledger entry still an open regression after the latest run?

    A per-job entry closes when its job is in `fixed`.  A CASCADE entry names
    no single job (its "job" is a synthetic cascade@<sha> key that can never
    appear in `fixed`), so it closes only once every job it swept up is
    genuinely passing again — otherwise it would pin itself open forever.

    `authoritative` is the MERGED per-job status (persisted st["jobs"] overlaid
    with this run's results), NOT just this run's `now`.  Using this run alone
    closed a cascade whenever ONE run happened to show every swept job as
    non-red — which bit us 2026-07-20/21: the riscv32 record-result cascade
    (18 jobs) closed off a single lucky full run, then the jobs failed again as
    STILL-RED (filing nothing), so 17 jobs sat `fail` in the jobs map with the
    cascade gone from open_regressions.  Against the merged map a job that is
    still `fail` in the persisted state keeps the cascade open even when this
    tier did not run it.

    A `skip` is mapped to `pass` by diff_jobs (corpus-absent is pass-equivalent
    for a normal verdict), but it is NOT proof a regression is fixed — so a
    cascade whose jobs only ever SKIP would wrongly close.  That is a known
    residual; the merged-map fix removes the common transient-flake close, which
    is what actually happened here.
    """
    if r.get("cascade"):
        return any(authoritative.get(j, "red") != "pass" for j in r["cascade"])
    return r["job"] not in fixed


def diff_jobs(prev_jobs, report):
    # "skip" (corpus tree absent on this box) is pass-equivalent: the job is
    # not applicable here, and mapping it to pass closes any open regression
    now = {job_key(j): ("pass" if j["status"] == "skip" else j["status"])
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
    # stable key -> source file(s), so a reader sees WHICH test without
    # mapping job numbers back to Makefile lines (numbers shift with edits)
    srcmap = {job_key(j): j.get("src", "") for j in report["jobs"]}
    def label(n):
        return "%s — %s" % (n, srcmap[n]) if srcmap.get(n) else n
    for title, names in (("NEW-RED", new_red), ("FIXED", fixed),
                         ("STILL-RED", still_red)):
        if names:
            lines.append("## %s" % title)
            lines += ["- %s" % label(n) for n in names]
            lines.append("")
    first = next((j for j in report["jobs"]
                  if j["status"] not in ("pass", "skip")), None)
    if first:
        lines.append("## first failure: %s (%s)" % (label(job_key(first)),
                                                    first["status"]))
        lines.append("repro: `tools/testmgr.py --tier %s --job '%s'` at %s"
                     % (report["tier"], job_key(first), sha))
        log = first.get("log")
        if log and os.path.exists(log):
            lines.append("```")
            with open(log, errors="replace") as f:
                body = f.read()
            diag = diagnostic_lines(body)
            if diag:
                lines.append("(diagnostics)")
                lines.append(diag)
                lines.append("(tail)")
            lines.append(body[-4000:])
            lines.append("```")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return rel


# Lines worth hoisting out of a job log ahead of the raw tail. Deliberately
# narrow — an anchored `error:`/`Error:` shape and the compilers' own fatal
# forms — because the value is that a hoisted line is ALWAYS the failure, never
# a warning that merely says "error" somewhere in its prose.
DIAG_RE = re.compile(
    r"\berror\s*:|\bfatal\s*:|\bfatal error\b|\bassertion\b.*failed"
    r"|\bsegmentation fault\b|\btext file busy\b|\bdiffer:"
    r"|\bundefined reference\b", re.I)
DIAG_MAX = 12          # keep the hoist short; the tail is right underneath


def diagnostic_lines(body):
    """Pull the actual error lines out of a job log.

    A raw tail is the wrong thing to read when a compiler fails: FPC emits
    thousands of warnings AFTER the error that stopped it, so the last 4000
    characters of a seed-build failure are `Comment level 2 found` and the one
    line that matters is nowhere in the report. That happened three times on
    2026-08-02 (three separate FPC seed drifts), and each cost a full local
    reproduction to learn a fact the log already contained.

    Hoisting is additive: the tail is still printed underneath, so nothing that
    used to be visible is lost and a failure whose signature is not matched
    reads exactly as before.
    """
    hits = []
    for line in (body or "").splitlines():
        line = line.strip()
        if line and DIAG_RE.search(line) and line not in hits:
            hits.append(line)
            if len(hits) >= DIAG_MAX:
                break
    return "\n".join(hits)


def ticket_suppression(had_baseline, n_new_red, n_jobs):
    """Why this run's regression tickets are suppressed, or None to file them.

    Gates TICKET FILING only — the verdict, the job map and the report are
    published either way. A false ticket is worse than a false tstate row: it
    lands on the board at prio 70, names an innocent sha, and costs another
    agent a triage cycle before anyone even looks at the box.
    """
    if not had_baseline:
        return ("first run on this host: with no baseline every red is 'new', "
                "so NEW-RED carries no information yet")
    if n_new_red and n_new_red > INFRA_FAULT_FRAC * max(1, n_jobs):
        return ("%d of %d jobs newly red (>%.0f%%): an environment or infra "
                "fault, not a code change"
                % (n_new_red, n_jobs, INFRA_FAULT_FRAC * 100))
    return None


def host_quiet_secs(st, now=None):
    """How long since this host last published a verdict, or None if fresh.

    Reads `last.date` (ISO-8601 Z, written by publish) rather than any file
    mtime: in a watcher clone the working tree is a snapshot of the sha under
    test and mtimes are rewritten by every checkout
    (task-t-worktree-is-not-current-state).
    """
    date = ((st.get("last") or {}).get("date") or "").strip()
    if not date:
        return None                  # never ran: not the same thing as quiet
    try:
        seen = calendar.timegm(time.strptime(date, "%Y-%m-%dT%H:%M:%SZ"))
    except ValueError:
        return None
    age = (now if now is not None else time.time()) - seen
    return age if age > QUIET_HOST_SECS else None


def fmt_age(secs):
    days, rem = divmod(int(secs), 86400)
    return "%dd%dh" % (days, rem // 3600) if days else "%dh" % (rem // 3600)


def regen_index(clone):
    tdir = os.path.join(clone.path, TSTATE_REL)
    rows, regs, held = [], [], []
    for fn in sorted(os.listdir(tdir)):
        if not fn.endswith(".json"):
            continue
        with open(os.path.join(tdir, fn)) as f:
            st = json.load(f)
        last = st.get("last") or {}
        lf = st.get("last_full") or {}
        quiet = host_quiet_secs(st)
        rows.append("| %s%s | `%s` | %s | %s (%s) | %ss | `%s` %s |" %
                    (st["host"], " **QUIET %s**" % fmt_age(quiet) if quiet else "",
                     (last.get("sha") or "")[:12],
                     last.get("date", ""), last.get("verdict", "never-ran"),
                     last.get("tier", "?"), last.get("wall", ""),
                     (lf.get("sha") or "")[:12], lf.get("verdict", "")))
        if quiet:
            # A quiet host's entries move to their own section: they are real
            # history, but only a run on THAT host can ever clear them.
            held.extend(
                "- **%s** (%s, quiet %s): bad `%s`, %d commit(s) in range"
                % (("CASCADE %d jobs" % len(r["cascade"])) if r.get("cascade")
                   else r["job"], st["host"], fmt_age(quiet), r["bad"][:12],
                   len(r.get("range", [])))
                for r in st.get("open_regressions", []))
            continue
        for r in st.get("open_regressions", []):
            if r.get("cascade"):
                # one event, one line — the job list goes in a fold so the
                # index stays readable when a whole cross matrix goes red
                regs.append(
                    "- **CASCADE %d jobs** (%s): bad `%s`, last good `%s`, "
                    "%d commit(s) in range\n"
                    "  <details><summary>jobs</summary>\n\n%s\n  </details>"
                    % (len(r["cascade"]), st["host"], r["bad"][:12],
                       (r.get("good") or "unknown")[:12],
                       len(r.get("range", [])),
                       "\n".join("  - `%s`" % j for j in r["cascade"])))
                continue
            regs.append("- **%s**%s (%s): bad `%s`, last good `%s`, %d commit(s) in range"
                        % (r["job"],
                           " — %s" % r["src"] if r.get("src") else "",
                           st["host"], r["bad"][:12],
                           (r.get("good") or "unknown")[:12],
                           len(r.get("range", []))))
    out = ["# TSTATE — Track T watcher index (generated by tools/twatch.py)", "",
           "| host | last tested | date | verdict | wall | full through |",
           "|------|-------------|------|---------|------|--------------|"] + rows + [""]
    out.append("## Open regressions")
    out += regs if regs else ["- none"]
    out.append("")
    if held:
        out.append("## Held — quiet hosts (not actionable)")
        out.append("")
        out.append("A regression clears when a later run on THAT host passes "
                   "the job. These hosts have stopped publishing, so nothing "
                   "can clear them; they return to the list above by "
                   "themselves if the host runs again.")
        out.append("")
        out += held
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

    # INVALID: the compiler changed underneath the run, so its PASS/FAIL cannot
    # be attributed to one binary. Treated exactly like "no report" — publish
    # nothing, diff nothing, file nothing. A red from a mixed run is as
    # untrustworthy as a green, and auto-filing from one is precisely how the
    # phantom-red family gets fed. The sha stays untested, so the next cycle
    # retests it honestly.
    if report.get("verdict") == "INVALID":
        print("twatch: %s INVALID — compiler changed mid-run (%s); discarding "
              "this run's verdict and retesting next cycle"
              % (sha[:12], (report.get("compiler_sha256") or "?")[:12]),
              flush=True)
        return False

    parent = (st["last"] or {}).get("sha")
    # Captured BEFORE the diff, because the diff is what consumes it. NEW-RED
    # means "red now, green in this host's recorded map", and on a host's first
    # run that map is empty — `prev_jobs.get(n, "pass")` then defaults every
    # unknown job to pass, so EVERY red is new. The verdict and the job map are
    # honest and get published; what must not happen is filing tickets or
    # opening ledger entries from a diff against nothing.
    had_baseline = bool(st["jobs"])
    now, new_red, fixed, still_red = diff_jobs(st["jobs"], report)
    no_ticket = ticket_suppression(had_baseline, len(new_red),
                                   len(report["jobs"]))

    # open-regression bookkeeping.  Two invariants keep this ledger a list of
    # REAL, actionable regressions instead of a dump of every red job:
    #
    #  1. EMPTY RANGE.  When the last tested sha IS this sha (the two-phase
    #     watcher re-testing one commit at a widening tier: native, then the
    #     full backfill), commits_between() is empty.  Such a "regression"
    #     names no commit that could have caused it — unbisectable and
    #     unfalsifiable.  It is a tier/harness event, not a code change.
    #  2. CASCADE.  A sweep above CASCADE_THRESHOLD is ONE event (broken
    #     build, or a red root job dragging every dependent down), so it gets
    #     ONE entry — the rule file_stub_tickets already applies to ticket
    #     filing.  Applying it only there is why 2026-07-20 a single
    #     cross-target collapse produced 1 ticket but 461 ledger rows, all
    #     with 0 commits in range.
    #
    # Neither case is dropped silently: the per-job red still lands in
    # st["jobs"] and in the written report, so the signal survives without the
    # ledger claiming N independent bisectable regressions that don't exist.
    # Cascade close is judged against the MERGED map (what we knew, overlaid
    # with what this run showed), so a cascade cannot close off one lucky run
    # while its jobs remain red in the persisted state. See reg_open.
    authoritative = dict(st["jobs"], **now)
    regs = [r for r in st["open_regressions"] if reg_open(r, fixed, authoritative)]
    # The entries this filter DROPS are exactly the regressions the ledger
    # considers closed, so they are also exactly the stubs face 1 may retire —
    # one rule, not a second invented one that could disagree with it.
    closed_regs = [r for r in st["open_regressions"]
                   if not reg_open(r, fixed, authoritative)]
    srcmap = {job_key(j): j.get("src", "") for j in report["jobs"]}
    namemap = {job_key(j): j["name"] for j in report["jobs"]}
    rng = clone.commits_between(parent, sha) if parent else [sha]
    if new_red and not had_baseline:
        # Same treatment as the empty-range case, and for the same reason: the
        # entries would name a sha that cannot have caused them. This run's
        # statuses still land in st["jobs"], which IS the baseline the next run
        # produces real NEW-RED against.
        print("twatch: %d red at %s recorded as this host's BASELINE — no "
              "ledger entries, no tickets (%s)"
              % (len(new_red), sha[:12], no_ticket), flush=True)
    elif new_red and not rng:
        print("twatch: %d new red at %s but 0 commits since the last tested "
              "sha — not localizable; recording job status only"
              % (len(new_red), sha[:12]), flush=True)
    elif len(new_red) > CASCADE_THRESHOLD:
        print("twatch: %d new red at %s — cascade, one ledger entry"
              % (len(new_red), sha[:12]), flush=True)
        regs.append({"job": "cascade@" + sha[:12], "name": "", "src": "",
                     "cascade": sorted(new_red), "bad": sha, "good": parent,
                     "range": rng, "opened": utcnow()})
    else:
        for name in new_red:
            # "job" is the stable selector; "name" is the positional name it
            # had at this sha — kept ONLY as the bisect fallback for older
            # commits, never as identity (see job_key).
            regs.append({"job": name, "name": namemap.get(name, ""),
                         "src": srcmap.get(name, ""), "bad": sha,
                         "good": parent, "range": rng, "opened": utcnow()})
    st["open_regressions"] = regs

    changed = bool(new_red or fixed)
    rel = None
    if changed or report["verdict"] == "RED":
        rel = write_report_md(clone, host, sha, parent, report,
                              new_red, fixed, still_red)

    st["last"] = {"sha": sha, "date": utcnow(), "verdict": report["verdict"],
                  "wall": report["wall"], "tier": report["tier"]}
    if full:
        # Evict by COVERAGE, not wholesale.
        #
        # The intent of replacing here is to drop jobs that no longer exist in
        # the suite. But a full run's job set contains no `optdiff#*` /
        # `test-opt#*` at all — those are built only under `tier == "opt"` — so
        # a blind replace evicted every opt verdict. The next opt run then found
        # them absent, and `prev_jobs.get(n, "pass")` counts an absent job as
        # having PASSED, so a red that never changed re-reported as NEW-RED,
        # once per cycle, forever. (Observed 2026-08-01: optdiff#shard5/6 NEW-RED
        # at 21:33 and again at 22:00 with nothing in between but a full run.)
        #
        # A run may only evict jobs it was CAPABLE of running. Keys last written
        # by a tier this run does not cover are carried forward untouched.
        # Unknown tier (state written before job_tier existed) defaults to
        # "covered", i.e. the old evict-it behaviour — so legacy keys can never
        # become sticky-forever, and the map self-heals as tiers get recorded.
        cov = covered_tiers(report["tier"])
        keep = {k: v for k, v in st["jobs"].items()
                if k not in now
                and st.get("job_tier", {}).get(k, report["tier"]) not in cov}
        st["jobs"] = dict(keep, **now)
        st["last_full"] = dict(st["last"])
    else:
        st["jobs"] = dict(st["jobs"], **now)
    # remember which tier last spoke for each job, so the rule above can tell
    # "this run could have run it and didn't -> gone" from "not my tier".
    st["job_tier"] = dict(st.get("job_tier", {}),
                          **{k: report["tier"] for k in now})
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
        msg += (" BASELINE:%d red" % len(new_red) if not had_baseline
                else " NEW-RED:" + ",".join(new_red[:5]))
    if fixed:
        msg += " FIXED:" + ",".join(fixed[:5])
    clone.publish(msg)
    if new_red and CONF.get("autoticket") and no_ticket:
        print("twatch: NOT filing a regression ticket — %s" % no_ticket,
              flush=True)
    elif new_red and CONF.get("autoticket"):
        file_stub_tickets(clone, host, st, sha, new_red, report, parent)
    if closed_regs and CONF.get("autoticket"):
        close_stub_tickets(clone, host, closed_regs, sha, report)
    print("twatch: %s %s%s" % (sha[:12], report["verdict"],
                               " report=" + rel if rel else ""), flush=True)
    return True


PROGRESS_BUCKETS = ("urgent", "working", "unfinished", "backlog",
                    "blocked", "done", "rejected")


# A sweep that turns MORE than this many jobs newly red is a cascade — one
# root cause (a broken compiler build, a red fpc-bootstrap taking every
# FPC-dependent job down with it), not N independent regressions.  Filing a
# stub per job buries the signal: 2026-07-18 a single missing FPC-seed
# forward produced 939 tickets.  Above the threshold, file ONE cascade
# ticket naming the whole set instead.
CASCADE_THRESHOLD = 10

# A sweep that turns more than this FRACTION of the matrix newly red is an
# environment or infra fault, not a code regression — a commit that breaks a
# quarter of N unrelated subsystems at once essentially does not exist. xeon's
# first run blamed 17 jobs on 110774a14648, a tstate-ONLY commit that touches
# no code; all 17 were missing host packages (libgtk2.0-dev, libsqlite3-dev,
# tk-dev, libc6:i386) plus a stale seed. The cascade rule above already
# collapses that to one ledger entry; this decides whether it is worth a
# TICKET, which lands at prio 70, names an innocent sha, and costs another
# agent a triage cycle.
INFRA_FAULT_FRAC = 0.25

# How many open-regression lines `--status` prints before summarizing. It is a
# pre-push liveness check: the UP/DOWN verdict must stay visible.
STATUS_REG_CAP = 12

# A host that has not published a verdict in this long is QUIET, and its open
# regressions are held rather than mixed into the live list.
#
# A regression clears when a later run ON THAT HOST passes the job — verdicts
# are per host by design, since the toolchain gap between boxes is the point.
# So a host that stops running leaves entries nothing can ever clear: borg's
# watcher stopped on 2026-07-31 with one open, and every --status and
# `gate.sh check` since has printed `fpc-bootstrap#src:compiler/compiler.pas`
# as if it were live. It reads exactly like a bootstrap break, so each new
# agent re-investigates it, and the habit it really trains is skimming the
# open-regression lines — which is how a REAL one gets missed.
#
# Time, not a flag, because borg is still the dev box and may run the watcher
# again now and then (user, decide-t-queue-scope-2026-08-03): quietness is a
# property of the clock, so this reverses itself the moment the host publishes
# and there is no `retire` anyone can forget to undo. Held, never hidden — a
# host going quiet unnoticed is its own failure mode, and noticing a stopped
# watcher is what --status is FOR.
QUIET_HOST_SECS = 2 * 86400

# Jobs whose red predictably drags a whole dependent class down — listed in
# the cascade ticket as root-cause suspects when present in the red set.
CASCADE_ROOT_JOBS = ("fpc-bootstrap", "selfhost-fixedpoint")


def revert_of_range(clone, sha, parent):
    """Has anything in (parent, sha] already been REVERTED on origin/master?

    Returns (revert_sha, reverted_subject) or None.

    The case this exists for, measured 2026-08-01:

        02:50:11Z  b93577cd3  fix(A): const Variant expr args   <- broke 60 jobs
        02:52:11Z  610936615  Revert "fix(A): ..."              <- author caught it
        02:56:29Z             watcher publishes the 60-job cascade
        02:56:33Z             autoticket files it, reading as a live emergency

    The report was CORRECT about the sha it named; the ticket was four minutes
    stale on arrival, and cost two agents a triage cycle each — one recommended
    reverting an already-reverted commit, the other concluded "transient, never
    broken" from a green HEAD.

    Note this deliberately does NOT use `merge-base --is-ancestor`, the obvious
    check: a revert ADDS a commit, it never removes the bad one, so the tested
    sha remains a perfectly good ancestor of origin/master and ancestry always
    passes. Ancestry only catches a rebase/force-push. What distinguishes "still
    broken" from "already fixed" is behaviour, and matching revert subjects is
    the cheapest honest proxy for it — no checkout, no build, pure git.
    """
    if not parent:
        return None
    try:
        suspects = {}
        for ln in sh(["git", "log", "--format=%H\x1f%s",
                      "%s..%s" % (parent, sha)], cwd=clone.path).splitlines():
            h, _, subj = ln.partition("\x1f")
            if subj:
                suspects[subj.strip()] = h
        if not suspects:
            return None
        for ln in sh(["git", "log", "--format=%H\x1f%s",
                      "%s..origin/master" % sha],
                     cwd=clone.path).splitlines():
            h, _, subj = ln.partition("\x1f")
            subj = subj.strip()
            if not subj.startswith('Revert "'):
                continue
            undone = subj[len('Revert "'):].rstrip('"')
            if undone in suspects:
                return (h, undone)
    except (RuntimeError, OSError):
        return None                      # never let staleness checking break publishing
    return None


def staleness_note(clone, sha, parent):
    """Markdown telling the reader how stale this ticket already is.

    Cheap by construction: two `git log`s and a `rev-list --count`, no checkout
    and no build, so it can sit in the publish path unconditionally.
    """
    try:
        behind = sh(["git", "rev-list", "--count", "%s..origin/master" % sha],
                    cwd=clone.path).strip()
    except (RuntimeError, OSError):
        behind = ""
    rev = revert_of_range(clone, sha, parent)
    if rev:
        return ("> **LIKELY ALREADY FIXED — verify before acting.** `%s` on "
                "origin/master reverts `%s`, which is in this sha's range. The "
                "failures below were real at `%s`, but the cause may already be "
                "gone. Re-check at current origin/master first; a green HEAD "
                "here means *already fixed*, not *never broken*.\n"
                % (rev[0][:12], rev[1], sha[:12]))
    if behind and behind != "0":
        return ("> **origin/master has advanced %s commit(s) since this sha.** "
                "Re-verify at current HEAD before acting — the callback is "
                "tagged to the sha that was tested, which may no longer be the "
                "state of the tree.\n" % behind)
    return ""


def already_filed(pdir, slug):
    """Does a ticket for `slug` exist in any bucket — and is it real?

    A ZERO-BYTE file does not count. That is not hypothetical: on 2026-08-01 a
    format-injection crash (fixed in `7911dc603`) died between `open(..., "w")`
    and the write, leaving
    `backlog/regression-test-nilpy-test-nilpy-static-mixed-type-guard.md` at 0
    bytes. Because this check only asked "does the path exist", that empty file
    became a permanent SUPPRESSOR: the job could go red again and the watcher
    would decline to file, silently, forever. Debris must never be able to
    switch off a signal.
    """
    for b in PROGRESS_BUCKETS:
        p = os.path.join(pdir, b, slug + ".md")
        try:
            if os.path.getsize(p) > 0:
                return True
        except OSError:                    # absent, or unreadable
            continue
    return False


def write_ticket(path, text):
    """Write a ticket atomically: full content to a temp file in the same
    directory, then rename over the target.

    Belt to `already_filed`'s braces. Formatting the body BEFORE any file
    exists is what actually prevents the 0-byte case, but a crash, a full
    disk, or a kill between write and close can still truncate an ordinary
    write — and the failure is invisible until the day a red goes unfiled.
    """
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tkt-")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def file_cascade_ticket(clone, host, st, sha, new_red, report, parent=None):
    """One ticket for a mass NEW-RED sweep.  Slug keyed on the bad sha, so a
    re-test of the same sha never files twice; a DIFFERENT sha cascading
    files its own (that is a new event worth a new signal)."""
    slug = "regression-cascade-" + sha[:12]
    pdir = os.path.join(clone.path, "devdocs/progress")
    if already_filed(pdir, slug):
        return
    roots = [j for j in new_red
             if any(j.startswith(r) for r in CASCADE_ROOT_JOBS)]
    joblist = "\n".join("- `%s`" % j for j in sorted(new_red))
    rel = os.path.join("devdocs/progress/backlog", slug + ".md")
    # A cascade whose cause is already reverted on origin/master is not an
    # emergency, and filing it at 70 is how one cost two agents a triage cycle
    # each. It is still worth a record — the sha really was broken — so file it,
    # but at a priority that matches "probably already handled".
    stale = staleness_note(clone, sha, parent)
    prio = 25 if stale.startswith("> **LIKELY ALREADY FIXED") else 70
    body = ("""---
prio: %d
---

%s""" % (prio, stale) + """

# regression CASCADE: %d jobs newly red at %s (auto-filed by twatch)

- **Type:** regression cascade (auto-filed by Track T watcher, host %s).
  Untriaged. %d jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** %s
- **Root-cause suspects in the red set:** %s

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier %s --job '<job>'` at %s

## Newly red jobs
%s

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
""" % (len(new_red), sha[:12], host, len(new_red), utcnow(),
            ", ".join("`%s`" % r for r in roots) if roots
            else "none of the known root jobs — likely a broken build or harness event",
            report["tier"], sha, joblist))
    write_ticket(os.path.join(clone.path, rel), body)
    clone.publish("tstate-ticket(%s): %s (cascade, %d jobs)" %
                  (host, slug + ".md", len(new_red)), paths=[rel])
    print("twatch: auto-filed CASCADE ticket for %d red jobs" % len(new_red),
          flush=True)


def file_stub_tickets(clone, host, st, sha, new_red, report, parent=None):
    """Face-1 auto-ticket: deterministic stub per NEW-RED job — repro command,
    range, log tail.  No analysis (that's face 2); slug = the STABLE selector,
    so a job never gets a second ticket while one exists in any bucket (and a
    renumbering can no longer file a duplicate for a test already ticketed).
    A mass sweep (> CASCADE_THRESHOLD new reds) files ONE cascade ticket
    instead — see file_cascade_ticket."""
    if len(new_red) > CASCADE_THRESHOLD:
        file_cascade_ticket(clone, host, st, sha, new_red, report, parent)
        return
    filed = []
    advisory = {job_key(j) for j in report["jobs"] if j.get("advisory")}
    for job in new_red:
        slug = reg_slug(job)
        pdir = os.path.join(clone.path, "devdocs/progress")
        if already_filed(pdir, slug):
            continue
        j = next((x for x in report["jobs"] if job_key(x) == job), {})
        tail = ""
        if j.get("log") and os.path.exists(j["log"]):
            with open(j["log"], errors="replace") as f:
                body = f.read()
            # Same blind spot as the report, and it matters more here: the stub
            # is what a dev reads FIRST. A 2000-char tail of an FPC failure is
            # all warnings, with the one Error line thousands of characters
            # above it.
            diag = diagnostic_lines(body)
            tail = (diag + "\n(tail)\n" if diag else "") + body[-2000:]
        reg = next((r for r in st["open_regressions"] if r["job"] == job), {})
        rel = os.path.join("devdocs/progress/backlog", slug + ".md")
        # an advisory job is not part of anyone's gate: its red is a NOTICE for
        # the track that owns the code (the FPC canary => Track A, compiler/**),
        # so it must not carry regression priority or read as a stop-work.
        kind = ("advisory (NOT a gate — nothing day-to-day depends on this "
                "path; a notice for the owning track)" if job in advisory
                else "regression")
        # The note is an ARGUMENT, never concatenated into the format
        # string: it carries commit subjects and free text, and a literal
        # `%` in there becomes a format spec once `%` is applied to the
        # joined string. That crashed the daemon on 2026-08-01 with
        # "TypeError: %d format: a real number is required, not str".
        # file_cascade_ticket already passed it as an argument; this one
        # did not, and only the stub path ever files a small-enough red.
        # Formatted BEFORE the file is created, so the same crash can no
        # longer leave a 0-byte suppressor behind (see already_filed).
        body = ("""---
prio: %d
---

%s
# %s: %s red at %s (auto-filed by twatch)

- **Type:** %s (auto-filed by Track T watcher, host %s). Untriaged.
- **Found:** %s
- **Test source:** %s

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
""" % (40 if job in advisory else 70,
                staleness_note(clone, sha, parent),
                "advisory" if job in advisory else "regression",
                job, sha[:12], kind, host, utcnow(),
                j.get("src") or "unknown (see repro commands)",
                report["tier"], job, sha,
                (reg.get("bad") or sha)[:12], (reg.get("good") or "unknown")[:12],
                len(reg.get("range", [])), tail))
        write_ticket(os.path.join(clone.path, rel), body)
        filed.append(rel)
    if filed:
        clone.publish("tstate-ticket(%s): %s" %
                      (host, ", ".join(os.path.basename(p) for p in filed)),
                      paths=filed)
        print("twatch: auto-filed %d stub ticket(s)" % len(filed), flush=True)


# Present in every stub file_stub_tickets/file_cascade_ticket writes. Its
# presence is the test for "still an untriaged stub, safe for the daemon to
# retire"; a triager who rewrites the body removes it and takes ownership.
STUB_MARKER = "auto-filed by twatch"


def close_stub_tickets(clone, host, closed, sha, report):
    """Face-1 auto-close: retire a stub whose job is green again.

    The mirror of file_stub_tickets, gated by the same `autoticket` flag: what
    the watcher opened, the watcher may close.  It ran a day too late for
    `regression-test-nilpy-test-nilpy-bytes-decode`, which sat in backlog at
    prio 70 for a full day after the watcher had already published
    `FIXED:...bytes_decode.npy` — top of `ready --track T`, work that no longer
    existed (feature-t-autoticket-must-close-its-own-stubs-when-fixed).

    Deliberately narrow.  The daemon closes a ticket only when BOTH hold:

      * it is still in `backlog/` — any other bucket means a human or an agent
        has taken it (working/blocked/unfinished) or already settled it
        (done/rejected), and their judgement outranks the ledger's;
      * it still carries STUB_MARKER — an enriched body is somebody's analysis,
        not a stub, even if it never moved bucket.

    Neither case is a silent skip: both print, because "the watcher quietly
    declined to do the thing you expect it to do" is how a tool loses trust.
    The board is NOT regenerated here — BOARD.md is generated and is the file
    two agents always conflict on (sync.sh exists for it), and the filing path
    does not regenerate it either.  An agent regenerates.
    """
    pdir = os.path.join(clone.path, "devdocs/progress")
    paths, slugs = [], []
    for r in closed:
        slug = ("regression-cascade-" + (r.get("bad") or "")[:12]
                if r.get("cascade") else reg_slug(r["job"]))
        src = os.path.join(pdir, "backlog", slug + ".md")
        if not os.path.exists(src):
            held = next((b for b in PROGRESS_BUCKETS
                         if b != "backlog"
                         and os.path.exists(os.path.join(pdir, b, slug + ".md"))),
                        None)
            if held:
                print("twatch: %s is in %s/ — its owner closes it, not me"
                      % (slug, held), flush=True)
            continue
        with open(src, errors="replace") as f:
            body = f.read()
        if STUB_MARKER not in body:
            print("twatch: %s has been triaged (no stub marker) — leaving it"
                  % slug, flush=True)
            continue
        if "\n## Log\n" not in body:
            body = body.rstrip("\n") + "\n\n## Log\n"
        # Name the sha the job PASSED at and the tier that judged it: a close
        # with no evidence is indistinguishable from a lost ticket, and
        # progress.sh check requires done/ tickets to log something citable.
        body = (body.rstrip("\n") + "\n- %s — auto-closed by the %s watcher: "
                "`%s` passes at %s (tier %s); it was red at %s. Reopening is "
                "by a fresh NEW-RED stub, since a second red is a second "
                "finding with its own range.\n"
                % (utcnow()[:10], host,
                   r.get("job") or slug, sha[:12], report["tier"],
                   (r.get("bad") or "?")[:12]))
        dst = os.path.join(pdir, "done", slug + ".md")
        with open(dst, "w") as f:
            f.write(body)
        os.unlink(src)
        paths += [os.path.relpath(p, clone.path) for p in (src, dst)]
        slugs.append(slug)
    if slugs:
        # Both paths go to publish(): `git add -- <gone> <new>` is what records
        # the move; staging only the destination leaves the stub in backlog on
        # origin and the ticket exists twice.
        clone.publish("tstate-ticket(%s): closed %s (job green again)"
                      % (host, ", ".join(slugs)), paths=paths)
        print("twatch: auto-closed %d stub ticket(s)" % len(slugs), flush=True)


def clone_head_back(clone):
    sh(["git", "checkout", "--quiet", clone.branch], cwd=clone.path)


def run_fuzz_idle(clone, host, st, sha, preempted):
    """Idle work: spend spare cycles fuzzing (feature-fuzzer-idle-scheduling).

    Differs from every other idle phase in one way that drives the whole design:
    opt and bench are DONE-per-sha, so they self-terminate. Fuzzing is endless --
    there is no point at which a sha is "fully fuzzed". So:

      * It is strictly LAST in the idle chain. It may only ever consume cycles
        that no real work wants; it must never delay a backfill, an opt sweep or
        a bisect. (If it ran earlier in the chain it would starve them forever,
        because it never finishes.)
      * It is TIME-BOXED per slice (fuzz_minutes) and PREEMPTIBLE -- a push kills
        it mid-slice and reclaims the box. A verdict on a real commit always wins
        over a speculative bug hunt.
      * The seed cursor PERSISTS across slices (st["fuzz_seed"]), so successive
        slices explore new programs instead of re-running seed 1 forever. This is
        the difference between a fuzzer and a very slow regression suite.

    Findings are PUBLISHED, never auto-ticketed: an unattended loop that files
    tickets produces ticket-spam, and a divergence needs triage (is it the
    generator's fault?) before it is a bug. tstate/ is also the watcher
    identity's entire write scope. A human or the Track T agent turns a finding
    into a ticket in the owning lane.

    RATE LIMIT (the ledger). One `case`-selector defect once produced 639
    published reports -- every one of them the same bug. A fuzzer that reports one
    bug 639 times is not finding bugs; it is finding *a* bug, loudly, and the pile
    buries the only number that matters (distinct causes per CPU-hour). So each
    slice runs against tstate/fuzz/LEDGER.json:

      * a known-open signature is COUNTED, never re-filed;
      * a NEW signature stops the slice on the spot (--stop-on-new): file it, hand
        it to the owning lane, do not spend the remaining minutes re-finding it;
      * while anything is open, slices are spaced fuzz_backoff_minutes apart --
        the lane that owns the bug gets room, and we stop burning the box
        re-deriving a known answer;
      * every tick first RECHECKS the open findings against the current sha, and
        the ones that stopped reproducing are marked fixed. Full-speed fuzzing
        then resumes BY ITSELF. Throttling on an open finding is only honest if
        something notices the fix without being asked.
    """
    minutes = float(CONF.get("fuzz_minutes", 10))
    # The seed cursor lives in an UNTRACKED, clone-local file — deliberately NOT
    # in tstate/<host>.json. That file is tracked, so recording the cursor there
    # would dirty the tree every slice, and the dirty-pause check then forces a
    # publish to un-wedge the next cycle: a commit+push every ~10 minutes,
    # forever, even on a clean fuzz run. Commit spam on master. A seed cursor is
    # local bookkeeping, not shared state — only FINDINGS are worth publishing.
    cursor = os.path.join(clone.path, ".testmgr", "fuzz.json")
    try:
        with open(cursor) as f:
            cur = json.load(f)
    except (OSError, ValueError):
        cur = {}
    seed0 = int(cur.get("next_seed", 1))
    runner = os.path.join(clone.path, "tools/pasmith_run.py")
    if not os.path.exists(runner) or not shutil.which("fpc"):
        return False        # no generator at this sha, or no oracle: skip silently

    # The ledger the SLICE writes is clone-local and untracked (.testmgr/): hit
    # counters tick on every slice, and mirroring that churn into a tracked file
    # would mean a commit+push every ten minutes, forever, on a clean run -- the
    # exact commit-spam trap the seed cursor above already documents. Only a
    # change in the finding SET or their STATUS is worth publishing, and that is
    # what gets copied into tstate/ at the end.
    ledger_pub = os.path.join(clone.path, TSTATE_REL, "fuzz", "LEDGER.json")
    ledger_loc = os.path.join(clone.path, ".testmgr", "ledger.json")
    if not os.path.exists(ledger_loc) and os.path.exists(ledger_pub):
        os.makedirs(os.path.dirname(ledger_loc), exist_ok=True)
        shutil.copy(ledger_pub, ledger_loc)
    shape0 = ledger_shape(ledger_loc)
    n_open = open_actionable_count(ledger_loc)

    findings = os.path.join(tempfile.gettempdir(), "twatch-fuzz-%d" % os.getpid())
    env = dict(os.environ, PASMITH_FINDINGS_DIR=findings)

    if n_open:
        # A finding is open. Recheck it against THIS sha first -- if the lane that
        # owns it has landed the fix, the tap reopens on the spot.
        set_phase(clone, host, "fuzz-recheck", sha=sha)
        clone.checkout(sha)
        try:
            r = subprocess.run(
                [sys.executable, runner, "--recheck", "--ledger", ledger_loc,
                 "--ledger-inplace", "--sha", sha[:12]],
                cwd=clone.path, env=env, text=True, capture_output=True, timeout=1800)
            tail = (r.stdout or "").strip().split("\n")[-1]
        except subprocess.TimeoutExpired:
            tail = "recheck timed out"
        clone_head_back(clone)
        print("twatch: fuzz recheck %s — %s" % (sha[:12], tail), flush=True)
        shape1 = ledger_shape(ledger_loc)
        n_open = open_actionable_count(ledger_loc)
        if shape1 != shape0:
            publish_ledger(clone, host, ledger_loc, ledger_pub, findings, sha)
            shape0 = shape1

    if n_open:
        # Still open: throttle. Slices are spaced fuzz_backoff_minutes apart so the
        # owning lane has room to fix it, instead of the fuzzer spending every idle
        # minute re-deriving a bug that is already on somebody's desk.
        backoff = float(CONF.get("fuzz_backoff_minutes", 90)) * 60
        since = time.time() - float(cur.get("last_slice_ts", 0))
        if since < backoff:
            print("twatch: fuzz throttled — %d finding(s) open, next slice in %.0fm "
                  "(fuzz_backoff_minutes=%.0f)"
                  % (n_open, (backoff - since) / 60.0, backoff / 60.0), flush=True)
            set_phase(clone, host, "idle")
            return False

    print("twatch: fuzz %s (%.0fm from seed %d%s)"
          % (sha[:12], minutes, seed0, ", %d open finding(s)" % n_open if n_open else ""),
          flush=True)
    set_phase(clone, host, "fuzz", sha=sha, seed=seed0)
    clone.checkout(sha)

    # --wide: every rung the grammar has -- records + forward pointers, enums/sets,
    # arrays, string[N], exception hierarchies, var/const/out params, on top of the
    # OOP and ansistring ones. Csmith can reach none of it, which is the reason a
    # Pascal smith exists at all; and a narrow grammar is what made the old fuzzer
    # re-find one `case` bug 639 times. Big programs on purpose -- size is a feature
    # here, not a cost (localisation is a trace diff, so it does not degrade).
    proc = subprocess.Popen(
        [sys.executable, runner, "--minutes", str(minutes), "--start", str(seed0),
         "--wide", "--classes", "4", "--stmts", "20", "--vars", "10",
         "--ledger", ledger_loc, "--ledger-inplace", "--stop-on-new",
         "--sha", sha[:12]],
        cwd=clone.path, env=env, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, start_new_session=True)

    out = []
    while proc.poll() is None:
        if STOP:            # a stop must not wait out a 10-minute fuzz slice
            kill_child(proc, grace=5)
            clone_head_back(clone)   # never leave HEAD detached behind us
            print("twatch: stopping — fuzz slice discarded", flush=True)
            set_phase(clone, host, "idle")
            return "aborted"
        if preempted():
            # A real push outranks speculative work: kill the GROUP (the runner
            # spawns compilers and qemu) and drop the slice on the floor.
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except OSError:
                pass
            proc.wait()
            clone_head_back(clone)   # never leave HEAD detached behind us
            print("twatch: fuzz preempted by a push — slice discarded", flush=True)
            set_phase(clone, host, "idle")
            return "aborted"
        time.sleep(2)
    out = proc.stdout.read().decode("utf-8", "replace") if proc.stdout else ""

    nprog = ndiv = 0
    m = re.search(r"(\d+) programs, (\d+) divergences", out)
    if m:
        nprog, ndiv = int(m.group(1)), int(m.group(2))
    write_json_atomic(cursor, {"next_seed": seed0 + max(nprog, 1),
                               "last_sha": sha, "date": utcnow(),
                               "last_slice_ts": time.time(),
                               "programs": nprog, "divergences": ndiv})
    # BACK ONTO THE BRANCH BEFORE TOUCHING THE TREE. The slice ran with HEAD
    # DETACHED at `sha`, and writing findings into the working tree there leaves
    # UNTRACKED files under devdocs/progress/tstate/fuzz/. The next checkout then
    # refuses to clobber them:
    #
    #   error: The following untracked working tree files would be overwritten
    #   by checkout: devdocs/progress/tstate/fuzz/906038a93015-seed_617.txt ...
    #   Aborting
    #   twatch: 10 consecutive failures — giving up
    #
    # ...and the daemon shuts itself down. That is the "trackt stops by itself"
    # regression, and it was entirely self-inflicted: run_bench_idle documents
    # this exact hazard ("written to a temp file and appended AFTER checking the
    # branch back out — mutating it under a detached HEAD would block the
    # checkout back") and I wrote the bug it warns about. Findings live in a temp
    # dir (PASMITH_FINDINGS_DIR) precisely so they can survive the checkout.
    clone_head_back(clone)

    shape1 = ledger_shape(ledger_loc)
    if shape1 == shape0:
        # Nothing NEW. Either a clean slice, or every divergence it hit was a known
        # signature the ledger already carries -- in which case the finding is
        # already on somebody's desk and re-publishing it is precisely the noise
        # this ledger exists to kill. Say it on stdout; commit nothing.
        print("twatch: fuzz %s — %d programs, %d divergence(s), no NEW signature"
              % (sha[:12], nprog, ndiv), flush=True)
        set_phase(clone, host, "idle")
        return True

    new = [s for s, v in shape1.items() if shape0.get(s) != v and v == "open"]
    publish_ledger(clone, host, ledger_loc, ledger_pub, findings, sha,
                   nprog=nprog, ndiv=ndiv, new=new)
    set_phase(clone, host, "idle")
    return True


def ledger_shape(path):
    """{signature: status} -- the part of the ledger worth PUBLISHING.

    Hit counters change every slice; the finding set and its statuses do not. Only
    the latter is a reason to commit, so this is what gets diffed.
    """
    try:
        with open(path) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return {}
    return {s: e.get("status") for s, e in d.get("findings", {}).items()}


# Finding classes with NO owning dev lane: an FPC-self contradiction is an FPC
# bug, an upstream bug -- nothing we commit can ever "fix" it. The fuzz throttle
# (fuzz_backoff_minutes) exists to give the owning lane room to land a fix before
# the fuzzer re-derives the same bug; a finding no lane owns must not count toward
# it, or a single permanently-open fpc-self finding wedges the fuzzer forever
# (recheck ~3s -> throttle -> idle, every cycle, never fuzzing). See
# open_actionable_count / run_fuzz_idle.
NONACTIONABLE_CLASSES = {"fpc-self"}


def open_actionable_count(path):
    """Count OPEN findings a dev lane can actually fix (throttle-relevant subset).

    Excludes NONACTIONABLE_CLASSES -- external bugs that can never be resolved
    locally and would otherwise pin the fuzzer in permanent backoff.
    """
    try:
        with open(path) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return 0
    return sum(1 for e in d.get("findings", {}).values()
               if e.get("status") == "open"
               and e.get("class") not in NONACTIONABLE_CLASSES)


def publish_ledger(clone, host, ledger_loc, ledger_pub, findings, sha,
                   nprog=0, ndiv=0, new=None):
    """Mirror the local ledger + its per-signature reports into tstate/ and push.

    One report file per SIGNATURE, not per seed: the seed lives inside the report
    and pasmith is deterministic, so the second instance of a bug adds nothing that
    the hit counter has not already said. This is what turns "639 files, one bug"
    into "one file, one bug, 639 hits".

    Must run ON THE BRANCH (clone_head_back first) -- writing tracked files under a
    detached HEAD blocks the checkout back and eventually shuts the daemon down.
    """
    dst = os.path.dirname(ledger_pub)
    os.makedirs(dst, exist_ok=True)
    shutil.copy(ledger_loc, ledger_pub)
    kept = 0
    for f in sorted(os.listdir(findings)) if os.path.isdir(findings) else []:
        if f.endswith(".txt") and f != "LEDGER.json":
            shutil.copy(os.path.join(findings, f), os.path.join(dst, f))
            kept += 1
    if new:
        msg = ("tstate(%s): fuzz %s — NEW: %s (%d divergence(s) in %d programs)"
               % (host, sha[:12], ", ".join(new), ndiv, nprog))
        print("twatch: fuzz — NEW signature(s) %s; published to tstate/fuzz (NOT "
              "ticketed: needs triage, the generator is the first suspect). Fuzzing "
              "throttles until it is fixed." % ", ".join(new), flush=True)
    else:
        msg = "tstate(%s): fuzz %s — ledger update" % (host, sha[:12])
        print("twatch: fuzz — ledger status changed; published", flush=True)
    clone.publish(msg)
    return kept


def run_bench_idle(clone, host, st, sha):
    """Idle work: tracked benchmark timings for the fully-tested sha — the
    clone's testmgr --bench, rows published to tstate/bench.tsv. Runs
    detached at `sha`, so the TSV is written to a temp file and appended
    after checking the branch back out (bench.tsv is tracked: mutating it
    under a detached HEAD would block the checkout back). Not preemptible —
    ~2-3 min, shorter than a full backfill."""
    print("twatch: bench %s" % sha[:12], flush=True)
    set_phase(clone, host, "bench", sha=sha)
    clone.checkout(sha)
    tmp_tsv = os.path.join(tempfile.gettempdir(),
                           "twatch-bench-%d.tsv" % os.getpid())
    if os.path.exists(tmp_tsv):
        os.unlink(tmp_tsv)
    env = dict(os.environ, TESTMGR_BENCH_TSV=tmp_tsv)
    r = subprocess.run([sys.executable,
                        os.path.join(clone.path, "tools/testmgr.py"),
                        "--bench"], cwd=clone.path, env=env)
    # FPC conformance breakdown at this sha (feature-testmgr-fpc-compare-and-
    # web-dashboard): per-test TSV the dashboard reads. Uses the compiler --bench
    # just built at `sha`; the suite may be absent (runner SKIPs, empty report).
    # Written to temp — the tracked tree is detached here, like bench.tsv.
    conf_tmp = os.path.join(tempfile.gettempdir(),
                            "twatch-conf-%d.tsv" % os.getpid())
    if os.path.exists(conf_tmp):
        os.unlink(conf_tmp)
    subprocess.run(["sh", os.path.join(clone.path,
                    "tools/run_pascal_conformance.sh"), "--report", conf_tmp],
                   cwd=clone.path, stdout=subprocess.DEVNULL)
    clone_head_back(clone)
    rows = 0
    if os.path.exists(tmp_tsv):
        with open(tmp_tsv) as f:
            new = [ln for ln in f if not ln.startswith("#")]
        rows = len(new)
        if new:
            tsv = os.path.join(clone.path, TSTATE_REL, "bench.tsv")
            fresh = not os.path.exists(tsv) or not os.path.getsize(tsv)
            with open(tsv, "a") as f:
                if fresh:
                    f.write("# date\thost\tsha\tworkload\tlevel\tms\n")
                f.writelines(new)
        os.unlink(tmp_tsv)
    conf_rows = 0
    if os.path.exists(conf_tmp):
        with open(conf_tmp) as f:
            cdata = f.read()
        conf_rows = sum(1 for ln in cdata.splitlines()
                        if ln and not ln.startswith("#"))
        if conf_rows:
            with open(os.path.join(clone.path, TSTATE_REL,
                                   "conformance.tsv"), "w") as f:
                f.write(cdata)
        os.unlink(conf_tmp)
    # regenerate the committed static dashboard from the fresh tstate data
    subprocess.run([sys.executable,
                    os.path.join(clone.path, "tools/twatch_web.py"),
                    "--clone", clone.path, "--static"],
                   cwd=clone.path, stdout=subprocess.DEVNULL)
    st["last_bench"] = {"sha": sha, "date": utcnow(), "rc": r.returncode,
                        "rows": rows, "conf_rows": conf_rows}
    save_state(clone, host, st)
    clone.publish("tstate(%s): bench %s %s (%d bench rows, %d conf)"
                  % (host, sha[:12],
                     "ok" if r.returncode == 0 else "RED", rows, conf_rows))


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


def make_preempted(clone, tested):
    """Abort-check for idle work (full backfill / opt sweep): a real push
    preempts, docs/tstate-only movement (e.g. our own fast-phase publish)
    must not abort the work it queued."""
    def preempted():
        if STOP:
            return True
        clone.fetch()
        h = clone.remote_head()
        if h == tested:
            return False
        return any(needs_test(clone.path, c)
                   for c in clone.commits_between(tested, h))
    return preempted


def bisect_step(clone, host, st, tier):
    """Idle work: narrow one open regression range by testing its midpoint
    with ONLY the failing job."""
    for reg in st["open_regressions"]:
        rng = reg.get("range", [])
        if len(rng) <= 1:
            continue
        if reg.get("cascade"):
            # "cascade@<sha>" is a synthetic key matching no job, so a
            # midpoint gate would select nothing and read as a pass. A
            # cascade needs root-cause triage (face 2), not a bisect.
            continue
        mid = rng[len(rng) // 2 - 1] if len(rng) > 2 else rng[0]
        # skip the known-bad tip
        if mid == reg["bad"] and len(rng) > 1:
            mid = rng[0]
        print("twatch: bisect %s at %s (%d in range)" %
              (reg["job"], mid[:12], len(rng)), flush=True)
        clone.checkout(mid)
        report, _rc = run_gate(clone, tier, job_glob=reg["job"])
        if report is None and "#src:" in reg["job"]:
            # bisect runs the testmgr OF THE COMMIT UNDER TEST, and one older
            # than the src: selector rejects it outright ("no jobs match").
            # Retry such commits with the positional name we saw the job under.
            # It is the wrong name if the range renumbered — but a possibly-off
            # bisect step beats a bisect that cannot run at all, and this only
            # applies to commits older than the selector itself.
            legacy = reg.get("name")
            if legacy:
                print("twatch: %s predates src: selectors — retrying as %s"
                      % (mid[:12], legacy), flush=True)
                report, _rc = run_gate(clone, tier, job_glob=legacy)
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
def states_at(repo, ref):
    """Per-host tstate documents read from a GIT REF, not the working tree.

    The daemon publishes to origin; the worktree is merely where it happened to
    be standing. Reading the ref is therefore the only view that matches what
    other boxes can see — and it is what `tools/trackt.py` has always done
    (`git show origin/master:…`), which is why `trackt status` stayed accurate
    while `twatch.py --status` did not.

    Pure git plumbing: no network, no fetch. Returns [] if the ref has no tstate
    (a fresh clone, a repo without the remote), so the caller can fall back.
    """
    out = []
    try:
        names = sh(["git", "ls-tree", "--name-only", "%s:%s" % (ref, TSTATE_REL)],
                   cwd=repo, check=False).split()
    except (RuntimeError, OSError):
        return out
    for n in sorted(names):
        if not n.endswith(".json"):
            continue
        try:
            blob = sh(["git", "show", "%s:%s/%s" % (ref, TSTATE_REL, n)],
                      cwd=repo, check=False)
            if blob:
                out.append(json.loads(blob))
        except (RuntimeError, OSError, ValueError):
            continue                   # a half-written or absent blob is not fatal
    return out


def status(repo, grace_min, tdir=None, ref="HEAD"):
    """Is Track T covering this repo?  No ping, no network: a watcher is
    considered UP iff every commit older than the grace window is tested by
    some host (a quiet watcher on a quiet repo is indistinguishable from a
    dead one — and it doesn't matter).  Exit 0 = offload to T; 1 = T is
    down/absent, run your own full gate.

    `tdir`/`ref` exist because BOTH default sources go stale and produce a false
    DOWN:

      * the tstate files in a WORKTREE are only as fresh as the last `git pull` —
        in a dev checkout that can be hours old, and in the watcher's own clone
        the worktree is DETACHED at the sha under test for most of every cycle;
      * `git log` on HEAD has the same problem, and during a bisect HEAD is an
        old commit entirely.

    So the caller can point this at data read from `origin/master` instead, which
    is what the daemon actually publishes to. Reported DOWN while the daemon was
    demonstrably mid-run (2026-07-14).
    """
    # origin/master is truth. A dev checkout drifts behind it constantly, and
    # `git log HEAD` then measures coverage over history this checkout cannot
    # see: 2026-07-20 a checkout 226 commits behind reported UP while the
    # daemon had been stopped for hours. Prefer the already-fetched remote ref
    # (still no network) and say so when it disagrees with HEAD.
    if ref == "HEAD":
        remote = sh(["git", "rev-parse", "--verify", "-q",
                     "origin/master"], cwd=repo, check=False).strip()
        if remote:
            behind = sh(["git", "rev-list", "--count", "HEAD..origin/master"],
                        cwd=repo, check=False).strip()
            if behind and behind != "0":
                print("tstate: note — checkout is %s commit(s) behind "
                      "origin/master; measuring coverage against "
                      "origin/master (run `git pull --rebase` to refresh it)"
                      % behind)
            ref = "origin/master"
    # BOTH inputs must come from the SAME ref. The walk above already prefers
    # origin/master; taking the tested-set from the worktree instead is what
    # made a healthy watcher report DOWN (2026-08-01, Track A). In the watcher's
    # own clone the worktree is DETACHED at the sha under test for most of every
    # cycle, so its tstate lags what the daemon has already pushed; in a dev
    # checkout it is only as fresh as the last pull. Either way: fresh history +
    # stale verdicts = commits that merely LOOK untested.
    #
    # No network — this reads whatever origin/master the checkout already has,
    # exactly like the walk. A checkout that is behind then reports on a
    # consistently old view rather than an incoherent mixed one.
    hosts = []
    if tdir is None:
        hosts = states_at(repo, ref)
    if not hosts:                      # explicit tdir, or no usable ref
        tdir = tdir or os.path.join(repo, TSTATE_REL)
        if os.path.isdir(tdir):
            for fn in sorted(os.listdir(tdir)):
                if not fn.endswith(".json"):
                    continue
                try:
                    with open(os.path.join(tdir, fn)) as f:
                        hosts.append(json.load(f))
                except (OSError, ValueError):
                    pass
    tested = set()
    for st in hosts:
        if st.get("last"):
            tested.add(st["last"]["sha"])
        tested.update(h["sha"] for h in st.get("history", []))
    if not hosts:
        print("tstate: DOWN — no watcher state in %s (run your own full gate)"
              % TSTATE_REL)
        return 1
    out = sh(["git", "log", "--format=%H %ct", "-n", "200", ref], cwd=repo)
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
        quiet = host_quiet_secs(st, now)
        print("tstate: host %-12s last %s %s (%s, %s)%s%s" %
              (st["host"], (last.get("sha") or "")[:12],
               last.get("verdict", "never"), last.get("tier", "?"),
               last.get("date", ""),
               "; full through %s %s" % (lf["sha"][:12], lf["verdict"])
               if lf.get("sha") else "",
               "  [QUIET %s — not publishing]" % fmt_age(quiet) if quiet
               # Before a host has one recorded job map, its NEW-RED is a diff
               # against nothing. Say so where the host is read, so a fresh
               # enrollment's green is not mistaken for coverage.
               else "  [NOT BASELINED — NEW-RED not meaningful yet]"
               if not st.get("jobs") else ""))
        # --status is a liveness check read before a push, not a report: cap
        # the ledger dump so one bad sweep can never bury the verdict line
        # (2026-07-20 it printed 467 entries / 49KB above the UP/DOWN answer).
        regs = st.get("open_regressions", [])
        if quiet and regs:
            # HELD, not hidden: nothing on a quiet host can clear these, so
            # printing them among the live ones asks agents to act on entries
            # no run will ever resolve. Named and counted, so the host going
            # quiet is MORE visible than before, not less.
            print("tstate:   %d open regression(s) held with %s — nothing can "
                  "clear them until it publishes again (see %s)"
                  % (len(regs), st["host"], INDEX_REL))
            continue
        for r in regs[:STATUS_REG_CAP]:
            if r.get("cascade"):
                print("tstate:   open CASCADE: %d jobs bad=%s (%d in range)"
                      % (len(r["cascade"]), r["bad"][:12],
                         len(r.get("range", []))))
            else:
                print("tstate:   open regression: %s bad=%s (%d in range)"
                      % (r["job"], r["bad"][:12], len(r.get("range", []))))
        if len(regs) > STATUS_REG_CAP:
            print("tstate:   ... and %d more open regression(s) — see "
                  "devdocs/progress/tstate/TSTATE.md"
                  % (len(regs) - STATUS_REG_CAP))
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


def is_ancestor(repo, a, b):
    """Is commit `a` reachable from `b`? (i.e. does b's tree contain a's change)"""
    if a == b:
        return True
    try:
        return subprocess.run(["git", "merge-base", "--is-ancestor", a, b],
                              cwd=repo, capture_output=True).returncode == 0
    except OSError:
        return False


def sha_verdicts(repo, ref="origin/master"):
    """{full sha: (verdict, tier, host, [new_red...])} for every judged sha."""
    out = {}
    for st in states_at(repo, ref):
        host = st.get("host", "?")
        for h in st.get("history", []):
            if h.get("sha"):
                out[h["sha"]] = (h.get("verdict", "?"), h.get("tier", "?"),
                                 host, h.get("new_red") or [])
        last = st.get("last") or {}
        if last.get("sha") and last["sha"] not in out:
            out[last["sha"]] = (last.get("verdict", "?"), last.get("tier", "?"),
                                host, [])
    return out


def follow(repo, shas, poll, branch="master", once=False, limit=20):
    """Wait for Track T's verdict on shas, so the session that PUSHED them hears
    back while its context is still warm.

    The offload ("confirm native, offload the matrix") only pays if the finding
    reaches the agent that caused it; otherwise the next session pays full
    re-investigation cost, which is most of what the offload was meant to save.

    Read-only with respect to the caller's tree: it FETCHES but never pulls,
    rebases or checks anything out — an agent's working tree must not move
    underneath it just because it asked a question.

    Fetching every poll is mandatory, not an optimisation: verdicts are read
    from `origin/master`, and without a fetch that ref is frozen at whatever the
    checkout last saw, so this would confidently report "nothing yet" forever.
    """
    # Fetch BEFORE choosing the default set, not just inside the loop: the
    # default is derived from origin/<branch>, so a stale (or absent) ref would
    # otherwise pick the wrong shas — or none, and exit reporting success.
    fetch_ref = ["git", "fetch", "--quiet", "--no-write-fetch-head", "origin",
                 "+refs/heads/%s:refs/remotes/origin/%s" % (branch, branch)]
    sh(fetch_ref, cwd=repo, check=False)
    if not shas:
        # default: what this checkout has pushed to the branch and T has not
        # judged. Author-filtering is deliberately NOT used — every agent in
        # this fleet commits as the same git identity, so it would select other
        # agents' work too and mean nothing.
        shas = sh(["git", "log", "--format=%H", "-n", str(limit),
                   "origin/" + branch], cwd=repo, check=False).split()
        shas = [s for s in shas if needs_test(repo, s)]
        if not shas:
            print("follow: nothing on origin/%s needs a verdict" % branch)
            return 0
    shas = [sh(["git", "rev-parse", s], cwd=repo, check=False).strip() or s
            for s in shas]
    pending = list(dict.fromkeys(shas))
    print("follow: watching %d sha(s) for a Track T verdict (poll %ds)"
          % (len(pending), poll), flush=True)
    worst = 0
    while pending:
        sh(fetch_ref, cwd=repo, check=False)
        judged = sha_verdicts(repo, "origin/" + branch)
        for s in list(pending):
            covered_by = None
            if s in judged:
                covered_by = s
            else:
                # The watcher tests HEAD, not every commit: it walks forward to
                # the newest testable sha and skips what a burst pushed in
                # between. So an exact-sha match hangs forever in the NORMAL
                # case — and the watcher's own tstate commits guarantee
                # something lands after yours. A commit is covered as soon as
                # any DESCENDANT has been judged: that run built and tested a
                # tree containing your change.
                for j in judged:
                    if is_ancestor(repo, s, j):
                        covered_by = j
                        break
            if covered_by is None:
                continue
            verdict, tier, host, new_red = judged[covered_by]
            pending.remove(s)
            if covered_by != s:
                print("follow: %s covered by %s (the watcher tests HEAD, not "
                      "every commit)" % (s[:12], covered_by[:12]), flush=True)
                s = covered_by
            if verdict == "GREEN":
                print("follow: %s GREEN (%s, %s)" % (s[:12], tier, host),
                      flush=True)
            else:
                worst = 1
                print("follow: %s %s (%s, %s)%s" %
                      (s[:12], verdict, tier, host,
                       "".join("\n    NEW-RED %s" % j for j in new_red[:10])),
                      flush=True)
        if once or not pending:
            break
        time.sleep(poll)
    if pending:
        # NEVER let silence read as success — the trap --status already documents
        print("follow: still unjudged (no verdict yet, NOT a pass): %s"
              % ", ".join(s[:12] for s in pending), flush=True)
        # a red already seen outranks "some are pending": it is the actionable
        # one, and the caller should not have to parse text to find that out
        return worst or 2
    return worst


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
    ap.add_argument("--follow", nargs="*", metavar="SHA",
                    help="wait for Track T's verdict on these shas (default: "
                         "unjudged commits on origin/<branch>). Fetches each "
                         "poll; never pulls or rebases your tree. "
                         "exit 0 all green, 1 a red, 2 still unjudged")
    ap.add_argument("--poll", type=float, default=30,
                    help="--follow: seconds between polls (default 30)")
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
                    help="single iteration (cron / smoke test); with --follow, "
                         "check once and exit instead of waiting")
    ap.add_argument("--no-bisect", action="store_true")
    ap.add_argument("--fetch-corpus", action="store_true",
                    help="install any missing corpus trees at startup instead "
                         "of just warning (jobs whose corpus is absent SKIP, "
                         "and a skipped job is invisible in a GREEN verdict)")
    args = ap.parse_args()

    if args.status or args.follow is not None:
        repo = os.path.abspath(os.path.expanduser(args.clone)) if args.clone \
            else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        if args.follow is not None:
            return follow(repo, args.follow, args.poll, args.branch, args.once)
        return status(repo, args.grace)
    if not args.clone:
        ap.error("--clone is required (except with --status/--follow)")

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

    warn_missing_corpus(clone.path, fetch=args.fetch_corpus)

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
                test_sha(clone, host, st, tested, args.tier,
                         full=True, abort_check=make_preempted(clone, tested))
                did_work = True
            elif tested and CONF.get("idle_opt") and \
                    (st.get("last_full") or {}).get("sha") == tested and \
                    (st.get("last_opt") or {}).get("sha") != tested:
                # idle, full matrix done: O-level differential sweep (tier
                # opt — the silent-miscompile oracle). A push preempts it.
                r = test_sha(clone, host, st, tested, "opt", full=False,
                             abort_check=make_preempted(clone, tested))
                if r != "aborted":
                    st = load_state(clone, host)
                    st["last_opt"] = {"sha": tested, "date": utcnow()}
                    if r is False:      # old sha: its testmgr has no tier
                        st["last_opt"]["note"] = "unsupported"   # opt yet —
                    save_state(clone, host, st)                  # don't wedge
                    # publish the last_opt bookkeeping: a bare save_state
                    # leaves the clone dirty and the dirty-pause check wedges
                    # every following cycle (observed 2026-07-11)
                    clone.publish("tstate(%s): opt %s %s"
                                  % (host, tested[:12],
                                     "done" if r else "unsupported"))
                did_work = True
            elif tested and CONF.get("idle_bench") and \
                    (st.get("last_full") or {}).get("sha") == tested and \
                    (st.get("last_bench") or {}).get("sha") != tested:
                # idle, opt done too: tracked benchmark timings per sha
                run_bench_idle(clone, host, st, tested)
                did_work = True
            elif not args.no_bisect:
                st = load_state(clone, host)
                set_phase(clone, host, "bisect-check", head=head[:12])
                if not bisect_step(clone, host, st, args.tier):
                    if args.once:
                        print("twatch: up to date (%s), nothing to do" % head[:12],
                              flush=True)
            # LAST, and only when nothing real is left: everything tested, the
            # full matrix done, no bisect pending. The fuzzer never finishes, so
            # anywhere earlier in the chain it would starve every phase below it.
            # Skipped in --once (a one-shot check should not sit fuzzing for 10
            # minutes).
            if not did_work and tested and not args.once \
                    and CONF.get("idle_fuzz") \
                    and (st.get("last_full") or {}).get("sha") == tested:
                st = load_state(clone, host)
                if run_fuzz_idle(clone, host, st, tested,
                                 make_preempted(clone, tested)):
                    did_work = True
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
