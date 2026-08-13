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

Work order on each cycle, highest priority first (a push preempts anything
below it, and the ladder restarts for the new sha):

  1. new push        -> fast tier on HEAD        seconds; nobody waits on T
  2. PIN, mid tier   -> native depth on the PIN  the binary every other track
                                                 is building with right now
  3. idle            -> mid tier on HEAD         native depth
  4. still idle      -> deep tier on HEAD        platform breadth (qemu)
  5. PIN, deep tier  -> platform breadth on the PIN
  6. opt / bench / bisect / fuzz                 in that order

Steps 2 and 5 exist because the pin is NOT reachable by deepening HEAD: a pin
is whatever HEAD happened to be when a human ran `make pin`, so by the time the
ladder climbs, the pin is history. Measured 2026-08-11: 18 of the last 25 pins
never got a `full` run and 13 were never judged at all. See `pinned_ref`.

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
import hashlib
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
# mid_tier == tier COLLAPSES the escalation ladder to native -> full, and that
# is the measured default now. `limited` was a cheap preview of `full` when it
# was a third of it; the matrix has since doubled (1084 jobs on 2026-07-08 ->
# 2343 on 2026-08-13) and the growth landed on both tiers, so measured on
# plexus 2026-08-13:
#
#     native   1224 jobs   170 s   (53% of the jobs, 21% of the wall)
#     limited  1811 jobs   686 s   (78% of the jobs, 84% of the wall)
#     full     2329 jobs   821 s
#
# Running all three costs 1677 s per sha where native -> full costs 991 s for
# the SAME final coverage — 41% of the box spent buying 135 s of notice. The
# wall is dominated by a few long serial jobs (selfhost alone is 131 s) that
# `limited` already pays for in full, while full's extra 518 jobs are
# parallel-friendly and nearly free. native still earns its rung: half the jobs
# for a fifth of the wall, because it excludes the qemu/cross matrix.
#
# `limited` is NOT removed — testmgr still defines it, `--tier limited` still
# runs it by hand, and setting `mid_tier` in twatch.conf restores the three-rung
# ladder. What changed is which default the measurements support. RE-MEASURE
# THIS RATIO when the matrix grows again; it is the thing that went stale
# silently last time, because nothing ever re-checked it.
CONF_DEFAULTS = {"tier": "full", "mid_tier": "full",
                 "fast_tier": "native", "interval": 60,
                 "debounce": 20, "no_bisect": False,
                 "autoticket": True,   # stub regression tickets (face 1)
                 # idle: the shards demoted out of the per-sha tiers for being
                 # the wall (testmgr.SLOW_SHARDS). Ranked above idle_opt — it
                 # is mainline coverage that used to run every sha.
                 "idle_slow": True,
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


# testmgr's exit code for "another run holds the repo lock, I refuse to start".
# NOT a fault: the box is fine and nothing was measured. Kept as a name because
# the difference between this and a real failure decides whether we reseed the
# compiler, and reseeding on contention corrupts the run that holds the lock.
TESTMGR_RC_LOCKED = 2

_GATE_PROC = None      # the testmgr child of the CURRENT cycle, if any


def _kill_orphan_gate():
    """Tear down a gate child left running by a cycle that threw.

    On 2026-08-12 a transient `git fetch` (exit 128) raised inside the cycle
    that had already started a full-tier testmgr. The handler retried the cycle
    but nothing killed that child, so it ran on holding the repo lock; the
    retry's testmgr hit `a run is ALREADY LIVE` and returned rc=2; twatch read
    that as a broken box and reseeded compiler/pascal26 *underneath the orphan*,
    which noticed and logged it. The orphan then finished GREEN 2293/2293 and
    its result was thrown away, while the box sat wedged for 16 hours.

    One transient network error should cost one cycle, not the run in flight
    and not the next three hours.
    """
    global _GATE_PROC
    proc, _GATE_PROC = _GATE_PROC, None
    if proc is None or proc.poll() is not None:
        return False
    print("twatch: cycle failed with a gate still running (pid %d) — tearing "
          "it down; leaving it would orphan the repo lock and make the next "
          "cycle collide with it" % proc.pid, flush=True)
    kill_child(proc)
    return True


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


LOG_CAP_BYTES = 64 * 1024 * 1024


def rotate_log(clone_path, cap=LOG_CAP_BYTES):
    """Cap our own log. Nothing else was ever going to do it.

    `trackt install` points the unit's stdout at `<clone>.log` with
    `append:`, and both that and `trackt start` then append forever: on plexus
    it had reached 281 MB. No logrotate config covers a user unit's
    `append:` file, and the daemon is the only writer, so it caps itself.

    copytruncate, NOT rename: systemd opened that fd before ExecStart and would
    keep writing into the renamed inode. Truncating in place keeps the fd
    valid, and O_APPEND means the next write lands at the new end rather than
    leaving a sparse hole.
    """
    path = clone_path.rstrip("/") + ".log"
    try:
        if os.path.getsize(path) < cap:
            return False
        shutil.copyfile(path, path + ".1")
        os.truncate(path, 0)
    except OSError as e:
        print("twatch: could not rotate %s: %s" % (path, e), flush=True)
        return False
    # lands as the first line of the fresh log, which is where you want it
    print("twatch: log passed %d MiB — previous content is now %s.1"
          % (cap >> 20, path), flush=True)
    return True


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
        self.heal_truncations()
        dirty = self.dirty()
        if dirty:
            sys.exit("twatch: %s has uncommitted changes — this looks like a "
                     "dev checkout, not a dedicated watcher clone. Refusing.\n%s"
                     % (path, dirty[:500]))

    def dirty(self):
        """Tracked changes only (-uno): untracked scratch (our own report
        file, corpus trees) is harmless — detached checkouts don't touch it."""
        return sh(["git", "status", "--porcelain", "-uno"], cwd=self.path)

    def publish_own_writes(self, host):
        """Commit dirt confined to tstate/ — it can only ever be ours.

        The dirty guard below exists to stop a HUMAN's edit being trampled by a
        detached checkout, and to stop dev sources leaking into a run. It is
        right about both. It is wrong about `tstate/`, because that directory is
        face 1's entire write scope and nothing else on the box writes there —
        so when it pauses on tstate dirt it is waiting for a commit that only
        the paused daemon could make.

        That deadlock has now happened twice from two different call sites: the
        `last_opt` bookkeeping on 2026-07-11, and mark_infra() on 2026-08-12,
        which cost 16 hours. Both were fixed at the call site. This fixes the
        SHAPE instead: any bare save_state() from any future path self-heals on
        the next cycle rather than taking the box dark, because publishing our
        own record is always the right answer and pausing forever never is.

        Deliberately narrow — tracked, modified, under tstate/ only. A dirty
        file anywhere else still pauses exactly as before, AND suppresses this
        entirely: if anything outside tstate/ is dirty we publish nothing and
        fall through to the pause. That is not tidiness, it is safety. publish()
        can hit a rebase conflict, and its recovery is `_drop_to_origin()` —
        a `reset --hard`, which would take a human's uncommitted edit with it.
        The old code could never do that because publish() was only reachable
        after the guard had proven the tree clean; running before the guard
        removes that protection unless we restore it here.
        """
        mine, others = [], []
        for line in (self.dirty() or "").splitlines():
            m = re.match(r"^\s*([A-Z?!]{1,2})\s+(.*)$", line)
            if not m or "D" in m.group(1) or "R" in m.group(1):
                continue
            rel = m.group(2).strip().strip('"')
            (mine if rel.startswith(TSTATE_REL.rstrip("/") + "/")
             else others).append(rel)
        if not mine or others:
            return []
        print("twatch: %d uncommitted tstate file(s) — ours by definition, "
              "publishing rather than pausing on them: %s"
              % (len(mine), ", ".join(os.path.basename(p) for p in mine)),
              flush=True)
        self.publish("tstate(%s): publish uncommitted state (%s)"
                     % (host, ", ".join(os.path.basename(p) for p in mine)))
        return mine

    def heal_truncations(self):
        """Restore tracked files an unclean shutdown zeroed. Returns the list.

        The guard above is right to refuse a dirty tree, but it cannot tell a
        human editing this checkout from the tree being CORRUPTED underneath
        it, and it fails the same way in both cases: exit 1, which under
        `Restart=on-failure` is an invisible 30-second restart loop.

        On 2026-08-11 plexus lost power mid-publish. ext4's delayed allocation
        did what it always does after an unclean shutdown — the files most
        recently written came back at length zero, seven of them, all tracked,
        five of them ours. The daemon then refused to start and looped 326
        times over 2h45m while nothing tested a single commit for 13.6 hours.
        Nobody was editing anything; the guard just had no vocabulary for
        "corrupt".

        `size == 0 on disk AND non-empty at HEAD` is that vocabulary. It is a
        narrow, evidence-based signature: no edit anyone makes on purpose looks
        like this, and restoring is provably lossless — a zero-byte file has
        nothing in it to lose. Anything else dirty still hits the refusal, so
        an actual dev checkout is as protected as it was.

        Deliberately not restricted to `tstate/**`: that power cut also zeroed
        a backlog ticket, and healing only our own files would have left the
        tree dirty and the daemon still looping. The signature is what makes
        this safe, not the path.
        """
        healed = []
        for line in (self.dirty() or "").splitlines():
            # porcelain v1 is XY<space>path, but do NOT slice at a fixed offset:
            # sh() strips the whole blob, so the FIRST line loses its leading
            # space and everything after it shifts by one. In the incident that
            # first line was the truncated backlog ticket, i.e. the fixed slice
            # silently skipped one of the very files this exists to restore.
            m = re.match(r"^\s*([A-Z?!]{1,2})\s+(.*)$", line)
            if not m:
                continue
            code, rel = m.group(1), m.group(2).strip().strip('"')
            if "R" in code or "D" in code:   # rename has ` -> `; delete has no file
                continue
            full = os.path.join(self.path, rel)
            try:
                if os.path.getsize(full) != 0:
                    continue
                head = sh(["git", "cat-file", "-s", "HEAD:" + rel],
                          cwd=self.path)
                if not head or int(head) == 0:
                    continue
            except (OSError, ValueError, RuntimeError):
                # unreadable, or not in HEAD at all (a staged add): not ours
                continue
            healed.append(rel)
        if healed:
            sh(["git", "checkout", "--"] + healed, cwd=self.path)
            print("twatch: %d tracked file(s) were zero-length on disk but "
                  "non-empty at HEAD — an unclean shutdown truncated them. "
                  "Restored from HEAD (a zero-byte file has nothing to lose): "
                  "%s" % (len(healed), ", ".join(healed)), flush=True)
        return healed

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
    # Published so the cycle's exception handler can tear this down. Without it
    # an exception anywhere in the cycle unwinds past every local `proc`, the
    # child keeps running and keeps the repo lock, and the retried cycle
    # collides with its own orphan — see _kill_orphan_gate().
    global _GATE_PROC
    _GATE_PROC = proc
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
    _GATE_PROC = None          # reaped: nothing left for the handler to kill
    report = None
    if os.path.exists(rep_path):
        with open(rep_path) as f:
            report = json.load(f)

    # Two shapes of the SAME condition — this box cannot produce a measurement:
    #
    #   * no report at all: testmgr died before reporting;
    #   * a report whose verdict is INFRA: testmgr reached the end and said so
    #     (today: the compiler could not be built from these sources here).
    #
    # The second case used to be missed, and that is the whole plexus incident
    # of 2026-08-07. report_build_failure() WRITES a report, so `not
    # os.path.exists(rep_path)` was False, so this recovery never fired — the
    # one path that could have healed the box was dead exactly when it was
    # needed. The seed stayed poisoned (021ead850d60) for hours while every
    # cycle published a fresh false RED.
    #
    # The likely cause is a STALE or poisoned seed binary that cannot compile
    # HEAD's sources (e.g. a since-fixed compiler bug rejects new valid code —
    # WsPos incident 2026-07-11; or a mid-bisect binary from an old sha that
    # miscompiles the current tree into a stage-1 that segfaults on startup).
    # Recovery: reseed from the committed pinned stable and retry once; without
    # this the watcher wedges retesting the same SHA forever.
    # rc=2 is testmgr REFUSING TO START because another run holds the repo lock.
    # That is not a degraded box, it is contention, and the two need opposite
    # responses: a poisoned seed wants a reseed, a busy repo wants patience.
    # Reseeding here is actively destructive — it unlinks and rebuilds
    # compiler/pascal26 underneath the run that legitimately holds the lock,
    # which on 2026-08-12 made a live full-tier run log "compiler/pascal26
    # changed during this run". Nothing measured, nothing broken: skip the
    # cycle and come back.
    if proc.returncode == TESTMGR_RC_LOCKED:
        print("twatch: testmgr refused — another run holds the repo lock "
              "(rc=%d). Contention, not a fault: no reseed, no verdict, no "
              "infra record; retrying next cycle." % TESTMGR_RC_LOCKED,
              flush=True)
        return None, "busy"

    infra = report is not None and report.get("verdict") == "INFRA"
    if report is None or infra:
        if not _reseeded and (proc.returncode or infra):
            print("twatch: %s — reseeding compiler from pinned stable and "
                  "retrying once"
                  % ("INFRA: %s" % (report.get("reason") or "no measurement")
                     if infra else "no report (rc=%s)" % proc.returncode),
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
                return report, proc.returncode
            return run_gate(clone, tier, job_glob=job_glob,
                            abort_check=abort_check, _reseeded=True)
        # Reseeding already happened and it STILL cannot build: a real box
        # fault. Hand the INFRA report up so test_sha can mark the host
        # degraded instead of silently treating it as "nothing happened".
        return report, proc.returncode
    return report, proc.returncode


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


def last_covering_sha(st, tier, exclude_sha):
    """Newest earlier run that certainly CONTAINED this tier's jobs, or None.

    The per-job range fallback. `commits_between(parent, sha)` measures "since
    this host last tested ANYTHING", and the two-phase watcher deliberately
    re-tests one commit at a widening tier (native for speed, then the full/opt
    backfill when the repo goes idle) — so on the second pass parent == sha and
    the range is empty. The information is not missing, it is in the wrong
    place: what matters is "since this JOB last ran and passed".

    A run at tier E contains every job of the tiers E nests over. This job just
    appeared in a run at `tier`, so it belongs to some tier at or below `tier`,
    and therefore any earlier run E with `tier in covered_tiers(E)` definitely
    contained it. That test is deliberately CONSERVATIVE: an earlier, narrower
    run may also have contained the job, and skipping it only widens the range.
    A too-wide range costs bisect steps; a too-narrow one can exclude the
    culprit, which is the failure that matters.

    `opt` is disjoint (covered_tiers("opt") == {"opt"}), so only earlier opt
    runs can answer for an opt job — which is correct, and is why the
    optdiff#shard8-12 miscompile sat two days unattributed.
    """
    for h in reversed(st.get("history") or []):
        if h.get("sha") == exclude_sha:
            continue                  # the same commit re-tested at a wider tier
        if tier in covered_tiers(h.get("tier") or ""):
            return h.get("sha")
    return None


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


def gone_keys(st, now, tier):
    """Job keys the ledger names that NO TIER HAS ANY MORE.

    A key stops existing for two routine reasons: a test is renamed or deleted,
    or `assign_selectors`' `@N` suffix shifts because a source's occurrence
    count inside its target changed. The second is not the corner case its
    docstring assumes — on 2026-08-04 one nilpy source sat in the Makefile three
    times (an agent had overwritten an existing test with a same-named new one),
    so its keys were `…npy@0/@1/@2`, and reverted to the bare key hours later
    when the duplicates went. 110 of xeon's keys currently carry an `@N`.

    Judged against TIER COVERAGE, never against one run: "this run could have
    run that job and did not" is a statement about existence, while "not my
    tier" says nothing at all. Confusing the two is what made a full run evict
    opt's verdicts and re-report `optdiff#shard5/6` as NEW-RED once per cycle,
    forever.
    """
    cov = covered_tiers(tier)
    jt = st.get("job_tier", {})
    named = set()
    for r in st.get("open_regressions", []):
        named.update(r.get("cascade") or [r["job"]])
    return {k for k in named
            if k not in now and jt.get(k, tier) in cov}


def orphan_keys(st, now, tier):
    """Job-map keys that no longer EXIST, judged the way gone_keys judges.

    Same predicate as gone_keys — "a run whose tier covers this job's tier did
    not produce it, so it is gone" — but over the whole persisted job map
    rather than only the keys an open regression happens to name.

    The map is never pruned, on purpose: a full run contains no `opt` jobs, so
    dropping absent keys would evict verdicts a later opt run still owns. The
    cost is that a renamed job leaves its last status behind forever. Harmless
    for reporting, NOT harmless for auto-pin: `selfhost-fixedpoint#src:compiler/
    compiler.pas` sat `fail` in plexus.json long after the job's src became
    `tools/selfhost_fixedpoint.sh` and started passing under the new key, and a
    red that no run can ever clear would have blocked every future pin.
    """
    cov = covered_tiers(tier)
    jt = st.get("job_tier", {})
    return {k for k in (st.get("jobs") or {})
            if k not in now and jt.get(k, tier) in cov}


def reg_open(r, authoritative, gone=frozenset()):
    """Is this ledger entry still an open regression after the latest run?

    `gone` names keys no tier carries any more (see gone_keys). Such an entry
    can never be closed by status — no run will ever REPORT that key again — so
    without this it stays open forever, asking agents to act on a job that
    cannot be run. Same shape as a quiet host's immortal entries
    (task-t-borg-open-regression-is-permanently-stale), reached through job
    identity instead of host identity.

    Both branches ask ONE question of ONE map: does the merged status still say
    red? A per-job entry closes when its job is passing; a CASCADE entry names
    no single job (its "job" is a synthetic cascade@<sha> key no run can
    report), so it closes only once every job it swept up is genuinely passing
    again — otherwise it would pin itself open forever.

    `authoritative` is the MERGED per-job status (persisted st["jobs"] overlaid
    with this run's results), NOT just this run's `now`.  Using this run alone
    closed a cascade whenever ONE run happened to show every swept job as
    non-red — which bit us 2026-07-20/21: the riscv32 record-result cascade
    (18 jobs) closed off a single lucky full run, then the jobs failed again as
    STILL-RED (filing nothing), so 17 jobs sat `fail` in the jobs map with the
    cascade gone from open_regressions.  Against the merged map a job that is
    still `fail` in the persisted state keeps the cascade open even when this
    tier did not run it.

    A `skip` is PASS-LIKE here (see PASSLIKE): it does not gate, and red -> skip
    still closes an open regression, because a box that legitimately cannot run
    a job must not hold a regression open forever.  It is NOT proof a
    regression is fixed, so a cascade whose jobs only ever SKIP still closes
    wrongly — a known residual, unchanged by publishing skip as its own status.
    The merged-map fix removes the common transient-flake close, which is what
    actually happened here.
    """
    if r.get("cascade"):
        # A swept job that no longer exists cannot pin the cascade open either;
        # if every job it named is gone, the entry closes with them.
        return any(authoritative.get(j, "red") not in PASSLIKE
                   for j in r["cascade"] if j not in gone)
    if r["job"] in gone:
        return False
    # Ask the merged map, exactly as the cascade branch above does — NOT "is
    # this job in `fixed`". `fixed` names red->pass TRANSITIONS THIS HOST
    # OBSERVED, and an entry can enter the ledger without this host ever having
    # seen the red: retire_host() migrates a dead host's open regressions into
    # the survivor. If the job already passes here, the transition can never
    # happen, so the entry is immortal — the fpc-bootstrap#00 entry migrated
    # from borg sat open from 2026-07-22 to 2026-08-13 with the job reading
    # `pass` in the same file. Same immortality as
    # task-t-borg-open-regression-is-permanently-stale, reached through a third
    # door (host identity, then job identity, now provenance).
    #
    # Equivalent to the old test for every entry this host opened itself — a
    # job in `fixed` is passlike in `now` and therefore in the merged map — so
    # this only closes entries the old test could never reach.
    return authoritative.get(r["job"], "red") not in PASSLIKE


        # PASS-LIKE, not pass. A skipped job did not fail, so it must not gate
# anything — but it did not RUN either, and publishing it as "pass" destroyed
# the only evidence of that. On xeon 33 full-tier jobs skip when the corpus
# trees are unfetched, including all 24 c-testsuite conformance jobs, and the
# host still published GREEN. Every consumer — cross-host comparison,
# --status, the dashboard, the cutover decision — read that as covered.
#
# The old comment's reasoning was right that skip must close an open
# regression; it was wrong to achieve that by erasing the distinction rather
# than by treating a third state as non-gating. Green must mean "ran and
# passed". Now made worse by test-uforth, which self-skips on any box without
# ~/projects/uforth (feature-t-enroll-uforth-in-the-tiers).
PASSLIKE = ("pass", "skip")


def diff_jobs(prev_jobs, report):
    # `now` keeps the LITERAL status, so tstate publishes "skip" as itself.
    # Readers were taught the third state before anything started writing it
    # (reg_open, gone_keys, the status/index summaries), which is the migration
    # order the ticket asks for: old states carrying "pass" for former skips
    # stay readable, they simply under-report coverage until the host publishes
    # again.
    now = {job_key(j): j["status"] for j in report["jobs"]}
    new_red = sorted(n for n, s in now.items()
                     if s not in PASSLIKE
                     and prev_jobs.get(n, "pass") in PASSLIKE)
    fixed = sorted(n for n, s in now.items()
                   if s in PASSLIKE
                   and prev_jobs.get(n, "pass") not in PASSLIKE)
    still_red = sorted(n for n, s in now.items()
                       if s not in PASSLIKE
                       and prev_jobs.get(n, "pass") not in PASSLIKE)
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
             # WHICH binary produced this verdict. The json has carried it since
             # the mid-run-change check; the markdown is what a human reads days
             # later, and "verify against a KNOWN sha" is unusable if the report
             # does not name the binary (task-t-seed-from-stable-defeats-rebuild).
             "compiler_sha256: %s" % (report.get("compiler_sha256") or "unknown"),
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
        if "host" not in st:
            continue            # a side file, not a per-host state document
        last = st.get("last") or {}
        lf = st.get("last_full") or {}
        quiet = host_quiet_secs(st)
        if st.get("retired_at"):
            # Retired: one row for the record, and NOTHING in the regression or
            # held sections — it holds no entries and can never clear any.
            rows.append("| %s _(retired %s%s)_ | `%s` | %s | %s (%s) | %ss | `%s` %s |" %
                        (st["host"], st["retired_at"],
                         " → %s" % st["retired_into"]
                         if st.get("retired_into") else "",
                         (last.get("sha") or "")[:12],
                         last.get("date", ""), last.get("verdict", "never-ran"),
                         last.get("tier", "?"), last.get("wall", ""),
                         (lf.get("sha") or "")[:12], lf.get("verdict", "")))
            continue
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
# ------------------------------------------------------------ auto-pin ---
# `make pin` moves `pinned`, the ground every other track builds on (B/C/D/E
# all build with $(PXX_STABLE)), so a bad pin does not fail one job — it
# silently rebases everyone onto a broken compiler. The cost is asymmetric
# against pinning too eagerly, which is why decide-track-t-autopin-criteria
# was answered "never auto-pin" on 2026-08-01 and DEFERRED until the baseline
# justified the machinery. It now does: plexus at 450bb7f86a75 was 2180/2182,
# and the 18-job permanently-red list that made "all green" unfireable is gone.
#
# Reopened 2026-08-08 by the user, who chose the ticket's own recommendation:
# option A (baseline allowlist) with K>=2 consecutive qualifying shas and
# auto-rollback, STARTING IN SHADOW MODE. Nothing here moves `pinned`. It
# records the decision it WOULD have made so a week of them can be compared
# against what a human actually blessed — evidence instead of argument.
PIN_ALLOWLIST_REL = TSTATE_REL + "/pin-allowlist.tsv"
PIN_SHADOW_REL = TSTATE_REL + "/pin-shadow.log"
PIN_STREAK_K = 2          # one clean matrix can be luck; today proved phantoms
PIN_TIER = "full"         # only the broadest nested tier may qualify a pin
SELFHOST_SEL_PREFIX = "selfhost-fixedpoint"


def load_pin_allowlist(clone):
    """{job selector: ticket slug} of reds that do NOT block a pin.

    Every entry MUST name a ticket. That is the whole design: it makes "we are
    shipping with these known breaks" an explicit, reviewable statement rather
    than a dumping ground. An entry without a ticket is refused and said out
    loud, so the file cannot quietly grow.
    """
    out, bad = {}, []
    p = os.path.join(clone.path, PIN_ALLOWLIST_REL)
    try:
        with open(p) as f:
            for ln in f:
                # A comment is a LEADING '#' only. Job selectors contain '#'
                # (`test-zlib#00`), so stripping inline comments at '#' silently
                # truncated every entry to its target name and the allowlist
                # loaded empty — caught by the devtest, not by reading it.
                ln = ln.strip()
                if not ln or ln.startswith("#"):
                    continue
                parts = ln.split()
                if len(parts) < 2:
                    bad.append(ln)
                    continue
                out[parts[0]] = parts[1]
    except OSError:
        return {}, []                 # absent is fine: nothing is allowlisted
    return out, bad


def pin_shadow(clone, host, st, sha, report, authoritative, now=None):
    """Would this sha have qualified for an automatic pin? LOG ONLY.

    Deliberately never touches `pinned`, `make pin`, or `stable_linux_amd64/**`
    — face 1's write scope is tstate/ and this stays inside it.
    """
    if report.get("tier") != PIN_TIER:
        return                        # only the broadest tier may qualify one
    allow, bad = load_pin_allowlist(clone)
    for ln in bad:
        print("twatch: pin-allowlist entry ignored (no ticket named): %s" % ln,
              flush=True)
    # Orphans do not count. A key the map still carries but no run can produce
    # any more is unclearable by construction, so letting one block a pin means
    # never pinning again — see orphan_keys.
    orphans = orphan_keys(st, now, report.get("tier")) if now is not None else set()
    reds = sorted(j for j, s in authoritative.items()
                  if s not in PASSLIKE and j not in orphans)
    if orphans:
        stale_red = sorted(j for j in orphans
                           if authoritative.get(j) not in PASSLIKE)
        if stale_red:
            print("twatch: [pin shadow] ignoring %d stale red key(s) no run can "
                  "produce any more: %s" % (len(stale_red), ", ".join(stale_red[:3])),
                  flush=True)
    unexpected = [j for j in reds if j not in allow]
    # The one property that can never be waived: a compiler that cannot
    # reproduce itself must not become anyone's ground, allowlist or not.
    # Orphans are excluded here too — the stale
    # `selfhost-fixedpoint#src:compiler/compiler.pas` key would otherwise fail
    # this check forever while the live key passes under its new src. But
    # `all()` over an empty set is True, and "no self-host evidence" must never
    # read as "self-host is clean": require at least one LIVE selfhost job, and
    # require it to pass.
    # Ask about THIS RUN, not the merged map. The merged map carries whatever
    # any tier last said, and a stale selfhost key recorded under `opt`
    # (`selfhost-fixedpoint#src:compiler/compiler.pas`, from before the job's
    # src changed) cannot be recognised as an orphan during a full run —
    # `opt` is disjoint from full's coverage, so the tier rule correctly
    # refuses to call it gone. It blocked four consecutive shadow verdicts.
    #
    # The honest question is simply "did the self-host job pass in the run we
    # are judging?", and every tier that may qualify a pin contains that job.
    # `now` cannot be stale, so this cannot be poisoned by history.
    live_sh = {j: s for j, s in (now or {}).items()
               if j.startswith(SELFHOST_SEL_PREFIX)}
    selfhost_ok = bool(live_sh) and all(s in PASSLIKE for s in live_sh.values())
    qualifies = not unexpected and selfhost_ok
    prev = st.get("pin_shadow") or {}
    streak = (int(prev.get("streak") or 0) + 1) if qualifies else 0
    would = qualifies and streak >= PIN_STREAK_K
    st["pin_shadow"] = {"streak": streak, "sha": sha, "at": utcnow(),
                        "qualifies": qualifies, "would_pin": would,
                        "unexpected": unexpected[:20], "reds": len(reds)}
    if would:
        why = "WOULD PIN %s — %d red(s), all allowlisted, self-host clean, " \
              "streak %d/%d" % (sha[:12], len(reds), streak, PIN_STREAK_K)
    elif qualifies:
        why = "would-pin PENDING %s — qualifies, streak %d/%d" \
              % (sha[:12], streak, PIN_STREAK_K)
    elif not selfhost_ok:
        why = "would NOT pin %s — self-host is not clean (never waivable)" \
              % sha[:12]
    else:
        why = "would NOT pin %s — %d red(s) not in the allowlist: %s" \
              % (sha[:12], len(unexpected), ", ".join(unexpected[:5]))
    print("twatch: [pin shadow] %s" % why, flush=True)
    try:
        with open(os.path.join(clone.path, PIN_SHADOW_REL), "a") as f:
            f.write("%s\t%s\t%s\t%s\n" % (utcnow(), host, sha, why))
    except OSError as e:
        print("twatch: could not record the pin-shadow line (%s)" % e,
              flush=True)


def no_measurement(report):
    """Did this run produce no measurement at all? Returns a reason, or "".

    The publish-time backstop for the whole false-RED family. A verdict is a
    claim about the SOURCES; it may only be published by a run that actually
    executed something. Two independent tells, either of which is conclusive:

      * `compiler_sha256` absent or "unknown" — a real run always snapshots the
        binary it tested (testmgr writes `snap_sha or repo_sha0`), so a verdict
        that cannot name its compiler was not produced by one;
      * no jobs — nothing ran, so there is nothing to have a verdict about.

    `wall == 0.0` is deliberately NOT conclusive on its own: a tier that
    matches no job legitimately finishes in no time. Paired with a missing
    compiler hash it is the exact signature the ticket named.

    This is belt-and-braces with the INFRA verdict, on purpose. INFRA depends
    on testmgr correctly labelling its own failure; this guard depends on
    nothing but the shape of the report, and so still holds if some future
    path invents a third way to emit an empty run.
    """
    if not report.get("compiler_sha256") or \
            report.get("compiler_sha256") == "unknown":
        return "compiler_sha256 is %s" % (report.get("compiler_sha256")
                                          or "absent")
    if not report.get("jobs"):
        return "0 jobs in the report"
    return ""


def mark_infra(clone, host, st, sha, tier, reason):
    """Record that this box could not run — and keep it out of the ledger.

    PUBLISHES, and must: a bare save_state() leaves the clone dirty, and the
    per-cycle dirty guard then pauses every following cycle forever, because the
    only thing that writes tstate/ is the daemon and the daemon is paused. The
    identical bug was found in the `last_opt` bookkeeping on 2026-07-11 and
    fixed only there; this sibling went unnoticed until it took the box dark for
    16 hours on 2026-08-12 — a full tier ran GREEN 2293/2293, testmgr returned
    rc=2, and the infra record written to explain that never got committed.
    """
    inf = st.get("infra") or {}
    st["infra"] = {"since": inf.get("since") or utcnow(), "last": utcnow(),
                   "sha": sha, "tier": tier, "reason": reason,
                   "count": int(inf.get("count") or 0) + 1}
    save_state(clone, host, st)
    clone.publish("tstate(%s): infra %s %s — %s"
                  % (host, sha[:12], tier, reason))


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
    # Contention, not a measurement and not a fault: record NOTHING. Falling
    # through would hit the `report is None` branch below and mark the host
    # infra-degraded for the crime of being busy.
    if rc == "busy":
        return "busy"
    if report is None:
        print("twatch: testmgr produced no report (rc=%s) — infra problem, "
              "not recording a verdict" % rc, flush=True)
        mark_infra(clone, host, st, sha, tier, "no report (rc=%s)" % rc)
        return False

    # INFRA: the run did not happen — the box could not build the compiler,
    # and run_gate already reseeded from the pinned stable and retried once.
    # Publish NOTHING: no verdict, no job map, no ledger entry, no bisect, no
    # ticket. A box that cannot run is not evidence about the sources, and the
    # cost of pretending otherwise is an innocent commit accused by a bisect
    # that had nothing real to narrow.
    if report.get("verdict") == "INFRA":
        why = report.get("reason") or "no measurement"
        print("twatch: %s INFRA — %s; host degraded, publishing no verdict "
              "(the sha stays untested and will be retried)"
              % (sha[:12], why), flush=True)
        mark_infra(clone, host, st, sha, tier, why)
        return False

    # Structural backstop, independent of the verdict label: refuse anything
    # that carries a verdict without having measured anything. See
    # no_measurement() for why these two tells are conclusive.
    empty = no_measurement(report)
    if empty:
        print("twatch: %s claims verdict %s but produced no measurement (%s) "
              "— refusing to publish it; host degraded"
              % (sha[:12], report.get("verdict"), empty), flush=True)
        mark_infra(clone, host, st, sha, tier, empty)
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
    gone = gone_keys(st, now, report["tier"])
    if gone:
        # Visible, never silent: an entry vanishing quietly is indistinguishable
        # from one being FIXED, and the ledger's whole value is that its entries
        # are actionable.
        print("twatch: %d ledger key(s) no longer exist in any tier — closing "
              "as GONE (renamed/removed test, or an @N selector shift): %s"
              % (len(gone), ", ".join(sorted(gone)[:5])), flush=True)
    regs = [r for r in st["open_regressions"]
            if reg_open(r, authoritative, gone)]
    # The entries this filter DROPS are exactly the regressions the ledger
    # considers closed, so they are also exactly the stubs face 1 may retire —
    # one rule, not a second invented one that could disagree with it.
    closed_regs = [r for r in st["open_regressions"]
                   if not reg_open(r, authoritative, gone)]
    srcmap = {job_key(j): j.get("src", "") for j in report["jobs"]}
    namemap = {job_key(j): j["name"] for j in report["jobs"]}
    rng = clone.commits_between(parent, sha) if parent else [sha]
    # PER-JOB RANGE FALLBACK. The parent-based range answers "since this host
    # last tested anything", which is empty exactly when the two-phase watcher
    # re-tests one sha at a widening tier — and an empty range is unbisectable,
    # so the red gets a stub ticket promising a bisect that bisect_step can
    # never perform (three instances in one session, 2026-08-04; the
    # optdiff#shard8-12 -O3 miscompile sat two days that way).
    #
    # So when it is empty, ask the narrower question the ledger actually needs:
    # since this JOB last ran under a tier that contained it.
    good = parent
    if new_red and not rng:
        y = last_covering_sha(st, report["tier"], sha)
        if y and y != sha:
            rng = clone.commits_between(y, sha)
            if rng:
                good = y
                print("twatch: parent range empty (%s re-tested at %s) — using "
                      "the per-job range since %s, %d commit(s)"
                      % (sha[:12], report["tier"], y[:12], len(rng)),
                      flush=True)
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
                     "cascade": sorted(new_red), "bad": sha, "good": good,
                     "range": rng, "opened": utcnow()})
    else:
        for name in new_red:
            # "job" is the stable selector; "name" is the positional name it
            # had at this sha — kept ONLY as the bisect fallback for older
            # commits, never as identity (see job_key).
            regs.append({"job": name, "name": namemap.get(name, ""),
                         "src": srcmap.get(name, ""), "bad": sha,
                         "good": good, "range": rng, "opened": utcnow()})
    st["open_regressions"] = regs

    changed = bool(new_red or fixed)
    rel = None
    if changed or report["verdict"] == "RED":
        rel = write_report_md(clone, host, sha, parent, report,
                              new_red, fixed, still_red)

    # A run that measured something proves the box works again — drop any
    # degraded marker, so the host stops reporting DOWN on its own the moment
    # it recovers (a reseed usually does it) with no manual clearing.
    st.pop("infra", None)
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
    # PRUNE keys this run PROVED do not exist. Same predicate gone_keys uses to
    # close a regression — "a run whose tier covers this job's tier did not
    # produce it" — so if that confidence is enough to close a ledger entry it
    # is enough to drop a map entry. Without this the map only grows: a renamed
    # job leaves its last status behind forever, and the auto-pin work found out
    # the hard way that a permanent stale `fail` is a permanent veto.
    #
    # Tier coverage is what makes this safe. A full run does not contain `opt`
    # jobs, so their verdicts are untouched here and are pruned (or refreshed)
    # by the next opt run instead.
    dead = orphan_keys(st, now, report["tier"])
    if dead:
        print("twatch: dropping %d job key(s) no tier produces any more: %s"
              % (len(dead), ", ".join(sorted(dead)[:5])), flush=True)
        st["jobs"] = {k: v for k, v in st["jobs"].items() if k not in dead}
        st["job_tier"] = {k: v for k, v in (st.get("job_tier") or {}).items()
                          if k not in dead}
        authoritative = {k: v for k, v in authoritative.items() if k not in dead}
    # Shadow only — records the pin it WOULD have made, moves nothing.
    pin_shadow(clone, host, st, sha, report, authoritative, now)
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
    record_host_epoch(clone, host)
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


