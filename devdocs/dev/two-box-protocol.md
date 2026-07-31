# Two boxes, one repo — how the borg and xeon agents self-organise

Written 2026-07-31, the day xeon became sole watcher coverage, two agents first
ran concurrently on separate machines, and the ssh link was made symmetric. Read with
[`parallel-tracks.md`](parallel-tracks.md) (which lane owns which file) and
[`track-t.md`](track-t.md) (what the watcher is). This doc is only about the
*fleet*: two boxes, two agent sessions, one origin.

## Topology — peer to peer, one shared truth

```
   borg  ◀──ssh──▶  xeon         symmetric since 2026-07-31
     │                │          borg 192.168.1.99 · xeon 192.168.1.191
     └───── origin ───┘          the SHARED TRUTH. state lives here, only here.
```

Two peers, one project, one repo. Neither is the master. The user may be
sitting at **either** box — borg is a workstation, xeon has a tmux session; an
instruction can arrive on either one, and whichever agent receives it acts on
it.

The two channels are **not interchangeable**, and keeping them distinct is what
stops the boxes fighting:

| | origin (git) | ssh |
|---|---|---|
| carries | **state**: claims, tickets, tstate, code, decisions | **notification only**: "look at X", "I'm taking Y" |
| ordered | yes — commits serialize | no |
| durable | yes — survives restarts, visible to the user | no, ephemeral |
| use for | anything another agent must *act* on later | cutting latency on something already in the repo |

**State goes through git. Always.** ssh may tell a peer to look sooner; it must
never *be* the record. If it is not pushed, it did not happen — that rule does
not relax just because the boxes can now talk directly.

## Operating model — what each box is FOR

Set by the user 2026-07-31:

- **borg = the dev box.** Holds **1-3 tracks** concurrently; the user decides how
  many, and the binding constraint is token budget, not file safety. The user
  also **guards the lane split** (A+ vs B+) when several run at once — agents do
  not self-assign overlapping lanes.
- **xeon = Track T.** Its job is to *find regressions*, continuously, across the
  matrix. Future: **pin when stable** — promoting a blessed binary automatically
  once a sha proves itself (criteria unsettled, see
  [[decide-track-t-autopin-criteria]]).

**The point of the split is speed: dev does not wait for the gate.** Push on a
fast local confirm and let Track T's report come back tagged to your sha. A red
arrives as an asynchronous callback minutes later; that is accepted, and it is
cheaper than every agent serialising on a 10-minute matrix.

### Do not RUN native on the dev box — let the watcher be your native run

Testing was eating ~80% of the dev loop. The fix is not less testing, it is
**moving native off the critical path** — the fleet already does this and
nobody was using it.

The watcher's `fast_tier` is `native`, triggered on every push
(`interval: 60`, `debounce: 20`, ~100s on xeon). So:

| | blocking cost on the dev box |
|---|---|
| old: run native locally, then push | **150-220 s** |
| new: `--tier quick --fail-fast`, push | **~15 s** (measured) |

Native still runs — on xeon, ~3 minutes after your push, while you are already
on the next thing. You did not skip it, you stopped *waiting* for it. That is
roughly a **10x cut in blocking time per iteration**, with the same coverage.

```
tools/testmgr.py --tier quick --fail-fast    # ~15s: catches the obvious
git push                                     # the watcher's native IS your gate
# keep working; the verdict arrives tagged to your sha
```

Green quick ⇒ **call the edit a success, push, move on.** Do not wait for the
matrix, do not wait for cross-targets, do not wait for a peer, and now: do not
wait for native either.

### …but the fixedpoint guarantee moved, it did not vanish

`quick` does **not** carry the self-host fixedpoint
(`SELFHOST_GATE_TIERS = native/limited/full`). Pushing on quick therefore means
master may briefly carry a broken fixedpoint until the watcher says so ~3
minutes later. Accepted — *fix forward* — with one hard consequence:

> **Rigor moves from before-push to before-PIN.** Landing is cheap and
> reversible; pinning moves the ground every other track builds on. A pin must
> never rest on an unverified sha, no matter how relaxed the landing bar gets.

This is exactly why [[decide-track-t-autopin-criteria]] matters more under this
model, not less. Run native locally only when you have reason to distrust the
change (a bootstrap/ABI/codegen edit you expect to bite), or when the watcher is
down (`twatch --status`).

This is safe by construction, not by optimism: native already carries the
self-host fixedpoint gate —

