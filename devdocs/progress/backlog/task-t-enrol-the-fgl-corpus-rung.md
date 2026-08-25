---
track: T
prio: 50
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

## Also worth considering (T's call, not a request)

`make test-fpjson` (fcl-json's own 203-case fpcunit suite under a pxx-built
runner) is likewise **in no tier**. It is the other real Pascal library rung and
has the same self-skip shape.

## Links
Rung: [[feature-pascal-corpus-fgl]] · umbrella
[[feature-pascal-corpus-expansion]]