def range_note(reg):
    """The Range section of a stub ticket — and it must not promise a bisect.

    A stub used to say "the watcher narrows this by idle bisect" unconditionally.
    With an empty range no ledger entry is opened, so `bisect_step` never sees
    the job and the promise is one nothing can keep — which is how a real -O3
    miscompile sat two days waiting for a bisect that was never coming. Say
    what is true instead, so the reader knows immediately whether to bisect it
    by hand.
    """
    n = len(reg.get("range") or [])
    bad = (reg.get("bad") or "")[:12] or "unknown"
    good = (reg.get("good") or "")[:12] or "unknown"
    if not n:
        return ("bad `%s`, range **unknown** (first run covering this job at "
                "this tier, so there is no earlier passing sha to bound it) — "
                "**no idle bisect will happen**; this one needs hand-triage."
                % bad)
    return ("bad `%s`, last good `%s`, %d commit(s) in range — the watcher "
            "narrows this by idle bisect; check tstate/TSTATE.md for the "
            "current range." % (bad, good, n))


SRC_RE = re.compile(r"^- \*\*Test source:\*\* (.+)$", re.M)
# the stub's repro line names the job selector it was filed for
JOB_RE = re.compile(r"--job '([^']+)'")


def stub_sources(pdir):
    """{test source -> slug} over every auto-filed stub in every bucket.

    One test SOURCE can be exercised by several jobs — `test/x.npy` runs under
    both `test-core` and `test-nilpy` — and the stub slug is the job selector,
    so one broken file filed two tickets
    (`test_nilpy_augmented_assign_class_dunder`, 2026-08-06). Two tickets for
    one fix is queue noise of the same kind this ticket is about.

    Scanned once per filing pass, not once per job: `new_red` is capped by
    CASCADE_THRESHOLD, but the bucket holds ~200 files.
    """
    out = {}
    # OPEN buckets only. A ticket in done/ or rejected/ is a finished argument,
    # and a source going red again after it closed is a NEW finding that must
    # get its own stub — `already_filed` scans every bucket on purpose (same job,
    # same slug, never two tickets), but that reasoning does not carry over to
    # "some other job once had trouble with this file". Found 2026-08-09: the
    # optdiff dedupe was matching `regression-optdiff-shard4-6`, resolved days
    # earlier and sitting in done/.
    for b in ("urgent", "working", "unfinished", "backlog", "blocked"):
        d = os.path.join(pdir, b)
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for fn in names:
            if not fn.endswith(".md"):
                continue
            p = os.path.join(d, fn)
            try:
                if os.path.getsize(p) == 0:      # debris, see already_filed
                    continue
                with open(p, errors="replace") as f:
                    body = f.read(4096)          # the header is all we need
            except OSError:
                continue
            if STUB_MARKER not in body:
                continue                         # somebody's analysis, not a stub
            m = SRC_RE.search(body)
            if m:
                jm = JOB_RE.search(body)
                tgt = jm.group(1).split("#")[0] if jm else ""
                out.setdefault(m.group(1).strip(), (fn[:-3], tgt))
    return out


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
    pdir = os.path.join(clone.path, "devdocs/progress")
    by_src = stub_sources(pdir)      # one scan, then updated as we file
    for job in new_red:
        slug = reg_slug(job)
        if already_filed(pdir, slug):
            continue
        j = next((x for x in report["jobs"] if job_key(x) == job), {})
        # DEDUPE BY TEST SOURCE. The slug is the job selector, so the same
        # broken file reached through two jobs files two tickets — one fix,
        # two things to close. Key the filing on the source; closing still
        # keys on the job, which is what close_stub_tickets already does.
        src = (j.get("src") or "").strip()
        owner, owner_tgt = (by_src.get(src) or (None, None)) if src else (None, None)
        # Dedupe ACROSS TARGETS only. The case this exists for is one TEST FILE
        # reached by two different targets (test/x.npy under both test-core and
        # test-nilpy) — one bug, one ticket. SHARDS of a single target are not
        # that: `optdiff#shard1/12` and `optdiff#shard4/6` merely share
        # `tools/optdiff.sh` as their `src`, because that is the DRIVER, not the
        # program under test. Suppressing on it silently swallowed two real -O3
        # miscompiles on 2026-08-09 (cmath_sign_bits rc 42 vs 1).
        if owner and owner != slug and owner_tgt and owner_tgt != job.split("#")[0]:
            print("twatch: %s is red too, but %s already covers %s — not "
                  "filing a second stub for one source" % (job, owner, src),
                  flush=True)
            continue
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
%s

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
                range_note(reg), tail))
        write_ticket(os.path.join(clone.path, rel), body)
        filed.append(rel)
        if src:
            # so a sibling job on the same source, later in THIS batch, sees it
            by_src[src] = (slug, job.split("#")[0])
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
    # Filing now dedupes by test SOURCE, so one stub can be the only ticket for
    # a source that several jobs exercise. Closing it because the job it was
    # named after went green would then leave a still-broken source with no
    # ticket at all — and no way to get one, since the other job is STILL-RED
    # rather than NEW-RED and nothing files on still-red. So: a stub whose
    # source is red in ANY job of this report stays open.
    red_srcs = {(j.get("src") or "").strip() for j in report["jobs"]
                if j.get("status") in ("fail", "timeout")}
    red_srcs.discard("")
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
        m = SRC_RE.search(body)
        if m and m.group(1).strip() in red_srcs:
            print("twatch: %s's job is green, but %s is still red in another "
                  "job — keeping the stub open (it is that source's only "
                  "ticket)" % (slug, m.group(1).strip()), flush=True)
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


