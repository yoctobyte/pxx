# Two boxes, one repo — how the borg and xeon agents stay out of each other's way

Written 2026-07-31, the day xeon became sole watcher coverage and two agents
first ran concurrently on separate machines. Read with
[`parallel-tracks.md`](parallel-tracks.md) (which lane owns which file) and
[`track-t.md`](track-t.md) (what the watcher is). This doc is only about the
*fleet*: two boxes, two agent sessions, one origin.

## Topology, and the asymmetry that shapes everything

```
   borg  ──ssh──▶  xeon          borg can drive xeon.
   borg  ◀──────   xeon          xeon CANNOT reach borg. Deliberate:
     │               │           the user lives on borg.
     └──── origin ───┘           the ONLY symmetric channel.
```

Consequences, and they are not symmetric — do not pretend otherwise:

- **origin is the bus.** Anything xeon wants borg to know must be *committed
  and pushed*. A finding that exists only in xeon's session transcript does not
  exist.
- **borg is the only box that can push work to the other.** It has ssh and the
  `gh` credentials (GitHub API: deploy keys, issues, PRs). xeon has a
  repo-scoped deploy key and nothing else.
- **the user is reachable only from borg.** xeon has no path to a human. Its
  escalation route is a Track U `decide-*` ticket, which the borg agent is
  expected to surface. If xeon blocks silently, nobody finds out.

## Who does what — split by capability, not by letter

The track letters still decide file ownership. The *box* split is about what
each machine can physically do:

| | xeon | borg |
|---|---|---|
| role | **Track T** — it IS the watcher | dev lanes (A/P/C/B/N/…) |
| toolchain | kernel 7.0, gcc 15.2 | kernel 6.17, gcc 13.3 |
| strengths | 12 threads, 60GB, runs the matrix; newer toolchain finds portability bugs | interactive, user present, `gh` creds, can drive xeon |
| weakness | ~40-90% slower per core; no human | contends with the user's own work |

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

## Escalation: xeon → user runs through the repo and through borg

xeon cannot ask the user anything. When it hits a fork it cannot settle:

1. xeon files a Track U `decide-<topic>` ticket — fork, options, trade-offs,
   its recommendation — and **moves on to the next queue item**. It does not
   block and does not guess.
2. borg's agent surfaces open `decide-*` tickets to the user.
3. The user decides; the answer lands as a ticket edit; xeon picks it up on its
   next pull.

The borg agent should treat "are there new `decide-*` tickets?" as part of
routine monitoring, not something to be asked for.

## Direct drive: borg → xeon

borg can `ssh neo@xeon` and can send a prompt into the running Claude session
(`tmux send-keys -t claude-T`). This is a **loud** channel — it interrupts
whatever that session is mid-way through. Use it for things the repo cannot
carry in time, not as the default. The default is: commit, push, let the other
side pull.

Read-only probing over ssh (inspecting logs, reproducing a build in `/tmp`) is
fine and needs no coordination — but **never run jobs inside `~/trackt-watch`
while the daemon is live**: it checks out shas underneath you, and your run
races its working tree. Copy what you need to `/tmp` and work there.

## The short version

- origin is the only thing both boxes share — if it is not pushed, it did not happen
- claim, push the claim, *then* work
- say which box a result came from
- disagreement between the boxes is a finding, not noise
- xeon escalates by filing `decide-*`; borg is the one who tells the human
