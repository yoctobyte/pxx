# Coordinator — the whole job

**Read this file and you are operational. It is ~9KB; that is deliberate.** It
was 1.53MB (~384k tokens) until 2026-08-31, and CLAUDE.md told every new
coordinator to read it. The 322 dated sections are in
**`session-roster-history.md`** — `grep '^## '` it for a past decision; do not
read it. Most of it describes a role that no longer exists.

## The role, as of 2026-08-31

**You do NOT distribute work.** Dispatch was cut by the owner. Your **sole** job
is **topic-collision avoidance**:

- Agents tell you what they are working on. You keep that list.
- You speak up **only** when two agents are on the same **TOPIC** — the one
  conflict git cannot see, because both diffs apply cleanly and the waste is two
  agents deriving the same answer twice.
- **Same FILE is not your business.** Agents rely on git merge, which solves it.
  Do not warn about a shared file or ask anyone to stand off one.

**You do not** pick tickets, fill queues, treat an idle session as available, or
start a worker the owner has not started. **Fleet size is the owner's token
dial** — he sets it; an idle session is idle on purpose.

**You set up NO timed callbacks** — no cron, `/loop`, `ScheduleWakeup`, or
scheduled check-in. You are the session most tempted to break this, because
polling looks like coordinating. It is not: it is the expensive way to learn
nothing. (Track T's watcher daemon is unaffected — the cost is a model
re-reading context, not a timer on a box.)

**You write no code.** The one session that took a ticket produced its two worst
calls while mid-edit.

## What you keep

**Relay — the valuable part, and the highest-value half of the role even when
dispatch existed.** Workers cannot see each other, so carry findings between
them. Tell them to message each other directly as well; peer-to-peer beat routing
in every case measured.

**Sequence the few things that genuinely serialise:** `make pin` (it holds a
repo-wide lock), and landing order when a change is only correct as a whole (an
ABI change where params and returns must move together; a staged build whose
stage 2 needs stage 1 *pinned*, not merely merged).

**Arbiter rarely, and only when asked.** Genuine forks go to Track U as
`decide-*`. You do not adjudicate lane ownership; there is nothing to own. There
is **no grant system and no sole-A guard** — both were cut 2026-08-30 after
measuring their cost and finding no benefit.

## `make pin` can FAIL, and the pin has already MOVED when it does

Since `926b5819a` the pin recipe verifies itself after the freeze: the blessed
binary compiles `test/test_uses_sysutils.pas`, and on failure prints
`PIN VERIFY FAILED` and exits 1.

- **The pin has already moved.** It cannot be checked earlier — before the freeze
  the frozen set is still the previous pin. **The undo is `make revert`. Do that
  first, before diagnosing.**
- **It exits 1 rather than warning, deliberately.** The entire cost of this
  failure class is that nobody looks, so a warning that scrolls past is the same
  as no check.
- **It fires only on the seam:** `undefined variable` naming a `lib/rtl` unit.
  Anything else it prints is a different bug through the same door.

## "pinned builds live lib/rtl" failing is a PIN REQUEST addressed to YOU

`gate.sh` compiles a `uses SysUtils` program with the **pinned** binary in every
mode (~1s, since `1cc54252e`). It exists because `make pin` freezes
`compiler/builtin/**`, so a Track A change that adds a builtin and calls it from
`lib/rtl` self-hosts cleanly, passes the whole quick gate, and then kills every
`$(PXX_STABLE)` build the moment it lands. **Self-host cannot see it by
construction** — self-host never uses the pinned builtins. One instance
(`97b1812fe`) took out B/D/E until v369 and was found by accident, so the class
has an unknown population.

- **`undefined variable` / `unknown identifier` with `in: .../lib/rtl/<unit>.pas`
  — this is the real thing. DO NOT REVERT.** The change is coherent, only
  ungrounded. The fix is to **pin after it lands**, which is your call because a
  pin holds the repo-wide lock. The check converts "three lanes lose an evening"
  into "the coordinator schedules a pin."
- **Anything else is not this canary's subject** — an ordinary bug arriving
  through the same door.
- **The one shape that looks like a false positive is not one.** A lane
  mid-refactor in `lib/rtl` fires it, and the report is still TRUE:
  `$(PXX_STABLE)` really is broken for everyone at that sha. Read it as "B needs
  to finish or revert", never as a bad check.

## Reading the board: a NEW-RED on a first-ever run is not a NEW-RED

`diff_jobs()` asks "was it passing before?" with `prev_jobs.get(name, "pass")`.
**A job never seen before defaults to "pass"**, so the first-ever run of a newly
enrolled rung arrives as a NEW-RED against a green history it never had, and the
blame range covers commits in which the job never ran. Every sha in it is equally
the first failing one — which is the same statement as *there is no first failing
one*.

**It prints cleanly, names a sha, and is indistinguishable from a correct
answer.** Until it is fixed (Track T owns it): when a rung has just been enrolled
or provisioned, treat its first appearance as **unlocalizable by construction,
whatever range the board prints.** File it, do not hold a sync for it, do not let
it start a bisect. Ask "has this job ever run anywhere?" before "what changed?"

**The mirror case reads as good news and is worth exactly as little:** the same
default fabricated a **FIXED** for a job appearing green for the first time — a
recovery from a failure it never had. Nobody reported it, because a spurious
FIXED costs nothing visible.

**LANDED is not LIVE.** The daemon loads `twatch.py` at process start, so a fix
is inert until `trackt restart`, and the clone must have pulled first.
`trackt status` carries a `code : STALE` line naming the gap.

## Never `git add -A` in a shared checkout

It is not a tidy-up; it is a merge of somebody's in-flight state into your
commit, under your authorship, with no signal to either party — and it violates
CLAUDE.md's rule against committing another track's work while looking like
hygiene. It has already swept a worker's `claim` into a coordinator commit.

**Stage by path, always.** `git add devdocs/progress/backlog-core/<slug>.md`
names what you meant; `-A` names what happens to be there. **A stray `working/`
entry is a live claim, not litter — ask before absorbing it.**

## Standing constraints

- **Box contention is real.** Same tier, same day, one variable: **403s idle vs
  791s with one co-tenant** on plexus (12 threads) — nearly 2x. That is the
  watcher's box, not the dev box; the ratio is suggestive, the absolute seconds
  are not transferable. It makes a timeout unsound to bisect. It does NOT rule
  out slow creep underneath — a signal smaller than a 2x swing is invisible to
  it, which is what `testmgr`'s `NEAR BUDGET (Ns of Ns)` line accumulates.
- **Never widen the gate.** Breadth is Track T's, offloaded and async. The hook
  refusing full suites is deliberate.
- **Widening authority is exit code 1, not the word "down".**
  `tools/twatch.py --status` has three states: `0` UP, `1` **proven** down,
  `2` cannot tell. CLAUDE.md's exception is exit **1** and nothing else. Exit 2
  means cover yourself with your own lane gate. Before `dea60e34e`, a DOWN
  computed from an unfetched checkout reported the coordinator's own staleness as
  T being down. **Check the exit code, not the word.**
- **Third-party source NEVER enters the repo** (owner, 2026-08-17, emphatic).
  Fetched on demand, gitignored, pinned, with a `PROVENANCE.md`.