# Bench needs the box to itself, and must give it back.
#
# A timing measured while something else runs is not slow, it is VOID — and it
# does not announce itself as void, it announces itself as `SLOW (was ...)`,
# i.e. in a regression's own words. Measured 2026-08-04: an agent's compiler
# builds and gate runs in a dev checkout inflated a batch by up to +24%, with
# the FPC rows — which pxx is not involved in at all — up 14.8%, the control
# that settles it. The inflation was PER-ROW (mandelbrot within 0.2%,
# selfcompile +23%) because the load was intermittent, so a contended window
# cannot be salvaged row by row: the numbers cannot say which ones were hit.
#
# Worse than the bad batch: it silently becomes the next baseline, so the
# following clean batch reads as a 20% IMPROVEMENT — the harder direction to
# notice. bug-t-bench-timings-recorded-under-co-tenancy.
#
# WHY A PROBE AND NOT loadavg. The first cut gated on /proc/loadavg and was
# wrong in both directions, measured on this 12-core box:
#
#     busy cores | probe ratio | loadavg
#     -----------|-------------|--------
#          0     |    1.00     |  17.22   <- quiet, but loadavg says otherwise
#          4     |    1.09     |  16.88
#         12     |    2.17     |  17.62
#         24     |    4.75     |  21.53   <- a full gate (testmgr cap=24)
#
# loadavg is a 1-minute EXPONENTIAL AVERAGE: it still reads 17 on a box that
# went quiet a minute ago, and it cannot separate quiet from 12 busy cores. So
# it blocks benching long after a burst ends and would wave one through at the
# start of a fresh burst. The probe measures the CPU actually available to a
# single thread RIGHT NOW, which is what the bench itself experiences.
#
# The tolerance is deliberately generous: this box has 12 cores and is meant to
# be worked on, so a third of it busy (ratio 1.09) must NOT block a batch —
# ordinary agent work costs 1-2 cores. What it rejects is oversubscription, and
# the contaminating gate run sat at 4.75x, nowhere near the line.
BENCH_PROBE_ITERS = 1_000_000
BENCH_PROBE_SAMPLES = 3      # min of N: a single probe's noise spans ~10%
# Generous ON PURPOSE. Measured here: 4 of 12 cores busy reads 1.09-1.19 —
# an agent doing ordinary work — while 12 busy is 2.17 and an oversubscribed
# gate run (testmgr cap=24) is 4.75. The line sits well above the first and
# well below the second, because a box with 12 cores is meant to be worked on
# and a bench that never runs is worth less than one measured beside a build.
BENCH_PROBE_TOL = 1.35
BENCH_POLL_SECS = 30.0
# The reference is the fastest probe ever seen on this host, so there is no
# per-box constant to tune and a faster box calibrates itself. The risk of a
# min-forever reference is that it becomes unreachable (thermal throttling, a
# CPU governor change, a Python upgrade) and bench then NEVER runs again — so
# it relaxes 5% after this many consecutive skips. Starvation self-heals; a
# genuinely quieter moment still pulls the reference back down.
BENCH_SKIP_RELAX_AFTER = 12
BENCH_RELAX_FACTOR = 1.05
# In MEMORY, never in tstate. These are operational counters, not published
# state, and writing them to a tracked file outside a publish left the clone
# DIRTY — which the daemon's dirty-clone guard then treats as "pause every
# cycle until a human intervenes". That wedged the watcher for 11 hours on
# 2026-08-04 over a one-line `bench_skips: 0 -> 1` diff. Anything written to
# the clone must ride a publish or not be written at all.
_BENCH_RT = {}          # host -> {"skips": int, "probe_ref": float}


