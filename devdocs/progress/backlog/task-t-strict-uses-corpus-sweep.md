---
track: T
prio: 80
type: task
blocked-by: []
summary: "Compile-only sweep of test/** with --strict-uses, classified against three known failure shapes. It is the last input bug-pascal-uses-is-transitive needs before the flag becomes the default, and it is a full-corpus run — Track T's kind of job, not a dev-loop one."
---

# Sweep `test/**` under `--strict-uses` and classify the failures

Track A built the enforcement ([[bug-pascal-uses-is-transitive]]) and measured it
over `examples/**`: **55 programs, 41 compile today, and all 41 compile
IDENTICALLY with `--strict-uses` on.** The remaining unknown is the `test/`
corpus — 923 `.pas` plus the `.npy` suite — and that is a full-corpus run, which
is why it is filed here rather than run in a dev loop.

## What to run

For each file in `test/**` (`.pas`, `.npy`, and the C corpus if cheap), compile
**twice** and compare only the pass/fail verdict:

```
pxx <file> /tmp/out                 # baseline
pxx --strict-uses <file> /tmp/out   # enforced
```

Nothing is executed and no expectation is checked. A file that already fails the
baseline is not a finding — 113 of the 934 are helper `*_unit.pas` files and
`{%FAIL}` cases that never compiled standalone. **The finding is the set that
compiles clean today and fails only with the flag.**

## How to classify each new failure

Three shapes account for every one Track A hit, and each has a different owner:

1. **A compiler-INJECTED unit that is not marked ambient.** The compiler injects
   `builtin`/`builtinheap`, `pylib`/`pyeval` (every `.npy`), and conditionally
   `textfile`/`math`/`promocore`/`softfloat`/`pxxcio`/`palpthread`. Tell:
   the missing name is a runtime helper the source never mentions —
   `pyfloormod_i`, `pystr_of`. Fix is one call site in the compiler
   (`ParseUsesUnitAmbient`).
2. **Two filters that fail to compose.** Tell: *"no overload of X matches these
   arguments"* with an **EMPTY candidate list**, rather than an undefined
   identifier. An out-of-scope candidate was still suppressing an in-scope one.
   Fix is in the compiler.
3. **A genuine missing `uses`.** Tell: the unit really does call another unit's
   routine without naming it. Fix is one clause in the library — or, as often,
   naming the RIGHT unit (pylib's `FloatToStr` came from `builtin`, not the
   `sysutils` it was accidentally reaching).

Report the count per shape, and for shape 3 the (importer, provider, name)
triples. That list is the actual remaining work, and it is expected to be
short.

## Do NOT size this with `--warn-uses-leak`

The warn pass is noise-dominated: it fires on **speculative** lookups
(`FindUClass`/`FindProc` called to ask "is this identifier a class?", answered
yes, answer discarded), so its top rows are things like
`platform -> pylib [class] TPyDict` at 2948 hits in a unit that never mentions
`TPyDict`. Two earlier sizings of the parent ticket were wrong for exactly this
reason. `--strict-uses` changes resolution, so it errors only where a name
really binds — count failures, not warnings.

## Why it is worth the run

`--strict-uses` becomes the default when this comes back short, which deletes
the whole class of bug behind `decide-class-namespace-scoping`, the tkinter /
reportlab `Canvas` collision, and every future "two libraries export the same
name". The parent ticket is parked on this result.
