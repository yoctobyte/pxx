---
track: P
prio: 60
type: perf
blocked-by: []
summary: "Measured at 13e196cc8 on the real -O2 compiler: ParseFactorCore is 9.4% of the whole run — the largest single named function — because 41,032 calls issue 1,583,871 CaseEqual, i.e. 38.6 string compares per factor, walking a linear `else if CaseEqual(name, '...')` chain of 92 arms spread over ~7,180 lines."
---

# `ParseFactorCore` walks a 92-arm name chain for every factor

Filed by the Track A session on
`perf-a-every-npy-compile-still-rebuilds-the-whole-nilpy-runtime`, which found
it while profiling the NilPy fixed cost. **Not touched** — `pasparser_expr.inc`
is Track P's file and A does not edit it.

## The measurement

Sampling profile of the real `-O2` compiler (`compiler/pascal26` self-hosted at
`13e196cc8`, `-O2 -g` so the profile is of the shipping configuration and not
the `-O0` that a bare `-g` silently selects) compiling a **zero-byte `.npy`** —
i.e. this is the cost of parsing `pylib.pas` + `pyeval.pas`, ordinary Pascal:

```
9.44%  ParseFactorCore     <- the largest named function in the compiler
4.96%  IRLowerAST
2.69%  UNameMatch
2.23%  ParseStatementAST
```

FPC `-pg` call counts (which are ours, where gprof's percentages are FPC's):

```
41,032 calls to ParseFactorCore
1,583,871 CaseEqual calls attributed to its frame   = 38.6 per factor
```

`compiler/pasparser_expr.inc:312` — the procedure runs to ~7,180 lines and
contains **92** `CaseEqual` sites, walked linearly. Every factor in every
program pays the full walk on a miss, and a miss is the common case: most
factors are ordinary identifiers, not `Length`/`Copy`/`Supports`/`round`/...

## Why it is the same bug as one already fixed next door

`bug-a-every-nilpy-compile-pays-a-fixed-nine-second-cost` found exactly this
shape in the text assembler and fixed it four times over: `AsmTextJccCode`
answering "no" by walking all 28 arms, `AsmRegNum` running its whole table on a
miss, `CaseEqual` scanning to the end of the string instead of bailing at the
first differing character. Same structure, same reason it is invisible — the
throughput curve stays perfectly linear, so nothing looks pathological.

## Shape of the fix (a hypothesis, not an instruction)

Dispatch before comparing: a fold-hash of `name` (`NameFoldHash` already exists
and is used elsewhere in the compiler) into a small table of intercept ids, or
at minimum a switch on the first character plus the length so that a miss costs
one comparison instead of 92. The arms themselves need not move.

The correctness hazard is the same one the existing chain relies on: **order**.
Some arms are reachable only because an earlier arm did not match, and a hash
dispatch loses that ordering for free. So the change is only safe if the arms
are mutually exclusive on the name — check that first, and where two arms share
a name, keep them in a nested chain under one hash bucket.

## Gate

Track P's: `make compiler/pascal26` byte-identical fixedpoint + your repro. The
strongest available check is **byte-identity of the emitted output** on a body
of Pascal that exercises the intercepts — `compiler.pas` itself compiles to a
9.1 MB binary and is dense with them, so `compiler.pas` in, `cmp` the two
outputs, is a very sharp oracle for "the dispatch resolves the same arm".

## What it is worth

~9.4% of every compile the Pascal frontend does, on every track. On the NilPy
fixed cost specifically it is ~0.27s of the current ~2.9s.
