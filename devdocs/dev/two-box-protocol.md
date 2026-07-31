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
