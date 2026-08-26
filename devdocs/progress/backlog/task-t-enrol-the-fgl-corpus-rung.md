---
track: T
prio: 70
type: task
blocked-by: []
summary: "Enrol the new `test-fgl` corpus target in a testmgr tier and add `fpc-rtl` to twatch's CORPUS_EXPECTED. The rung is wired and green (3 pass / 4 skip) but nothing in the matrix runs it, and the watcher will not warn when the tree is unfetched."
status: backlog
owner: —
---

# Enrol the fgl corpus rung in the tiers and the watcher

- **Type:** task (test infrastructure)
- **Track:** T — the files below are Track T's, so the rung's author filed this
  rather than editing them.
- **Filed:** 2026-08-25 by the Track P/B worker that landed
  [[feature-pascal-corpus-fgl]].

## What exists now

`make test-fgl` → `tools/run_fgl_corpus.sh ./compiler/pascal26
library_candidates/fpc-rtl/rtl/objpas`. Compiles real FPC 3.2.2 `fgl.pp` and
diffs seven drivers' stdout against FPC-generated `.expected` files. Honours
`test/fgl/pxx.skip`. Prints `test-fgl: SKIP …` / `PASS` / `FAIL` at line start,
so testmgr's `_self_skipped()` marker convention is already satisfied, and the
recipe spells out `library_candidates/fpc-rtl` so `CORPUS_RE` can see it.

Runtime: ~3 pxx compiles of a ~2,000-line unit plus three tiny runs — seconds,
not minutes. `classify()` will class it `corpus` on the `library_candidates`
token, which is the right cost class.

## Asks

1. **`tools/testmgr.py`** — add `"test-fgl"` to `TIERS`. Suggested `limited` and
   `full`, next to `test-lua` / `test-cjson` / `test-zlib`: it is cheap, it is
   native-only, and it is the only thing in the matrix that compiles real
   third-party Object Pascal. Not `quick` — that is the inner loop.
2. **`tools/twatch.py`** — add `"fpc-rtl"` to `CORPUS_EXPECTED` so a watcher
   clone missing the tree warns instead of publishing a silent green.
3. **`tools/twatch-setup.sh`** — add `fpc-rtl` to the provisioning
   `for t in lua sqlite zlib c-testsuite tcc cjson tiny-regex-c; do` list.

## Why it matters

This rung's entire history is the failure mode being guarded against: the fgl
check lived in `test-core` guarded on `/usr/share/fpcsrc`, a path absent from
every box here, so it printed `SKIP (no fpcsrc)` and passed for its whole life
while asserting nothing. Wiring the rung without enrolling it would leave it in
the same state one level up — green because nobody runs it.

## 4. `test-fpjson` too — and this one is not hypothetical

`make test-fpjson` (fcl-json's own 203-case fpcunit suite under a pxx-built
runner) is likewise **in no tier**, same self-skip shape. It was landed green at
203/203 and then never run again. Re-running it by hand on 2026-08-25 at dev
HEAD `20c989a5e` — the first time since it landed — found it **red**: the
program no longer compiles at all
([[bug-a-the-fpjson-suite-overflows-the-fixed-4096-entry-data-ptr-fixup-table]]).
The corpus is pinned, so the regression is ours.

That is the concrete cost of the enrolment gap, measured rather than argued:
**the rung that was not enrolled is the rung that rotted**, and it rotted
silently for however long. Worth bumping this ticket's priority accordingly.

## Links
Rung: [[feature-pascal-corpus-fgl]] · umbrella
[[feature-pascal-corpus-expansion]]

## Raised 60 -> 70 (coordinator, 2026-08-25)

Not for the wiring, which is small, but for what the wiring prevents. Two
findings today are the same failure: **an unenrolled check asserts nothing while
reporting success.** The fgl rung was guarded on `/usr/share/fpcsrc/3.2.2`, which
is absent from this box, the watcher box and every fresh clone, so `test-core`
printed `SKIP (no fpcsrc)` and PASSED without running once. fpjson was in no
tier, so it rotted from 203/203 to not-compiling for an unknown period, silently.

That is the same class as a torn-down Track T run publishing an empty
`still_red` and having unreached jobs read as FIXED: a hole in coverage that
presents itself as coverage. Cheap to fix, and the cost of leaving it is
measured in how long a regression can hide rather than in developer minutes.