```python
SELFHOST_GATE_TIERS = ("native", "limited", "full")   # testmgr.py
# NOT advisory — byte-identical self-host is the gate the stable binary rests on.
```

— so the one property that is genuinely not offloadable (a broken fixedpoint
poisons the next `pin` for *every* track) is already inside the bar. `quick` is
the inner loop and does **not** carry it; that is the difference between the two
tiers and the reason the push bar is native, not quick.

Non-compiler changes (docs, tickets, libs built against `$(PXX_STABLE)`) do not
need even that.

### Fast-forward, fix later — including on the same target

Green native does **not** mean nothing will break. Track T may later file
regressions for other targets *and for the target you just tested* — native is a
subset of native-plus-breadth, and the matrix reruns things your run never
touched.

That is the deal, not a defect: **a later red becomes a ticket, never a reason
to have waited.** Land, move to the next thing, and treat incoming reds as new
work items ranked against everything else in the queue. The alternative —
serialising every significant change behind a 10-minute matrix, across several
agents — costs far more than the occasional fix-forward.

Two things this does *not* license: skipping native, and pushing a state you
already know is broken or mid-refactor.

### Callbacks arrive tagged to a sha that may already be stale

You will be moving while the matrix runs, so a red comes back pointing at a
commit that is no longer HEAD. Before acting on any callback: **re-check it at
current HEAD.** It may already be fixed, or moved. Report every verdict with the
sha of the binary it came from (`gating-and-waiting.md` — a leak was once
measured against a mid-bisect binary and read as "still broken" when HEAD was
already flat).

### Concurrency costs tokens, not correctness

File-lanes make parallel tracks *safe*; the usage cap makes them *expensive*.
`autonomy.md` records the measured position: **two concurrent sessions trip the
cap even under light load**, and one worker cycling lanes gets more done per
5-hour block than three concurrent lane-workers. That is a real tension with
running 1-3 tracks on borg, and the user owns the trade: concurrency buys
wall-clock latency and costs block lifetime. Spend it knowingly — for scheduled
and unattended work the default stays **one worker cycling lanes**.

## The anti-recursion rule (the thing to actually worry about)

Two peers that can each poke the other can ping-pong forever. One rule prevents
it, and it costs nothing:

> **An agent may send a direct message triggered by human input, or by its own
> work reaching a result. NEVER as a reaction to receiving one.**

Receiving a message may cause you to *do work*, pull, read the repo, change what
you are doing — but it may not, by itself, cause you to send a message back. So
every chain is at most one hop, and every chain traces to a human or to real
work completing. There is no cycle to enter.

Corollaries:
- No acknowledgements. If the peer needs to know you acted, the *commit* tells
  them.
- No "are you there?" polling over ssh. Liveness is `tstate` and the daemon's
  own heartbeat.
- A message is a hint with no reply channel. Treat it as advisory; the repo is
  the authority.

## Self-organising: who takes what, decided by the boxes

There is no dispatcher. Both agents run the same loop, and the **push is the
arbiter**:

```
git pull --rebase
progress.sh next            # highest effective-prio ready ticket
progress.sh claim <slug> claude@<box>
progress.sh board-md
git commit && git push      # ← wins or loses HERE
```

If the push lands, the ticket is yours. If it rejects because the peer claimed
the same slug first, **rebase, drop it, and run `next` again** — do not fight
for it. Optimistic concurrency, one authority, no negotiation protocol needed.

Two standing biases keep them out of each other's way without anyone deciding:

- **xeon is Track T** — it *is* the watcher; the matrix, fuzzing and the test
  tooling live there.
- **borg leads the dev lanes** — it holds the `gh` credentials and it is where
  the interactive work usually happens.

These are defaults, not fences. Either box may take any ticket its capabilities
allow; the claim is what matters. Capabilities that genuinely differ:

| | xeon | borg |
|---|---|---|
| toolchain | kernel 7.0, gcc 15.2 | kernel 6.17, gcc 13.3 |
| capacity | 12 threads, 60GB — the matrix, long parallel work | 8 threads, 15GB, shared with the user's own use |
| speed | ~40-90% slower per core (serial work suffers) | faster per core |
| GitHub API | deploy key (push only) | full `gh` (issues, PRs, keys) |

A ticket needing the GitHub API belongs on borg. A ticket needing hours of
parallel compute belongs on xeon. Everything else: whoever claims first.

