---
track: T
prio: 55
type: chore
status: done
blocked-by: []
found: 2026-08-30
found-by: claude@plexus (Track T face 2), from frank-coordinator's three-failure report
summary: "tools/sync.sh failed three distinct ways in one night, all in the push/rebase path, all only once eight lanes were live: retry budget exhausted (6 -> raised to 12), two commits folded into one, and a commit dropped entirely while every signal said pushed. The immediate fixes landed. The class did not: nearly every conflict is BOARD*.md, a generated file, and a merge driver would remove the conflict rather than one more failure path."
---

# Push contention is a property of this fleet now, not an anomaly

## What happened, in one night

Three distinct failures of one tool, all in the push/rebase path, none of them
reproducible before eight lanes were pushing concurrently:

| # | symptom | fix |
| --- | --- | --- |
| 1 | `sync.sh` exhausted its 6 rebase-and-retry attempts and reported the push as failed | default raised 6 → 12 (`fe90725fc`) |
| 2 | two local commits folded into one | `f81498db8` |
| 3 | **a commit dropped entirely** — four `rebase(start)`/`rebase(finish)` pairs each landed on origin's tip without replaying the local commit; `rev-list --count origin/master..HEAD` said 0, exit 0, tree clean, and the work existed only in the reflog | `36687fe6d` — a manifest of commit subjects taken BEFORE the first rebase and confirmed on origin after the push |

Symptom 1 was mine, reported an hour before symptom 3 and treated as a knob. It
was the same contention.

## Why this is a chore and not three closed bugs

**Each fix closes one path; none reduces the number of rebases.** The retry loop
exists because pushes race. The rebases exist because the retry loop retries.
The losses happened *during rebases*. So the failure rate is a function of how
often we rebase, and every fix so far has made the rebase safer rather than
rarer.

**And nearly every one of those conflicts is a generated file.** `BOARD.md`,
`BOARD-brief.md` and `BOARD-done.md` are regenerated wholesale by
`tools/progress.sh board-md`; two lanes touching unrelated tickets still collide
in them, and the conflict is meaningless — the correct resolution is always
"regenerate". frankC proposed a **merge driver** for exactly this, and it removes
the conflict class rather than one more failure path.

## Proposed work

1. **A merge driver for `BOARD*.md`** (`.gitattributes` + a driver that runs
   `progress.sh board-md` and takes the result). This is the item with the
   leverage: it should remove the large majority of rebase conflicts, and with
   them most of the rebases that the losses happen during.
2. **Measure before and after.** Count conflicts per push over a day, by file,
   so the claim in (1) is a measurement rather than a plausible story. If
   `BOARD*` is not actually the majority, the driver is the wrong fix and we
   should know that before writing it.
3. **Consider not committing the boards at all**, or committing them from one
   place. A generated artifact in git that every lane rewrites is the root; a
   merge driver is a very good treatment of a self-inflicted wound.

## A fourth shape, from the same night, that no tool fix covers

Not `sync.sh`, and worth recording next to it because it is the same *family*:

**`git add a b c` where one path does not exist aborts the ENTIRE add with a
fatal — and the `git commit` that follows still succeeds, on whatever was staged
before, and prints a success line.** A step failed, the next step succeeded on a
subset, and the aggregate reported success. It cost three commits tonight: one
that landed as a bare rename with none of its content, one that landed with only
a ticket move, and one recovered by `reset --soft`. Nothing was lost — the
working tree still held everything — but each looked complete.

Same shape as symptom 3 and as the size canary's own rule: **failing to do the
thing is not the same as failing loudly, and an aggregate that reports success
after a failed step is the dangerous case.** The habit that avoids it is
`git add -A <dir>` or `git add -u` plus explicit new files, never a hand-written
list that may contain a path a previous step already consumed.

Recorded here rather than in CLAUDE.md because CLAUDE.md is the owner's.

## Not started

Filed rather than begun: `tools/sync.sh` has had three patches from the
coordinator in the last two hours, and a second agent editing it concurrently is
the collision this whole ticket is about. Whoever takes it should confirm the
file is quiet first.

---

## RESOLVED 2026-08-30 — the rebase-frequency half

The merge-driver half (proposed work 1) was taken by frank-coordinator. This is
the other half, and it is the one the ticket's own argument pointed at: *"every
fix so far has made the rebase safer rather than rarer."* Two causes found, both
measured, both in `tools/sync.sh`.

### 1. sync.sh spent 18-21 seconds of every retry widening the window it was racing in

`rebase_onto_origin()` ended with an unconditional `tools/progress.sh board-md`,
and `push_with_retry()` calls `rebase_onto_origin` on every failed push. Measured
on plexus:

| | |
| --- | --- |
| `tools/progress.sh board-md` | **21.16 / 17.92 / 17.99 s** |
| ...of which `write_board_md` | ~2.5 s |
| ...of which `write_board_html` | **~87%** — 82 of 94 profiled seconds, `md_html` (3.3k calls) → `inline` (310k calls) → **1.88M uncompiled `re.sub` calls**, 21.7 s of it inside `re._compile`'s cache lookup |
| a no-op `tools/sync.sh` | 27.3 s |
| a ticket-tree fingerprint | **0.028 s** |

