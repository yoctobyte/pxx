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

- **borg = the dev box.** Development is **one broadly linear stream**, not a
  set of concurrent lanes ([[decide-two-track-model-dev-and-regression-testing]]
  — this supersedes an earlier "1-3 concurrent tracks" reading recorded here).
  Where genuine concurrency is wanted the user calls it, and the binding
  constraint is token budget rather than file safety.
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

For reference, the tier split that makes this work:

```python
SELFHOST_GATE_TIERS = ("native", "limited", "full")   # testmgr.py
# NOT advisory — byte-identical self-host is the gate the stable binary rests on.
```

`quick` is the inner loop and does not carry the fixedpoint; `native` does. So
the guarantee is **deferred to the watcher's native run**, not skipped — which
is the whole trade, and why the watcher going down changes the rules (below).

Non-compiler changes (docs, tickets, libs built against `$(PXX_STABLE)`) carry
no such concern at all.

### Fast-forward, fix later — including on the same target

Green quick does **not** mean nothing will break — nor does the watcher's
native that follows it. Track T may later file regressions for other targets
*and for the target you just tested*: native is a subset of
native-plus-breadth, and the matrix reruns things your run never touched.

That is the deal, not a defect: **a later red becomes a ticket, never a reason
to have waited.** Land, move to the next thing, and treat incoming reds as new
work items ranked against everything else in the queue. The alternative —
serialising every significant change behind a 10-minute matrix, across several
agents — costs far more than the occasional fix-forward.

Two things this does *not* license: skipping the quick tier, and pushing a
state you already know is broken or mid-refactor.

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
5-hour block than three concurrent lane-workers. This reinforces the linear-development
model above rather than competing with it: the cap makes concurrency expensive
exactly where the two-track decision already says it buys little. Where the user
does call for genuine concurrency, spend it knowingly — for scheduled and
unattended work the default stays **one worker cycling lanes**.

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

## Terse dispatch — one stream, not concurrent lanes

**Superseded 2026-07-31 by [[decide-two-track-model-dev-and-regression-testing]].**
An earlier draft of this section defined an `A+C` / `A+*` lane grammar. The user
struck it: *"A+ waters down"* — the expressions imply development is several
concurrent lanes when in practice it is **one broadly linear stream** (one IR,
one self-host gate, one history). Do not dispatch the letters as if they were
concurrency lanes.

Operationally there are **two** things, and the axis is **what parallelizes**,
not who owns which file:

| | development | Track T |
|---|---|---|
| shape | linear — one IR, one gate, one history | 1617 jobs × 6 targets, embarrassingly parallel |
| scales by | not easily parallelized | cores, straightforwardly |
| box | borg | xeon |

So read a terse instruction as **a filter on the queue, not a set of parallel
lanes**. "proceed on bugs, track A" means: work the highest-effective-prio bug
whose gate is A, one at a time.

```sh
tools/progress.sh next --track A      # or omit --track for the global top
tools/progress.sh claim <slug> claude@<box>
tools/progress.sh board-md
tools/sync.sh                         # push the claim BEFORE editing code
```

The frontend letters stay useful as **labels** — which gate must be green, what
context to hold, who owns a ticket. C/P/N/Z/R sharing Track A is *by design*:
frontends lower to a shared IR, and lexer/parser work usually reaches the IR
layer anyway. **Track A is the single mutex; everything else works around it.**

**The sole-A guard is now checkable, not a guess.** Before taking a Track A
ticket — or a Track P edit touching the shared `lexer.inc` — look
at what the peer holds:

```sh
git fetch -q origin master
for f in $(git ls-tree -r --name-only origin/master devdocs/progress/working); do
  t=$(git show "origin/master:$f" | sed -n 's/^track: *//p' | head -1)
  o=$(git show "origin/master:$f" | sed -n 's/^owner: *//p' | head -1)
  [ "$t" = "A" ] && echo "A HELD by ${o:-?}: $(basename "$f" .md)"
done
```

Clear ⇒ claim it. Someone holds A ⇒ **do not queue behind it** — take the next
ready ticket whose gate is not A (`progress.sh next` with no `--track`), so a
held mutex never idles you. Track A is the single mutex; everything else works
around it.

Corollary the peer got right and worth repeating: **never infer lane ownership
from filesystem state** (which checkouts exist, what is in a working tree).
`working/` on origin is the only answer, which is what the query above asks.

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

## Landing: use `tools/sync.sh`, not `git pull --rebase`

`devdocs/progress/BOARD.md` is **generated**, so any two agents that both
touched tickets conflict on it every single time (four times in one afternoon).
Merging the two halves by hand produces a board matching neither box; the only
correct resolution is discard-both-and-regenerate.

```sh
tools/sync.sh              # pull --rebase, auto-resolve BOARD.md, push
tools/sync.sh --no-push    # just get current
```

It **only** auto-resolves `BOARD.md`. Any other conflict is real content: it
stops, names the files, and leaves the rebase in place for a human. It also
refuses to run on a dirty tree.

It additionally avoids a quieter failure: a background `git fetch` in the same
repo races a foreground `git pull` and corrupts `FETCH_HEAD`, producing
`fatal: Cannot rebase onto multiple branches`. `sync.sh` always fetches with an
explicit refspec and `--no-write-fetch-head`, and never relies on `FETCH_HEAD`.
**Any long-lived tooling that polls this repo must use `--no-write-fetch-head`
for the same reason.**

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

### …and that applies to your OWN box's watcher clone

The rule above is written as a courtesy to the peer. It is not — it is a
property of **any live watcher clone, including the local one**:

> a checkout with a live watcher daemon is infra and cannot also be a
> workspace, because it detaches HEAD underneath you.

So **every box running a watcher needs a second, ordinary checkout for agent
work.** On 2026-07-31 xeon had only `~/trackt-watch`, the agent used it as a
workspace, and three separate failures followed from that one cause: `git pull
--rebase` refusing while the daemon was mid-publish, a commit stranded on a
detached HEAD (rescued by cherry-pick onto a re-attached `master`), and a push
rejected by the daemon's own tstate push. None of it was the daemon
misbehaving — `twatch` refuses a dirty checkout precisely because it detaches,
which is it protecting you.

Current layout, the same shape on both boxes: agent works in a dev checkout
(`~/pxx` on xeon), the watcher owns `~/trackt-watch` alone, origin is the only
shared state.

**This is not an argument for one checkout per box** (user, 2026-07-31):
borg's several checkouts are deliberate — that split is per TRACK, and the
resulting untidiness is normal development, not drift to be cleaned up. The
rule here is narrower: a clone with a *live daemon in it* is not a workspace.

## The short version

- two peers, no master; the user may be at either box
- **state through git, notifications through ssh** — never the reverse
- claim by pushing; if the push loses, drop it and pick again
- never send a message *because* you received one — that is the whole
  anti-recursion rule
- say which box a result came from; disagreement between boxes is a finding
- a verbal decision must be written back into its ticket, or the peer never sees it
