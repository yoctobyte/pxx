---
track: A
prio: 82
type: bug
blocked-by: []
summary: "`make test-fpjson` — the fcl-json 203-case suite, a rung recorded as green 203/203 — no longer compiles: `error: data ptr fixup overflow` from elfwriter.inc, i.e. the program needs more than `MAX_DATAPTRFIX = 4096` data→data pointer relocations. A fixed-size table, a real program that exceeds it, and nothing in any testmgr tier that would have caught it."
status: backlog
owner: —
---

# The fpjson suite overflows the fixed 4096-entry data-ptr fixup table

- **Type:** bug (core — ELF writer capacity limit)
- **Track:** A (`compiler/defs.inc`, `compiler/elfwriter.inc`)
- **Found:** 2026-08-25, verifying the Pascal corpus ladder's rungs while
  landing [[feature-pascal-corpus-fgl]].

## Measured

Compiler: dev HEAD `20c989a5e`, both the pinned stable
(`stable_linux_amd64/default/pinned`, VERSION 374) and a freshly self-hosted
`compiler/pascal26` at that sha. Corpus: `library_candidates/fcl-json` at the
pinned FPC commit `0d122c49…` — **the corpus has not moved**, so whatever
changed is on our side.

Running the `test-fpjson` recipe by hand (the `make test*` hook blocks the
target):

```
compile exit=1
pascal26:2: error: data ptr fixup overflow
  in: .../stable_linux_amd64/default/builtin/builtinheap.pas
```

(The `in:` file is wrong — that is a separate, already-filed diagnostic bug,
[[bug-p-a-diagnostic-in-a-used-unit-names-the-wrong-source-file]].)

The error is raised at `compiler/elfwriter.inc:106`:

```pascal
if DataPtrFixCount >= MAX_DATAPTRFIX then Error('data ptr fixup overflow');
```

against `compiler/defs.inc:229`:

```pascal
MAX_DATAPTRFIX  = 4096;  { data->data 8-byte pointer relocations (RTTI blobs) }
```

So this is a **fixed-size table**, and a real program has outgrown it. fpjson +
fpcunit is class-dense (203 registered test cases across a deep fixture
hierarchy), which is exactly the shape that mints RTTI blobs.

## Not diagnosed here, deliberately

I did not bisect when it started, did not measure how far over 4096 the count
runs, and did not change the constant — the constant and the writer are Track A
files and the sizing question is a real one (bump it, grow it dynamically, or
stop emitting the relocations that are avoidable). Recording what is measured
and leaving the design call to whoever owns the file, per
`devdocs/dev/root-cause-over-microfix.md`: raising 4096 to some other fixed
number is the microfix, and a real program will find the new number too.

## Why nobody noticed

`make test-fpjson` is in **no testmgr tier** — absent from every list in
`TIERS`. It was landed green (`feature-pascal-corpus-fpjson`, 203/203) and then
nothing ever ran it again. Its sibling `make test-fgl` had the same problem in a
different shape. Both are covered by [[task-t-enrol-the-fgl-corpus-rung]], which
should now be read as urgent rather than tidy-up: **the rung that was not
enrolled is the rung that rotted.**

## Repro

```sh
tools/install_lib_candidates.sh fcl-json
# then the test-fpjson recipe body from the Makefile, or:
make test-fpjson        # needs PXX_ALLOW_FULL_SUITE=1 past the hook
```

## Gate
`make compiler/pascal26` (self-host fixedpoint) + the fpjson suite reaching
`run: 203  failures: 0  errors: 0` + `tools/gate.sh quick`.

## Links
Rung: [[feature-pascal-corpus-fpjson]] (done, now red) · ladder
[[feature-pascal-corpus-expansion]] · enrolment
[[task-t-enrol-the-fgl-corpus-rung]]

## Raised 60 -> 82 (coordinator, 2026-08-25)

A real library we **cannot compile at all**, and it is a regression: fpjson
landed green at 203/203 and nothing ran it again until today, because it sits in
no testmgr tier. The corpus is pinned, so the change is ours. That is the
project's stated priority order almost verbatim -- "we are not seeking utopia,
we are seeking a pragmatic tool", real-world targets over edge cases -- and a
pinned real program going from 203/203 to not-building is as real-world as the
board gets.

Ranked below the 88s (segfaults, and the text-`read` chain) and just under the
NilPy 9s constant at 80, which pays out across the whole matrix rather than one
corpus.

Endorsing the reporter's judgement call explicitly so nobody "fixes" it the
cheap way: **do not just bump MAX_DATAPTRFIX.** A fixed 4096-entry table that a
class-dense real program outgrows will be outgrown again by the next one, and a
larger constant only moves the cliff. See `devdocs/dev/root-cause-over-microfix.md`.