def speed_probe(iters=BENCH_PROBE_ITERS):
    """Seconds for a fixed integer workload — a pure hardware/contention signal.

    Deliberately does NOT use the compiler under test. A probe that compiled
    something would slow down when the COMPILER regressed, and bench would then
    switch itself off exactly when there was a regression worth measuring.
    """
    t0 = time.perf_counter()
    x = 0
    for i in range(iters):
        x = (x * 31 + i) & 0xFFFFFFFF
    return time.perf_counter() - t0


def hours_since(iso):
    """Hours since an ISO-8601 Z timestamp, or None if there isn't one."""
    if not iso:
        return None
    try:
        return (time.time() - calendar.timegm(
            time.strptime(iso, "%Y-%m-%dT%H:%M:%SZ"))) / 3600.0
    except ValueError:
        return None


def box_speed(host):
    """(ratio, seconds) — how much slower than this host's best-ever probe.

    Min of several samples: one probe's noise spans ~10%, which is the same
    order as the contention worth detecting, and min is the right statistic —
    it is the least-interrupted sample rather than an average of interruptions.

    The reference lives in memory (see _BENCH_RT): it is a calibration detail,
    it self-recovers from the first probe after a restart, and persisting it
    would mean writing to the clone outside a publish.

    KNOWN LIMITATION: on a fresh store the first probe DEFINES the reference,
    so it always reads 1.00 and the first bench after a daemon restart is
    effectively ungated. Subsequent quieter probes pull the reference down and
    the gate tightens by itself. Persisting the reference would fix it — but
    only by writing to the clone outside a publish, which is what wedged the
    watcher for 11 hours on 2026-08-04. A quiet-box calibration at startup is
    the better fix if this ever matters.
    """
    rt = _BENCH_RT.setdefault(host, {"skips": 0, "probe_ref": None})
    t = min(speed_probe() for _ in range(BENCH_PROBE_SAMPLES))
    ref = min(rt["probe_ref"] or t, t)
    rt["probe_ref"] = ref
    return t / ref, t


