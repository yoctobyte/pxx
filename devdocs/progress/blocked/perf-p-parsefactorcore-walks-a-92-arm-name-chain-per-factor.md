---
track: P
prio: 60
status: blocked
owner: ""
type: perf
blocked-by: [perf-a-a-string-literal-passed-to-an-ansistring-parameter-is-copied-every-call]
summary: "SUPERSEDED PREMISE (frankB, 2026-08-30): the 9.4% is NOT the 92-arm walk. CaseEqual already compares lengths first and bails at the first differing char, so a miss is O(1) and 1.58M O(1) compares cannot be 9.4% of a run — the original ticket counted calls and inferred cost from the count. Measured cause: passing a string LITERAL to an AnsiString parameter allocates and copies it every call (543ms vs 30ms for a typed constant over 5M calls; cost scales with literal length), so each of the up-to-101 arms copies a string. Root cause filed as perf-a-a-string-literal-passed-to-an-ansistring-parameter-is-copied-every-call [A p70]; this ticket is blocked on it and is likely MOOT once it lands — re-measure before implementing anything here. Traps banked in the body: the arms are not an else-if ladder, `name` is reassigned at 8 points inside the function, and 25 of 101 names repeat."
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

## 2026-08-30 (frankB) — the 92-arm walk is the SYMPTOM; each arm allocates a string

Binary: HEAD, self-host fixedpoint `faf762981c3c` (= pin v397). `perf` is
unavailable on this box (`perf_event_paranoid=4`, zero-sized capture), so this
is measured by direct A/B timing rather than by profile.

### The premise does not survive a look at `CaseEqual`

`CaseEqual` (`defs.inc:5322`) is **already optimal**: it compares lengths first
and returns, then bails at the first differing character. A miss against a
length-mismatched name is O(1). So "38.6 string compares per factor" should cost
almost nothing, and the arithmetic never worked — 1.58M O(1) compares cannot be
9.4% of a run.

### What it actually is: passing a LITERAL to an `AnsiString` parameter copies it

Five million calls each, same machine, same binary:

| form | ms |
| --- | --- |
| `if n = 'await'` — inline compare against a literal | **19** |
| `if n = lit` — inline compare against a variable | 22 |
| `ByConst('await')` — literal into a `const AnsiString` param | **543** |
| `ByVal('await')` — literal into a by-value `AnsiString` param | 576 |
| `ByConst(S_AWAIT)` — a typed `const S_AWAIT: AnsiString` | **30** |

**28x**, and it is a copy, not fixed call overhead — the cost scales with the
literal's LENGTH (5-char literal 791ms, 40-char literal 2151ms, variable 51ms
over 5M calls). Comparing against a literal *inline* is free; **passing** one to
a string parameter allocates and copies it, every call, even for `const`, where
by definition no copy is needed.

So `ParseFactorCore` is not slow because it walks 92 arms. It is slow because
**each arm it walks allocates and copies a string literal**, and it does that up
to 101 times per factor.

### This is not a ParseFactorCore bug and should not be fixed here

Every `CaseEqual(x, 'literal')` in the compiler pays it, and so does every pxx
program that passes a string literal to a string parameter. Filed as
[[perf-a-a-string-literal-passed-to-an-ansistring-parameter-is-copied-every-call]]
with these measurements.

**Microfix vs overhaul, decided deliberately** per
`devdocs/dev/root-cause-over-microfix.md`: the microfix available in P's own
file is to hoist the 73 distinct literals into typed constants, which the table
above says would buy ~18x on these calls. **I am not doing it.** It is 101
mechanical edits in a 7,790-line function that become dead weight the moment the
Track A fix lands, and it would leave the same defect in every other caller and
in user code. The ticket's own suggested fix — hash dispatch — is a second
microfix: it reduces the NUMBER of copies rather than removing the copy, and it
carries a real correctness hazard (below) for a fraction of the win.

### If anyone does return to the dispatch idea, two facts it needs

1. **The arms are not an `else if` ladder.** They are ~54 independent `if
   CaseEqual(name, '...') and <more> then begin ... end` statements at indent 6,
   spread over 7,790 lines, plus ~47 nested deeper. There is no single chain to
   reorder.
2. **`name` is REASSIGNED at 8 points inside the function** (`:786`, `:1947`,
   `:3521`, `:3781`, `:3819`, `:3827`, `:5954`, `:7253`), so any hoisted
   per-name guard computed once at entry is silently WRONG after the first
   reassignment. This is the trap in the obvious implementation.
3. The order hazard the ticket warns about is real and larger than stated: of
   the 101 sites, **25 names appear more than once** (`Abs` 4x, `round` 3x,
   `hex`/`oct`/`trunc`/`frac`/`Eof`/`Chr`/`Succ`/`Concat`/`Copy` and the
   `__pxx*` intrinsics 2x each).

### Gate, unchanged and still the right one

`make compiler/pascal26` fixedpoint + `compiler.pas` in, `cmp` the two emitted
binaries. That oracle is what makes the Track A fix safe to land, since a
codegen change to literal marshalling must not alter a single emitted byte.