`BOARD.html` **is gitignored** (`.gitignore:86`) and `BOARD_GLOB` is
`devdocs/progress/BOARD*.md`, so sync.sh could never stage it. It paid 87% of the
command for a file it is structurally incapable of using, inside the one window
where every second raises the odds of the next race — and the retries are what
that race causes. The loop fed itself.

Two changes:

- **`progress.sh board-md --no-html`** (`tools/progress.py`) — additive; the bare
  command is unchanged for humans, who are the only ones who read the HTML.
  Drops board-md to **4.9 s**.
- **Skip the regeneration entirely when no ticket moved.** The boards are a pure
  function of the ticket files (nothing in the board writers reads git; the
  `git log` call at `progress.py:1298` is the `check --strict` citation audit).
  So fingerprint the ticket tree with `git ls-tree`, cache it, and regenerate
  only on a change.

  The fingerprint covers **everything** under `devdocs/progress` except the
  generated boards and `tstate/`. That single exclusion is what gives the skip
  its value: `tstate` is not in `progress.py`'s `STATUSES`, so the watcher's
  publishes cannot change a board — and the watcher is the busiest writer on the
  tree, i.e. the retries fire during exactly the churn the skip now ignores.
  **1165 of the 4497 blobs under `devdocs/progress` are tstate.** The bias is
  deliberate and stated in the code: over-covering costs a needless regeneration,
  under-covering commits a stale board.

  *Near miss worth recording:* the first cut wrote the exclusion as
  `grep -v -e '\tdevdocs/progress/tstate/'`. `\t` is not a tab in a BRE — GNU
  grep reads it as `t`, the pattern matches nothing, and the filter silently
  excludes nothing. Green, correct output, no error, and the entire benefit gone.
  Caught by counting what the filter dropped instead of trusting that it ran.

### 2. the backoff was deterministic, and its comment said it was not

```sh
# Brief, growing pause. Without it every racing writer retries in
# lockstep and they keep colliding; ...
sleep "$tries"
```

An identical delay in every process is precisely the thing that cannot break
lockstep. Two writers colliding at t=0 both sleep 1 s, both retry at t≈1, and
stay in phase for the whole budget — which is what "exhausted twice in a row on
one resolve, then landed first try immediately after" looks like from outside.

Now `sleep "$(jittered_backoff "$tries")"`, uniform over `[tries/2, 3*tries/2)`
from `/dev/urandom`. **The mean is unchanged at `tries`**, so this buys
decorrelation without spending patience, and the raise 6→12 stands on its own.

The shape is worth naming, because it is the reason this survived review at
sight: **a mechanism whose comment states the property its implementation
lacks.** Nothing about `sleep "$tries"` looks wrong next to that comment; you
have to test the property rather than the presence of the pause. So the devtest
asserts the 200 draws *differ* — a guard the old line fails (1 distinct value)
and that "there is a sleep here" would have passed.

### Guard

`tools/sync_contention_devtest.py` — 24 guards, 0 FAIL. Both halves proven to
discriminate against the code they replaced: guard 1 against `sleep "$tries"`,
guard 7 against a dropped `--no-html`. The fingerprint is tested in **both**
directions in a scratch repo — it must not move for a tstate publish or a board
rewrite (or the skip is worthless) and it must move for a ticket edit, a new
status dir, a ticket merely *named* `BOARD-*`, and a deletion (or the skip is
unsafe). Either direction alone is a green that means nothing.

### What is NOT done, deliberately

- **Proposed work 2 (count conflicts per push over a day, by file).** Not run.
  The two causes above were found by measuring the *tool*, not the fleet, and
  they are true independently of how the conflicts distribute. The distribution
  measurement still has value — it is what would tell us whether the merge driver
  earned its keep — and it needs a day of fleet traffic, not a session.
- **Proposed work 3 (stop committing the boards at all).** A real design fork
  with a human in it: `check` reports `STALE-BOARD` against the committed files,
  and every lane's workflow ends in `board-md` + commit. Not mine to pick.
- **The 87% itself.** `inline()` calls `re.sub` with pattern literals in a hot
  loop — ~1.9M cache lookups. Hoisting the six patterns to module-level
  `re.compile` was **measured, not estimated**: 18.66 s → 12.99 s, `BOARD.html`
  byte-identical. A 30% cut, and worth having — but note cProfile put that same
  line at 21.7 s, ~4x the 5.7 s it is really worth, so the profile alone would
  have put a wrong number in this ticket. The other ~13 s is the rest of a 26 MB
  render. Not landed here: `tools/progress.py` is every lane's tool on every
  ticket move, not a contention fix, so it is filed as
  `chore-t-board-html-render-is-13s-of-every-ticket-move` with the patch and the
  numbers.

  *(The measurement itself nearly went wrong the same way everything else here
  did: the first run of the patched copy lived outside the repo, printed
  `no .../devdocs/progress`, exited, and the `cmp` that followed compared the
  baseline against an untouched file and said **byte-identical**. A skipped step
  and a passing check.)*

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