def run_bench_idle(clone, host, st, sha, abort_check=None):
    """Idle work: tracked benchmark timings for the fully-tested sha — the
    clone's testmgr --bench, rows published to tstate/bench.tsv. Runs
    detached at `sha`, so the TSV is written to a temp file and appended
    after checking the branch back out (bench.tsv is tracked: mutating it
    under a detached HEAD would block the checkout back).

    Skips outright unless the box is quiet, and abandons the batch — DISCARDING
    its rows — if the quiet ends or a push preempts it. Both halves are the same
    rule: a measurement taken while the box was shared is void, and a void
    number is worse than no number, because it is indistinguishable from a
    regression. Bench is the one idle phase that used to be non-preemptible;
    at ~2-3 min it was also the largest term in time-to-verdict
    (feature-t-bench-idle-must-be-preemptible).

    Returns whether the caller should keep the loop HOT (`did_work`). True when
    a batch completed, and also when a push preempted it — the loop must go
    straight on to test that push, not sleep out the poll interval first. False
    when the box was too loaded, because `did_work` skips the sleep: returning
    True there would spin the cycle, re-fetching and re-deciding as fast as the
    CPU allows, which is itself load."""
    rt = _BENCH_RT.setdefault(host, {"skips": 0, "probe_ref": None})
    ratio, secs = box_speed(host)
    if ratio > BENCH_PROBE_TOL:
        rt["skips"] += 1
        if rt["skips"] >= BENCH_SKIP_RELAX_AFTER and rt["probe_ref"]:
            # Do not starve forever on an unreachable reference; a real quiet
            # moment still pulls it back down.
            rt["probe_ref"] *= BENCH_RELAX_FACTOR
        since = hours_since((st.get("last_bench") or {}).get("date"))
        print("twatch: bench SKIPPED at %s — box %.2fx slower than its best "
              "(%.0fms probe, limit %.2fx); %d consecutive skip(s)%s. A "
              "contended timing is VOID, not slow."
              % (sha[:12], ratio, secs * 1000, BENCH_PROBE_TOL, rt["skips"],
                 ", none for %.0fh" % since if since and since >= 24 else ""),
              flush=True)
        return False          # NOTHING written: a skip must leave no trace
    print("twatch: bench %s (box at %.2fx of best)" % (sha[:12], ratio),
          flush=True)
    set_phase(clone, host, "bench", sha=sha)
    clone.checkout(sha)
    tmp_tsv = os.path.join(tempfile.gettempdir(),
                           "twatch-bench-%d.tsv" % os.getpid())
    for stale in (tmp_tsv, tmp_tsv + ".clock"):
        if os.path.exists(stale):
            os.unlink(stale)
    env = dict(os.environ, TESTMGR_BENCH_TSV=tmp_tsv)
    proc = subprocess.Popen([sys.executable,
                             os.path.join(clone.path, "tools/testmgr.py"),
                             "--bench"], cwd=clone.path, env=env,
                            start_new_session=True)
    abandoned, preempted = None, False
    while proc.poll() is None:
        time.sleep(BENCH_POLL_SECS)
        # Sampled throughout, not just at the start: the load that spoiled the
        # 2026-08-04 batch ARRIVED mid-batch, which a start-only check would
        # have called a quiet box.
        during, _secs = box_speed(host)
        if during > BENCH_PROBE_TOL:
            abandoned = "box slowed to %.2fx of its best" % during
        elif abort_check and abort_check():
            abandoned, preempted = "new work preempts it", True
        if abandoned:
            kill_child(proc)
            break
    r = proc.returncode
    if abandoned:
        # VOID, not partial: the rows already collected are indistinguishable
        # from the contaminated ones, so none of them are written.
        rt["skips"] += 1
        print("twatch: bench ABANDONED at %s — %s; rows discarded (%d "
              "consecutive skip(s))" % (sha[:12], abandoned, rt["skips"]),
              flush=True)
        # the clock rows are as void as the timings they describe — drop both,
        # or an abandoned batch's clocks ride along with the next good one
        for void in (tmp_tsv, tmp_tsv + ".clock"):
            if os.path.exists(void):
                os.unlink(void)
        clone_head_back(clone)
        return preempted        # a push must be tested NOW, not after a sleep
    rt["skips"] = 0
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
    # The clock each row was taken at, joined on (date, host, workload, level).
    # A side file because bench.tsv is indexed positionally and cols 6/7 are
    # already uforth_sha/rss_kb — see BENCH_CLOCK_TSV_REL in testmgr.
    if os.path.exists(tmp_tsv + ".clock"):
        with open(tmp_tsv + ".clock") as f:
            cnew = [ln for ln in f if not ln.startswith("#")]
        if cnew:
            ctsv = os.path.join(clone.path, TSTATE_REL, "bench-clock.tsv")
            cfresh = not os.path.exists(ctsv) or not os.path.getsize(ctsv)
            with open(ctsv, "a") as f:
                if cfresh:
                    f.write("# date\thost\tworkload\tlevel"
                            "\tmhz\tmhz_lo\tmhz_hi\tbox_mhz\n")
                f.writelines(cnew)
        os.unlink(tmp_tsv + ".clock")
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
    # Provenance rides the same publish as the rows it describes — written
    # HERE, after the run survived, so an abandoned batch leaves the clone as
    # clean as it found it.
    record_host_epoch(clone, host)
    st["last_bench"] = {"sha": sha, "date": utcnow(), "rc": r,
                        "rows": rows, "conf_rows": conf_rows,
                        # what the box was doing while these numbers were taken:
                        # recorded, not merely gated on, so a series can be
                        # audited after the fact instead of only suspected
                        "probe_ratio": round(ratio, 3),
                        "hw_fp": (host_hardware_fp() or "")}
    save_state(clone, host, st)
    clone.publish("tstate(%s): bench %s %s (%d bench rows, %d conf)"
                  % (host, sha[:12],
                     "ok" if r == 0 else "RED", rows, conf_rows))
    return True