**Use the toolchain gap on purpose.** It is not noise to be normalised away —
on day one it found two real bugs that borg called green:
[[bug-elf-missing-pt-gnu-stack]] (kernel 7.0 refuses our `.so`, 6.17 tolerates
it) and the `test-zlib` oracle break (gcc 14+ makes implicit function
declarations an error). So:

- **a green on one box is not a green on both.** Say which box a result came
  from, always.
- xeon red + borg green ⇒ suspect *portability*, not regression. File it,
  don't skip it.
- borg is the box that answers "did this EVER work?" — it is the older
  toolchain and the historical baseline.

## Terse dispatch — "proceed on bugs track A+*"

The user may drop a one-liner on **any box, any checkout**, and expects both
agents to sort it out. Read it as `<verb> on <type> track <lanes>`:

| form | means |
|---|---|
| `track A` | only Track A |
| `track A+C` | A and C, both in scope |
| `track A+*` | **A first**, then anything else once A's queue is dry |
| `track *` | any lane, global top |
| `on bugs` | restrict to `type: bug` / `regression` tickets |
| (no type) | any type |

`progress.sh next` takes **one** `--track` and has no type filter, so expand it
yourself — do not wait for tooling:

```sh
for T in A C P B N; do tools/progress.sh next --track $T; done
# each prints "effective prio N" — take the highest; ties break toward the
# named-first lane (the A in A+*), then toward urgent/.
```

Then the normal loop: `claim` → **push the claim** → work → your lane's gate →
`resolve` → `board-md` → push.

**The sole-A guard is now checkable, not a guess.** Before taking a Track A
ticket — or a Track P edit touching the shared `lexer.inc`/`parser.inc` — look
at what the peer holds:

```sh
git fetch -q origin master
for f in $(git ls-tree -r --name-only origin/master devdocs/progress/working); do
  t=$(git show "origin/master:$f" | sed -n 's/^track: *//p' | head -1)
  o=$(git show "origin/master:$f" | sed -n 's/^owner: *//p' | head -1)
  [ "$t" = "A" ] && echo "A HELD by ${o:-?}: $(basename "$f" .md)"
done
```

Clear ⇒ claim it. Someone holds A ⇒ take the next lane in the expression
instead. That is what `A+*` is *for*: a fallback order, so a blocked lane never
idles you.

**"Two boxes" is shorthand — do not assume exactly two agents.** Owner ids in
`working/` today include identities beyond `claude@borg` / `claude@xeon` (e.g.
`fable-a-n`), and more than one agent can run per box. The check above asks
*"does anyone hold this lane?"*, never *"does the other box hold it?"* — the
`owner:` field is the answer, whoever it names.

## Lazy sync — pull at decision points, not continuously

Synchronise only where a stale view would cause wrong work:

1. **before `next`** — so you pick against the peer's current claims
2. **before `push`** — `git pull --rebase`
3. **when a peer notification arrives** — that is what it is for

Nothing else. No polling loop, no watching the peer's branch. Between those
points, work from your snapshot: it is allowed to be stale, because the claim
you pushed is what protects you.

Push rejected ⇒ rebase, regenerate `BOARD.md` (see above), and **re-check the
claim is still yours**. If the peer won it, drop it without argument and run
`next` again.

## Using the cores — split tiers across boxes, never duplicate

Two boxes, ~20 threads. The waste mode is both of them compiling the same thing.

**Never start a run blind:**

```sh
tools/testmgr.py --status      # live run in this repo, or anywhere on this box?
```

**Split by tier, not by duplication.** Breadth belongs to the watcher box; the
interactive box stays in the inner loop:

| | interactive box | watcher box |
|---|---|---|
| tier | `--tier quick --fail-fast` (seconds) + self-host fixedpoint | `native` / `full` / `opt` — the matrix |
| why | you need a verdict now | it already runs breadth for everyone |

**Do not run `--tier full` on a box whose daemon is already running the
matrix**, and never on both boxes at once — it is duplicate work that also
starves the daemon. Confirm native yourself, push, and let the watcher's report
come back tagged to your sha (`gating-and-waiting.md`).

**Leave the daemon its cores.** On the watcher box an agent's own run must cap
itself (`--jobs N`) rather than compete adaptively — the daemon's scheduler
packs by measured RSS/cores and cannot see your run. On a box where the *user*
is working, cap to roughly half the threads so the machine stays usable.
`--deadline` bounds anything you cannot babysit.

