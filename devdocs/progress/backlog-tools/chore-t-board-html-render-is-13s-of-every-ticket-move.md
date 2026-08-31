---
track: T
prio: 40
type: chore
status: backlog_new
blocked-by: []
found: 2026-08-30
found-by: claude@plexus (Track T face 2), while measuring sync.sh's push window
summary: "tools/progress.sh board-md takes 18.7s, of which ~87% is BOARD.html — a 26MB render every lane pays on every ticket move. Hoisting six re.sub pattern literals out of the inline() hot loop is measured at 18.66s -> 12.99s with byte-identical output. Not landed: progress.py is shared tooling, not Track T's."
---

# `board-md` costs 18.7 s, and ~87% of it is a gitignored 26 MB file

## Measured on plexus, 2026-08-30

| | |
| --- | --- |
| `tools/progress.sh board-md` | **18.66 s** (also 21.16 / 17.92 / 17.99 across runs) |
| ...`write_board_md` (the committed files) | ~2.5 s |
| ...`write_board_html` (`BOARD.html`) | the remaining **~87%** |
| `BOARD.html` size | **26 MB** |
| `BOARD.html` in git? | **no** — `.gitignore:86` |

Every lane runs `board-md` after every ticket move, so this is a cost the whole
fleet pays continuously for a file only a human ever opens.

## The one measured fix

`inline()` (`tools/progress.py:1124`) calls `re.sub` with six pattern **literals**
per line of markdown — 310k calls, ~1.9M `re` cache lookups. Hoisting them to
module-level `re.compile`:

```
18.66 s  ->  12.99 s      BOARD.html byte-identical (cmp)
```

Patch kept at `scratchpad/progress_fast.py` at the time of filing; it is six
`_RX_*` constants and six call-site edits, nothing else.

**Do not trust the profile's number here.** cProfile attributed **21.7 s** to
`re._compile`, ~4x the 5.7 s the change is actually worth, because per-call
profiling overhead lands hardest on exactly this shape — millions of tiny calls.
The number above came from wall clock on the real tree with the output diffed.

## What the other 13 s is

Not established. It is the rest of a 26 MB render, and the obvious questions in
order of expected value:

1. **Does anything need all of it?** `BOARD-done.md` exists because `done/` alone
   was 190 KB of BOARD.md; `BOARD.html` never got that treatment and still
   renders every finished ticket. Splitting or paginating it is likely worth more
   than any micro-optimisation.
2. String building — whether the renderer accumulates with `+=` on large strings.
3. Whether the HTML is worth generating eagerly at all, versus on request.

## Why this is filed and not done

`tools/progress.py` is shared tooling — every lane's `next`/`ready`/`claim`/
`resolve`/`board-md` path. Track T owns testmgr/twatch/tstate and the fuzzers,
not the board tool. The additive `board-md --no-html` flag that
`chore-t-push-contention-is-a-fleet-property-not-an-anomaly` needed was the
minimum a contention fix required; a performance rewrite of the renderer is a
different change to a different lane's file and wants its owner.

Related: `chore-t-push-contention-is-a-fleet-property-not-an-anomaly` (why this
was measured at all — `sync.sh` was paying the full 18 s inside its fetch→push
race window, on every retry).