# A commit that only touches tickets/docs/tstate cannot change a test verdict,
# so it needs no gate run.  Without this filter the watcher full-tiers its own
# tstate commits forever: every publish moves the head it then retests
# (observed 2026-07-07: one ~300s full tier every ~5 min on an idle repo).
NOTEST_PREFIXES = ("devdocs/", "docs/")


def idle_phase(st, tested, mid_tier, deep_tier):
    """Which tier to run on an IDLE cycle for `tested`, or None if done.

    The escalation ladder, and the order is the point
    (task-t-pin-fast-track-t-owns-verification, deliverable 2):

        new commit -> fast_tier   native, seconds, so A+/B never wait
        idle       -> mid_tier    NATIVE DEPTH: all frontends + the real
                                  corpus, no qemu. Where the yield is, so it
                                  runs first and therefore most often.
        still idle -> deep_tier   PLATFORM BREADTH: + the qemu cross matrix,
                                  an order of magnitude slower, so it only
                                  happens if nothing has landed meanwhile.
        still idle -> opt         the O-level differential (handled by caller)

    SHIPPED DEFAULT: mid_tier == deep_tier == full, so the middle rung is
    collapsed and the ladder is native -> full (see CONF_DEFAULTS for the
    measurements). The three-rung shape stays here, parameterised, because it
    is right whenever the mid tier is genuinely cheaper than the deep one —
    which is a ratio to re-measure, not a property to assume. Setting
    `mid_tier` in twatch.conf brings it back.

    A push preempts whatever is running and the ladder restarts at the bottom
    for the new sha — which is the intent, not a cost: fresh commits outrank
    breadth on an old one.

    `last_full` carries the tier of the last REPLACING run, so no new state is
    needed to know how far up the ladder this sha has climbed. A mid-tier run
    cannot evict the deep tier's verdicts: eviction is by tier COVERAGE, and
    covered_tiers("limited") excludes the cross jobs.
    """
    lf = st.get("last_full") or {}
    if lf.get("sha") != tested:
        return mid_tier
    if mid_tier != deep_tier and lf.get("tier") != deep_tier:
        return deep_tier
    return None


# ------------------------------------------------------------ pin coverage ---
# A pin is FAST and UNVERIFIED **by design**: `make stabilize-fast && make pin`
# is ~34s and proves the self-host fixedpoint and little else, on the explicit
# trade that a bad pin is RECOVERED rather than prevented
# (task-t-pin-fast-track-t-owns-verification). Track A already did its half.
# The other half is T actually judging the pinned sha — and T was not:
#
#   18 of the last 25 pins never received a `full` run, and 13 were never
#   judged in ANY tier (measured 2026-08-11 across pin.log x runs-*.ndjson).
#
# That is not a bug in the escalation ladder; it is a gap the ladder cannot see.
# The ladder deepens HEAD, and the pin is whatever HEAD *happened to be* when a
# human ran `make pin`. By the time the box climbs to depth, HEAD has moved on
# and the pin is history. So the one artifact every OTHER track builds against
# (`$(PXX_STABLE)`, Tracks B/C/D/E) was the sha nobody was deepening — exactly
# backwards, and it quietly voided the recovery half of the fast-pin trade.
#
# Verifying the pin is therefore NOT the same work as testing HEAD, and it is
# scheduled ahead of idle depth on HEAD.
PIN_LOG_REL = "stable_linux_amd64/default/pin.log"


def pinned_ref(clone):
    """(version, git sha) of the CURRENT pin, or None.

    Read out of git (`origin/<branch>`) rather than off disk: this clone checks
    out arbitrary shas in order to test them, so the worktree's copy of pin.log
    is whatever the sha under test happened to carry, not what is pinned now.

    Two line shapes live in that file — older ones omit the binary sha256. The
    GIT sha is last in both, so key off position from the END, never a field
    index (same rule trackt.read_pin_log follows).
    """
    try:
        out = sh(["git", "show", "origin/%s:%s" % (clone.branch, PIN_LOG_REL)],
                 cwd=clone.path)
    except (RuntimeError, subprocess.SubprocessError, OSError):
        return None
    cur = None
    for ln in out.splitlines():
        w = ln.split()
        if len(w) >= 5 and w[1] == "pinned" and len(w[-1]) == 40:
            cur = (w[2], w[-1])
    return cur


def judged_tiers(clone, host, sha):
    """Tiers in which THIS host has already published a verdict for `sha`.

    Reads the uncapped run archive, not `st["history"]`, which is capped and
    would forget a pin older than the cap — the exact case that matters here,
    since a pin is usually days behind HEAD.
    """
    got = set()
    path = os.path.join(clone.path, TSTATE_REL, "runs-%s.ndjson" % host)
    try:
        with open(path) as f:
            for ln in f:
                ln = ln.strip()
                if not ln:
                    continue
                try:
                    r = json.loads(ln)
                except ValueError:
                    continue
                if r.get("sha") == sha and r.get("tier"):
                    got.add(r["tier"])
    except OSError:
        pass
    return got


def pin_verify_due(clone, host, st, tiers):
    """(ver, sha, tier) for the first of `tiers` the current pin still lacks.

    `tiers` is passed by the caller rather than fixed here because the two
    halves sit at different priorities: native DEPTH on the pin outranks idle
    depth on HEAD (it is what the other tracks are building on right now),
    while platform BREADTH on the pin is ordinary work and waits its turn.
    """
    cur = pinned_ref(clone)
    if not cur:
        return None
    ver, sha = cur
    have = judged_tiers(clone, host, sha)
    for tier in tiers:
        if tier in have:
            continue
        # A pin we cannot reach is not ours to judge: another box may have
        # pushed a pin newer than anything this clone has fetched, and a
        # checkout of an unknown sha would just fail the cycle.
        if not is_ancestor(clone.path, sha, clone.remote_head()):
            return None
        return (ver, sha, tier)
    return None


def verify_pin(clone, host, st, ver, sha, tier, abort_check=None):
    """Judge the PINNED sha out of band and record it for the pinstatus join.

    Deliberately does NOT go through test_sha(). That function maintains the
    HEAD progression — `st["last"]`, the per-job map `st["jobs"]`, and the
    open-regression ledger — all of which are defined relative to the sha
    sequence this host is walking. Feeding it a days-old pin would set "last
    tested" backwards, diff the pin's jobs against HEAD's map and manufacture
    NEW-RED/FIXED pairs out of nothing but the time travel, and open
    regressions whose commit range is meaningless.
    So this publishes exactly one thing — a run record — and touches no state
    that another phase reads.
    """
    print("twatch: verifying PIN %s (%s) at %s — the sha every other track "
          "builds on" % (ver, sha[:12], tier), flush=True)
    set_phase(clone, host, "pin-verify", sha=sha[:12], tier=tier, pin=ver)
    clone.checkout(sha)
    report, rc = run_gate(clone, tier, abort_check=abort_check)
    clone_head_back(clone)
    if rc == "aborted":
        print("twatch: pin verify preempted by a push — will resume", flush=True)
        return "aborted"
    if rc == "busy":
        # Distinguished from "no usable verdict" below purely so the log does
        # not read like the pin failed to verify. Nothing ran; it retries.
        print("twatch: pin verify skipped — the repo lock is held elsewhere",
              flush=True)
        return False
    if report is None or report.get("verdict") in ("INFRA", "INVALID") \
            or no_measurement(report):
        # Same rule as everywhere else: a box that could not measure publishes
        # NOTHING. An unjudged pin is a known unknown; a fabricated verdict on
        # the artifact every track builds against is far worse.
        print("twatch: pin verify produced no usable verdict — publishing "
              "nothing, the pin stays unjudged", flush=True)
        return False
    verdict = report["verdict"]
    reds = [j["name"] for j in report["jobs"]
            if j["status"] not in ("pass", "skip")]
    st = load_state(clone, host)
    st["pin_verify"] = {"ver": ver, "sha": sha, "tier": tier,
                        "verdict": verdict, "date": utcnow(),
                        "red": reds[:20]}
    save_state(clone, host, st)
    with open(os.path.join(clone.path, TSTATE_REL,
                           "runs-%s.ndjson" % host), "a") as f:
        f.write(json.dumps({"sha": sha, "date": utcnow(), "tier": tier,
                            "full": True, "verdict": verdict,
                            "wall": report["wall"], "new_red": [], "fixed": [],
                            "pin": ver}, sort_keys=True) + "\n")
    regen_index(clone)
    # A RED here is louder than an ordinary red, and says so: every track
    # building with $(PXX_STABLE) is on this binary right now, and `make revert`
    # plus `trackt pinstatus`'s last-fully-green line are how it gets undone.
    if verdict != "GREEN":
        print("twatch: *** PIN %s (%s) is %s at %s: %s — tracks are BUILDING "
              "on this. `tools/trackt.py pinstatus` for the last fully-green "
              "pin, `make revert` to demote."
              % (ver, sha[:12], verdict, tier, ", ".join(reds[:5]) or "?"),
              flush=True)
    clone.publish("tstate(%s): pin %s %s %s (%s)"
                  % (host, ver, sha[:12], verdict, tier))
    return True


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
# A SUBDIR, not the tstate root. Every reader treats `<tstate>/*.json` as a
# per-host state document — an implicit schema that was never written down, and
# putting a side file beside them took the daemon down with KeyError: 'host'
# on 2026-08-04. Side files go under meta/.
HOSTS_REL = TSTATE_REL + "/meta/hosts.json"
# Facts that DEFINE a measurement epoch. A change in any of them means earlier
# numbers are not comparable with later ones, so it opens a new epoch rather
# than silently continuing the old series.
_HW_CACHE = {}


def _first(path, needle=None):
    try:
        with open(path) as f:
            if needle is None:
                return f.read().strip()
            for ln in f:
                if ln.startswith(needle):
                    return ln.split(":", 1)[1].strip()
    except (OSError, IndexError):
        pass
    return ""