**Send heavy work to the box with free cores.** Checking a peer's load over ssh
is read-only and needs no coordination:

```sh
ssh <peer> 'uptime; tools/testmgr.py --status'
```

If a long parallel job would contend locally and the peer is idle, that is what
the peer is for — but run it in a *scratch clone or `/tmp`*, never inside a live
`~/trackt-watch`.

## The claim is the lock. Push it before you work.

`tools/progress.sh claim <slug> <agent-id>` sets `Owner` and moves the ticket
to `working/`. That is already a distributed mutex — it just only works if the
*other* box can see it, which means **pushed**.

```
progress.sh claim <slug> claude@xeon
progress.sh board-md
git commit && git push          # <-- BEFORE you start editing code
```

**This is not ceremony.** On 2026-07-31 two agents independently wrote the
*same* fix for the same parser bug (`e09febaf6` landed; the duplicate was
discarded unpushed) — a self-host build each, wasted. Neither had pushed a
claim. A tstate RED is visible to every agent at once, so an unclaimed
regression reliably attracts duplicate work.

Agent ids encode the **box**, because the box is the scarce coordination fact:
`claude@borg`, `claude@xeon`. The track lives in the ticket, not the id.

Before deciding what to work on: `git pull --rebase` first, every time.
`working/` on origin is the truth about what is taken.

## Write scopes — stay inside them

- **`devdocs/progress/tstate/**` belongs to the watcher host.** Only xeon
  writes it now. borg must never commit tstate. (borg's daemon was stopped
  2026-07-31; if it is ever re-enabled it publishes under its own `borg.json`,
  never xeon's.)
- **`tools/testmgr.py`, `tools/twatch*`, `tools/fuzz.sh`, `tools/pasmith*`** —
  Track T. Whoever holds T edits them; today that is xeon.
- Everything else: normal lane rules from `parallel-tracks.md`.
- **Push only your own commits.** Never push, rebase, or "helpfully"
  fast-forward the other box's in-flight work.

## BOARD.md always conflicts. Don't merge it — regenerate it.

`devdocs/progress/BOARD.md` is generated, so two boxes touching tickets
conflict on it constantly (three times in one afternoon). The resolution is
mechanical, never a manual merge:

```
git checkout --ours devdocs/progress/BOARD.md   # either side; content is discarded
tools/progress.sh board-md                      # regenerate from the tickets
git add devdocs/progress/BOARD.md
git rebase --continue
```

## Escalation: the human may be at either box

Neither agent should assume it has the user. An instruction can arrive on
borg's terminal or in xeon's tmux; the user moves between them.

So escalation is **posted, not sent**: when an agent hits a fork it cannot
settle from the code, the request, or a sane default, it files a Track U
`decide-<topic>` ticket (fork, options, trade-offs, recommendation) and **moves
on to the next queue item**. It does not block and does not guess.

Whichever agent currently has a human in front of it is responsible for
surfacing open `decide-*`. Both should treat "any new `decide-*`?" as routine
monitoring. A decision the user gives verbally on one box must be **written
back into the ticket**, or the other box never learns it — this is the most
likely way for the two to drift apart.

## Direct messaging between peers

Each box can `ssh` the other and inject a prompt into the peer's Claude session:

```
# from borg                      # from xeon
ssh neo@xeon \                   ssh rene@borg.home \
  'tmux send-keys -t claude-T "…" Enter'   'tmux send-keys -t <session> "…" Enter'
```

This **interrupts** the peer mid-task. Governed by the anti-recursion rule
above: send on human input or a completed result, never in reply. Keep it to
things where latency actually matters — a claim collision about to waste a
build, a red the peer should see now. The default remains: commit, push, let
the peer pull.

Read-only probing over ssh (inspecting logs, reproducing a build in `/tmp`) is
fine and needs no coordination — but **never run jobs inside the peer's
`~/trackt-watch` while its daemon is live**: it checks out shas underneath you
and your run races its working tree. Copy what you need to `/tmp` and work there.

## The short version

- two peers, no master; the user may be at either box
- **state through git, notifications through ssh** — never the reverse
- claim by pushing; if the push loses, drop it and pick again
- never send a message *because* you received one — that is the whole
  anti-recursion rule
- say which box a result came from; disagreement between boxes is a finding
- a verbal decision must be written back into its ticket, or the peer never sees it