def host_hardware():
    """What this box IS, for benchmark provenance.

    A hostname is not a hardware identity: the same name survives a CPU swap, a
    RAM upgrade, a governor change or a kernel update, and the numbers silently
    stop being comparable. That is not hypothetical — the bench series moved
    from borg (i7-6700 @3.4GHz) to xeon (E5-2620 v2 @2.1GHz) on 2026-07-31 and
    got 40-90% slower on identical work, which reads as a 2x regression that
    never happened.

    Governor and turbo are identity, not trivia: on this Xeon that is the
    difference between 2.1 and 2.6 GHz — a governor flip alone moves numbers
    more than most optimisation work does. They are re-read every call for the
    same reason (they change at runtime); the rest is cached, since a CPU does
    not change under a running daemon.
    """
    if not _HW_CACHE:
        cores = _first("/proc/cpuinfo", "cpu cores")
        sockets = len({ln.split(":", 1)[1].strip()
                       for ln in open("/proc/cpuinfo", errors="replace")
                       if ln.startswith("physical id")}) or 1
        mhz_max = _first("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq")
        gcc = ""
        try:
            gcc = subprocess.run(["gcc", "-dumpfullversion"], capture_output=True,
                                 text=True, timeout=10).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            pass
        _HW_CACHE.update({
            "cpu": _first("/proc/cpuinfo", "model name"),
            "sockets": sockets,
            "cores": int(cores) * sockets if cores.isdigit() else None,
            "threads": os.cpu_count(),
            "mhz_max": int(mhz_max) // 1000 if mhz_max.isdigit() else None,
            "mem_total_kb": int((_first("/proc/meminfo", "MemTotal")
                                 or "0 kB").split()[0] or 0),
            "kernel": os.uname().release,
            "gcc": gcc,
        })
    hw = dict(_HW_CACHE)
    hw["governor"] = _first(
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
    no_turbo = _first("/sys/devices/system/cpu/intel_pstate/no_turbo")
    hw["turbo"] = (no_turbo != "1") if no_turbo else None
    return hw


# The hardware fields host_hardware() reports, and so the only keys a stored
# epoch may contribute to its fingerprint: an epoch also carries fp/from/to and
# rename bookkeeping, and hashing those would make the fp depend on when it was
# written rather than on what the box is.
HW_KEYS = ("cpu", "sockets", "cores", "threads", "mhz_max", "mem_total_kb",
           "kernel", "gcc", "governor", "turbo")


def fp_of_hardware(hw):
    """Fingerprint a hardware dict — live or read back out of an epoch.

    MemTotal is NOT stable across boots. The kernel reserves a slightly
    different amount each time, so /proc/meminfo drifts by a few kB (63424932
    -> 63424944 on this box across the 2026-08-05 rename reboot) and hashing it
    raw minted a spurious epoch for EVERY host on EVERY reboot — which reads as
    "new hardware, earlier rows are not comparable" and breaks the join the
    fingerprint exists to make. Quantise to GiB before hashing: the question is
    "is this the same machine", and a few kB of firmware reservation is not an
    answer to it. Rounded, not truncated, and at GiB rather than MiB, so boot
    drift cannot straddle the boundary — at MiB a 12 kB wobble still lands on a
    different bucket about 1% of reboots, which would resurrect this bug rarely
    enough to be baffling. Any real RAM change is >= 1 GiB and still lands.

    The raw kB stays in the stored epoch; only the hash input is normalised.
    """
    hw = {k: hw.get(k) for k in HW_KEYS}
    mem = hw.pop("mem_total_kb", None)
    hw["mem_total_gib"] = int(round(int(mem) / 1048576.0)) if mem else None
    return hashlib.sha256(
        json.dumps(hw, sort_keys=True).encode()).hexdigest()[:12]


def host_hardware_fp():
    """The current fingerprint, without touching the file — for stamping a run
    with the epoch it belongs to."""
    return fp_of_hardware(host_hardware())


def record_host_epoch(clone, host):
    """Append a hardware epoch for `host` when its fingerprint changes.

    A SIDE FILE rather than more columns in bench.tsv: `read_bench()` indexes
    columns positionally (6 = uforth_sha, 7 = rss_kb), so inserting one breaks
    the uforth rows, while a (host, date) lookup into the epochs needs no schema
    change at all. History is appended, never rewritten — the previous epoch
    gets a `to`, so a step in the series can be shown as "new hardware here"
    instead of being read as a regression.
    """
    hw = host_hardware()
    fp = host_hardware_fp()
    path = os.path.join(clone.path, HOSTS_REL)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path) as f:
            doc = json.load(f)
    except (OSError, ValueError):
        doc = {}
    epochs = doc.setdefault(host, [])
    if epochs and epochs[-1].get("fp") == fp:
        return False                       # unchanged: the common case
    now = utcnow()
    if epochs:
        epochs[-1]["to"] = now
        print("twatch: hardware fingerprint changed for %s (%s -> %s) — new "
              "bench epoch; earlier rows are not comparable with later ones"
              % (host, epochs[-1].get("fp"), fp), flush=True)
    epochs.append(dict(hw, fp=fp, **{"from": now}))
    doc[host] = epochs
    write_json_atomic(path, doc)
    return True


def head_detached(repo):
    """Is this checkout standing on a sha rather than a branch?

    True for most of the watcher's cycle — twatch checks out arbitrary shas to
    test them. Detaching is correct and deliberate; the defect is only ever in
    READERS that assume the tree reflects now.
    """
    try:
        return sh(["git", "symbolic-ref", "-q", "HEAD"], cwd=repo,
                  check=False).strip() == ""
    except (RuntimeError, OSError):
        return False


def materialize_tstate(repo, ref="origin/master", dst=None):
    """Extract the whole tstate tree out of a git REF into a directory.

    The one helper every "what is the state NOW" reader should share, instead of
    each rediscovering that a clone's worktree is a point-in-time snapshot:
    newer `tstate/reports/*.md` do not exist there yet, `<host>.json` shows the
    tested sha's verdicts rather than today's, and file mtimes are rewritten by
    every checkout. Four separate bugs in one day came from reading it, two of
    them in shipped tools, and the fourth reproduced the second a few hours
    after that one was fixed — knowing the rule was not enough
    (task-t-worktree-is-not-current-state).

    Unlike `states_at`, this brings the WHOLE subtree — reports/, bench.tsv,
    conformance.tsv — so the dashboard and any future reader can use it too.
    `git archive` in one shot rather than a `git show` per file.

    Returns the directory holding `<dst>/devdocs/progress/tstate/...`, or None
    when the ref has no tstate (fresh clone, no remote) so the caller can fall
    back to the worktree deliberately rather than by accident.
    """
    dst = dst or tempfile.mkdtemp(prefix="tstate-at.")
    try:
        with subprocess.Popen(["git", "archive", ref, TSTATE_REL], cwd=repo,
                              stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL) as ar:
            rc = subprocess.run(["tar", "-x", "-C", dst], stdin=ar.stdout,
                                stderr=subprocess.DEVNULL).returncode
            ar.stdout.close()
            ar.wait()
        if rc != 0 or not os.path.isdir(os.path.join(dst, TSTATE_REL)):
            return None
    except (OSError, subprocess.SubprocessError):
        return None
    return dst


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
            doc = json.loads(blob) if blob else None
            if doc and "host" in doc:   # side files are not host states
                out.append(doc)
        except (RuntimeError, OSError, ValueError):
            continue                   # a half-written or absent blob is not fatal
    return out


def retire_host(repo, old, into=None, tdir=None, renamed=False):
    """Retire host `old`, optionally moving its open regressions `into` another.

    A regression only clears when a later run ON THAT HOST passes the job. That
    is the right rule while a host is merely quiet — it may come back — but it
    becomes a trap when the host can never publish again, and the commonest
    reason for that is the most mundane event there is: somebody renamed the
    box. `xeon` became `plexus` on 2026-08-05 and its open
    `test-core#src:csocket_loopback_b88.c` turned into a phantom that no run
    could ever clear, sitting in every `--status` readout indefinitely.

    Renaming a box is not rare, so this is a general operation rather than a
    one-off edit of the JSON:

      --retire-host borg --into plexus   # T moved off borg: migrate entries
      --retire-host xeon --into plexus --renamed   # same box, new name
      --retire-host oldbox               # box is gone: close its entries out

    With `--into`, entries move to the new host and clear normally there — the
    signal is preserved, and if the job still fails on that box the next run
    re-reports it honestly. Without it, they are closed as unclearable. Either
    way the tombstone stays: the host's tested shas keep counting toward
    coverage, because those runs really did happen.

    `--renamed` is a SEPARATE, STRONGER claim and must not ride along with
    `--into`. Two different things move a job off a host: the box was renamed
    (`xeon` → `plexus`, one machine), or the work moved to a different box
    (`borg` kept existing as a dev station; Track T moved to plexus). Both want
    the entries migrated; only the first means `plexus` was ever called `borg`.
    Recording `renamed_from: borg` on plexus would be a plain falsehood in the
    permanent record — and this file IS the record — so the default is the
    weaker claim that `--into` actually supports (`migrated_from`), and the
    rename is opt-in.
    """
    tdir = tdir or os.path.join(repo, TSTATE_REL)
    op = os.path.join(tdir, old + ".json")
    if not os.path.exists(op):
        print("twatch: no such host state: %s" % op)
        return 1
    with open(op) as f:
        ost = json.load(f)
    if ost.get("retired_into") or ost.get("retired_at"):
        print("twatch: %s is already retired%s" %
              (old, " into %s" % ost["retired_into"]
               if ost.get("retired_into") else ""))
        return 0
    regs = ost.get("open_regressions") or []
    moved = 0
    if into:
        np_ = os.path.join(tdir, into + ".json")
        if not os.path.exists(np_):
            print("twatch: no such host state to migrate into: %s" % np_)
            return 1
        with open(np_) as f:
            nst = json.load(f)
        # Dedupe on the ledger's own identity (job selector + accused sha), so
        # retiring twice, or into a host that already saw the same regression,
        # cannot double-list it.
        have = {(r.get("job"), r.get("bad")) for r in nst.get("open_regressions", [])}
        for r in regs:
            if (r.get("job"), r.get("bad")) in have:
                continue
            r = dict(r, migrated_from=old, migrated_at=utcnow())
            nst.setdefault("open_regressions", []).append(r)
            moved += 1
        key = "renamed_from" if renamed else "migrated_from"
        nst[key] = sorted(set(nst.get(key) or []) | {old})
        with open(np_, "w") as f:
            json.dump(nst, f, indent=1, sort_keys=True)
            f.write("\n")
    ost["retired_at"] = utcnow()
    if into:
        ost["retired_into"] = into
        ost["retired_kind"] = "rename" if renamed else "migration"
    # Nothing here is actionable any more: the entries either moved or are
    # closed, and the job map can never be diffed against again.
    ost["open_regressions"] = []
    ost["jobs"] = {}
    with open(op, "w") as f:
        json.dump(ost, f, indent=1, sort_keys=True)
        f.write("\n")
    print("twatch: retired host %s%s — %d open regression(s) %s"
          % (old,
             " into %s (%s)" % (into, "rename" if renamed else "migration")
             if into else "", len(regs),
             "migrated (%d new)" % moved if into else "closed as unclearable"))
    print("twatch: commit %s (and %s) to publish the retirement."
          % (os.path.relpath(op, repo),
             os.path.relpath(os.path.join(tdir, into + ".json"), repo)
             if into else "TSTATE.md"))
    return 0


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
                        doc = json.load(f)
                    if "host" in doc:   # side files are not host states
                        hosts.append(doc)
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
    live, degraded = 0, 0
    for st in hosts:
        if st.get("retired_at"):
            # One line, no ledger, never QUIET: a retired host holds nothing,
            # so it must not appear among the hosts an agent could wait on.
            # Its tested shas still count toward coverage above — those runs
            # happened, whatever the box is called now.
            print("tstate: host %-12s RETIRED %s%s"
                  % (st["host"], st["retired_at"],
                     " → %s" % st["retired_into"]
                     if st.get("retired_into") else ""))
            continue
        last = st.get("last") or {}
        lf = st.get("last_full") or {}
        quiet = host_quiet_secs(st, now)
        inf = st.get("infra") or {}
        if not quiet:
            live += 1
            if inf:
                degraded += 1
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
        # Coverage, not just verdict. A host publishing GREEN with 33 skipped
        # jobs is not the same as one that ran them, and this line is the only
        # place that difference is visible without diffing two json files —
        # which matters most at cutover, when the fleet decides whose green to
        # trust. Silent while a host skips nothing.
        nskip = sum(1 for s in (st.get("jobs") or {}).values() if s == "skip")
        if nskip:
            print("tstate:   coverage — %d job(s) SKIPPED on %s (absent corpus "
                  "or unmet precondition): green here does not cover them"
                  % (nskip, st["host"]))
        if inf:
            # LOUD, and above the ledger dump: this host is running but cannot
            # produce a measurement, so it is publishing nothing. Saying only
            # "quiet" would understate it, and saying nothing is how a box that
            # could not build spent a day inventing reds nobody doubted.
            print("tstate:   DEGRADED — %s cannot run here since %s (%s; %d "
                  "cycle(s), last tried %s at %s): publishing no verdicts"
                  % (st["host"], inf.get("since", "?"), inf.get("reason", "?"),
                     int(inf.get("count") or 0), (inf.get("sha") or "")[:12],
                     inf.get("last", "?")))
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
    if live and degraded == live:
        # Every host that is supposed to be publishing is degraded. Coverage
        # WILL lapse; waiting for the grace window to notice would hand out an
        # UP in the meantime, and "T is up → offload the matrix" is precisely
        # the rule that must not fire here.
        print("tstate: DOWN — all %d live host(s) degraded (cannot build/run); "
              "run your own full gate" % live)
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
    ap.add_argument("--mid-tier", dest="mid_tier", default=None,
                    choices=["quick", "native", "limited", "full"],
                    help="idle backfill run BEFORE the full matrix: native "
                         "depth, all frontends, no qemu (default limited)")
    ap.add_argument("--host", default=socket.gethostname().split(".")[0])
    ap.add_argument("--interval", type=float, default=None, help="poll seconds")
    ap.add_argument("--debounce", type=float, default=None,
                    help="repo must be quiet this long before testing")
    ap.add_argument("--once", action="store_true",
                    help="single iteration (cron / smoke test); with --follow, "
                         "check once and exit instead of waiting")
    ap.add_argument("--no-bisect", action="store_true")
    ap.add_argument("--retire-host", metavar="HOST",
                    help="retire a host that will never publish again (a "
                         "renamed or decommissioned box), so its open "
                         "regressions stop being unclearable. Run in any "
                         "checkout, then commit the tstate change")
    ap.add_argument("--into", metavar="HOST",
                    help="--retire-host: migrate the open regressions to this "
                         "host, which then clears or re-reports them normally. "
                         "Omit to close them out as unclearable")
    ap.add_argument("--renamed", action="store_true",
                    help="--retire-host --into: the two names are the SAME box "
                         "(xeon → plexus), not work moving between boxes. "
                         "Records renamed_from instead of migrated_from")
    ap.add_argument("--fetch-corpus", action="store_true",
                    help="install any missing corpus trees at startup instead "
                         "of just warning (jobs whose corpus is absent SKIP, "
                         "and a skipped job is invisible in a GREEN verdict)")
    args = ap.parse_args()

    if args.status or args.follow is not None or args.retire_host:
        repo = os.path.abspath(os.path.expanduser(args.clone)) if args.clone \
            else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        if args.retire_host:
            if args.renamed and not args.into:
                sys.exit("twatch: --renamed needs --into (renamed into WHAT?)")
            return retire_host(repo, args.retire_host, args.into,
                               renamed=args.renamed)
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
    if getattr(args, "mid_tier", None) is None:
        # CONF_DEFAULTS, not a second literal: load_conf already merges the
        # defaults, so a hardcoded fallback here is a silent override waiting
        # to disagree with the table above.
        args.mid_tier = conf.get("mid_tier", CONF_DEFAULTS["mid_tier"])
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
            # a truncated file is corruption, not an edit to wait for: heal it
            # here too, or an OOM kill mid-publish parks the daemon forever
            clone.heal_truncations()
            rotate_log(clone.path)
            clone.publish_own_writes(host)
            dirty = clone.dirty()
            if dirty:
                # Say what we ARE, not what we last were. Without this the
                # phase stays at whatever ran last, so on 2026-08-12 a daemon
                # paused on a dirty clone reported `phase=testing` and
                # `trackt health` diagnosed "WEDGED: live.json has not moved in
                # 57605s" — pointing at a hang that was not happening, while
                # the actual cause (one uncommitted file) went unnamed for 16h.
                set_phase(clone, host, "paused-dirty",
                          files=[ln[3:].strip() for ln in
                                 dirty.splitlines()][:5])
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
            # Evaluated ONCE per cycle rather than inside the elif chain: each
            # call costs a `git show` plus a `merge-base`, and asking twice
            # could also act on a different pin than the one that satisfied the
            # condition. Requires `tested`: the abort-check below is defined
            # relative to it, and on a host that has tested nothing yet HEAD is
            # the more urgent work anyway.
            pin_mid = pin_deep = None
            if tested and not do_test:
                pin_mid = pin_verify_due(clone, host, st, (args.mid_tier,))
                pin_deep = pin_verify_due(clone, host, st, (args.tier,))
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
                    # "busy" leaves did_work False ON PURPOSE: did_work skips
                    # the poll sleep, so treating contention as work would spin
                    # the cycle and collide with the lock holder as fast as the
                    # CPU allows. The sha stays untested and is retried after a
                    # normal interval. Note it is NOT `is False` either — that
                    # branch escalates to the full tier, which is the worst
                    # possible answer to "something else is already running".
                    did_work = r != "busy"
            elif pin_mid:
                # AHEAD of idle depth on HEAD, and deliberately so: this is the
                # binary Tracks B/C/D/E are building with *right now*, whereas
                # HEAD is a sha nobody has adopted yet. Native depth only here —
                # platform breadth on the pin is ordinary work and waits below.
                verify_pin(clone, host, st, *pin_mid,
                           abort_check=make_preempted(clone, tested))
                did_work = True
            elif tested and fast and \
                    idle_phase(st, tested, args.mid_tier, args.tier):
                # idle: climb the ladder — native DEPTH first, platform
                # BREADTH only if the repo is still quiet after it. A new push
                # preempts either; the run is SIGINTed and discarded, no
                # verdict recorded, and the ladder restarts for the new sha.
                nxt = idle_phase(st, tested, args.mid_tier, args.tier)
                r = test_sha(clone, host, st, tested, nxt,
                             full=True, abort_check=make_preempted(clone, tested))
                did_work = r != "busy"      # see the note above: never spin
            elif pin_deep:
                # HEAD's ladder is exhausted: give the pin platform breadth too.
                # This is what lets `trackt pinstatus` name a last fully-green
                # pin to fall back to — pin_is_green() requires a `full` run,
                # and without one the recovery half of the fast-pin trade has
                # no target.
                #
                # UNREACHABLE under the shipped default, and that is correct
                # rather than dead: mid_tier == tier makes pin_mid and pin_deep
                # the same query, so the branch above already gave the pin its
                # full run — one verification instead of limited-then-full. It
                # comes back the moment a clone configures a distinct mid_tier,
                # which is why it stays.
                verify_pin(clone, host, st, *pin_deep,
                           abort_check=make_preempted(clone, tested))
                did_work = True
            elif tested and CONF.get("idle_slow") and \
                    (st.get("last_full") or {}).get("sha") == tested and \
                    (st.get("last_full") or {}).get("tier") == args.tier and \
                    (st.get("last_slow") or {}).get("sha") != tested:
                # idle, full matrix done: the shards DEMOTED out of the per-sha
                # tiers because they set the sweep's wall (testmgr.SLOW_SHARDS
                # — today just test-uforth#blocktest, 595s of an 821s full run).
                # Ranked ABOVE the opt sweep: this is mainline corpus coverage
                # that used to run on every sha, whereas opt is an extra oracle.
                # A push preempts it, which is the point — a fresh sha outranks
                # finishing an expensive sweep on an old one.
                r = test_sha(clone, host, st, tested, "slow", full=False,
                             abort_check=make_preempted(clone, tested))
                if r not in ("aborted", "busy"):
                    st = load_state(clone, host)
                    st["last_slow"] = {"sha": tested, "date": utcnow()}
                    if r is False:      # sha predates the tier: don't wedge
                        st["last_slow"]["note"] = "unsupported"
                    save_state(clone, host, st)
                    clone.publish("tstate(%s): slow %s %s"
                                  % (host, tested[:12],
                                     "done" if r else "unsupported"))
                did_work = True
            elif tested and CONF.get("idle_opt") and \
                    (st.get("last_full") or {}).get("sha") == tested and \
                    (st.get("last_full") or {}).get("tier") == args.tier and \
                    (st.get("last_opt") or {}).get("sha") != tested:
                # idle, full matrix done: O-level differential sweep (tier
                # opt — the silent-miscompile oracle). A push preempts it.
                r = test_sha(clone, host, st, tested, "opt", full=False,
                             abort_check=make_preempted(clone, tested))
                if r not in ("aborted", "busy"):
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
                # idle, opt done too: tracked benchmark timings per sha.
                # Preemptible like every other idle phase — it was the one that
                # was not, and at ~2-3 min the largest term in time-to-verdict.
                did_work = run_bench_idle(
                    clone, host, st, tested,
                    abort_check=make_preempted(clone, tested))
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
            _kill_orphan_gate()          # before anything else: it holds the lock
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
