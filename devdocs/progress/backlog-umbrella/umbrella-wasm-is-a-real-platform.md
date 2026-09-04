---
slug: umbrella-wasm-is-a-real-platform
title: "wasm as a real platform — emit it, and host the compiler on it"
track: A
prio: 25
type: umbrella
blocked-by: [feature-target-wasm, bug-wasm-hosted-compiler-crashes-node-but-not-wasmtime-on-a-full-compile, feature-t-run-the-wasi-slices-under-wasmtime-as-a-strict-second-host, bug-a-emitzeroframeslot-has-no-wasm32-arm, bug-a-wasm32-has-no-variant-ir-arms-so-any-variant-assignment-traps]
created: 2026-08-31
summary: "GOAL, not a unit of work. wasm is named in the goal's platform list and is the non-Unix platform with the most work already landed -- the wasm branch is merged into master. Two halves: emit correct wasm32, and HOST the compiler under a wasm runtime. The hosted half already has a live crash (node, not wasmtime)."
---

# wasm as a real platform

Named in the owner's platform list alongside linux/bsd/minix/gnu/windows. It is
the furthest along of the non-Linux cells: the `wasm` branch is fully merged
into master (verified 2026-08-31).

Two halves, and the second is the one that counts for the goal:

1. **Emit** correct wasm32 from the shared IR.
2. **Host** the compiler under a wasm runtime — the "minimal system with
   compiler" property, on a platform with no processes and no syscalls.

The hosted half already has a concrete failure wired here: the hosted compiler
crashes node but not wasmtime on a full compile, which is a genuine divergence
between runtimes rather than a missing feature.

Full goal: `devdocs/dev/the-goal-cross-cross.md`.

## The gap census, 2026-09-03 - attempted, not triaged

300 sources from the test corpus, compiled for wasm32 with the fixed coverage
report (52d134518), which is the first build whose listing can name more than
one gap per body. 14 programs have a broken body; 278 gap instances behind them:

| count | gap |
| --- | --- |
| 222 | `statement IR op 43` -- **IR_VAR_STORE**, the whole Variant family |
| 18 | `value IR op 54` -- IR_SYSCALL (raw syscalls; wasi has none) |
| 8 | `value IR op 33` -- IR_SET_LIT |
| 7+ | `slot <n> has no wasm value type` |
| 3 | `builtin SetLength (-102)` |
| 3 | `builtin FreeMem (-46)` |
| rest | one or two each: IR_SET_BINOP, IR_RTTI_REG, record loads, `=` on strings |

**Variant is not one of several gaps, it is four fifths of them**, which is why
`bug-a-wasm32-has-no-variant-ir-arms-so-any-variant-assignment-traps` is wired
in here. This is an umbrella grown by ATTEMPTING the target: the ranking came
out of compiling real programs, not out of reading the backlog.

Scope limit: 278 is a FLOOR by construction -- a body stops at its first refusal
-- so the tail is understated relative to the head. It cannot overstate op 43.

## Where it stands, 2026-09-04 (frankA) - WITH THE DENOMINATOR THIS TIME

### THE CENSUS I HAVE BEEN QUOTING WAS A RATE OVER A POPULATION I NEVER STATED, AND THE POPULATION MOVED BY 109 WHILE I WAS QUOTING IT

Every "N gap instances over 300 sources" figure in this section's earlier
versions -- 278, 70, 57, 42, 26, 22, 20 -- counted refusals **among the sources
that reached the wasm32 backend at all**. A source that fails EARLIER produces
no coverage report, so it scored as *zero gaps* while never having been
measured. That is the exact failure my own notes call "a zero can be vacuous",
committed for two days against my own rule.

Measured at `2eef6bc98`, immediately before `bce31c210` landed:

| | count |
| --- | --- |
| sources attempted | 300 |
| `is a unit, not a program` -- not applicable on any target | 31 |
| corpus unit not present in this tree | 6 |
| inline asm -- out of scope for this target by design | 19 |
| **in-scope programs** | **244** |
| **reached the wasm32 backend** | **91** |
| failed in the FRONT END, mostly `undefined variable (SYS_openat)` | 133 |
| coroutine context switch not implemented | 14 |
| `{$threadsafe}` unsupported here | 6 |

**So "5 programs with gaps" was 5 of 91, not 5 of 300**, and the 86 "clean"
programs were 86 of 91. The headline that a reader takes from it -- *wasm32 is
nearly clear* -- was false: **63% of in-scope programs never got as far as the
backend the census measures.**

The same census at `bce31c210`, which routed the Pascal RTL to the real wasi
PAL:

| | before | after |
| --- | --- | --- |
| in-scope programs | 244 | 242 |
| **reached the wasm32 backend** | **91** | **200** |
| front-end failures (the `SYS_*` wall) | 133 | 15 |
| of those reached: clean | 86 | 110 |
| of those reached: with gaps | 5 | **90** |
| gap instances | 20 | 177 |

**The gap count going 20 -> 177 is not a regression and nothing broke.** One
hundred and nine more programs now get far enough to be measured, and their
refusals became visible for the first time. A metric that improves when the
population shrinks and worsens when it grows is not measuring what its name
says, and mine did both without my noticing, because the denominator was never
printed.

`tools/`-side fix so the mistake cannot be re-expressed rather than merely
noted: the census script now prints REACHED THE BACKEND as the denominator and
labels pre-codegen failures *never measured; not zero gaps*.

### What is actually left, 2026-09-04, at `bce31c210`

**Forty-two in-scope programs still do not reach the backend**, and the two
real groups are ours:

| count | why | owner |
| --- | --- | --- |
| 21 | `coroutine context switch not implemented` | open, this target |
| 6 | `{$threadsafe}` is x86-64/i386/aarch64/arm32 only | by design today |
| 15 | assorted front-end, incl. `wasm: duplicate export "Loc$N"` | mixed |

**Of the 200 that reach it, 90 have a gap and 110 are clean.** The 177 gap
instances are TWELVE distinct bodies, not 177 problems:

| instances | body | shape |
| --- | --- | --- |
| 82 | `Sleep` | `__pxxrawsyscall` with a RUNTIME `-1` guard |
| 45 | `TerminalSize`, `AnsiWrite`, `AnsiSetRawMode`, `AnsiReadKeyWait`, `AnsiReadKey` | same |
| 28 | `__pxx_time`, `__pxx_exit`, `__pxx_clock_gettime`, `__pxx_clock` | same |
| 7 | `OSEntropyBytes` | same |
| 1 | `fpgettimeofday` | same |

All twelve are the shape frankb-78 named while fixing pypal: **the promise of
soft failure is made at RUNTIME while the syscall instruction is still
EMITTED**, so the body does not fail softly, it fails to compile. `Sleep` alone
gates 82 of the 200. Twelve edits, not 177.

The genuine wasm32 CODEGEN tail is six shapes:

| count | gap | owner |
| --- | --- | --- |
| 4 | `value IR op 32` -- IR_RTTI_REG, in `GetClass` | open |
| 2 | `string expression nested more than 16 deep`, and `` `+` on strings `` behind it | open |
| 1 | `value IR op 68` | open |
| 1 | `statement IR op 60` | open |
| 1 | `value of type Pointer assigned to a managed string` | open |
| 1 | `load through a pointer of type record` | **filed**, `bug-a-wasm32-refuses-a-load-of-an-interface-valued-record-field` (DO NOT WIDEN the aggregate-address family: an interface is spelled `tyRecord`) |

### Earlier corrections, kept because the numbers were quoted to peers

`26 gap instances` counted two lines the report itself labels *not a coverage
gap*; `19 IR_SYSCALL` was 18 in every saved output back to the first; and
`value IR op 32` was never in the table at all. The last two cancel exactly --
19 + 0 = 18 + 1 -- so the SUM reconciled with the previous run on every one of
four re-measurements while two of six rows were wrong throughout. **A total
that agrees is not evidence about its components.**

### Closed to get here

Each with a cross row wired against the x86-64 build of the same source:

- Variant (`IR_VAR_STORE/BOX/BINOP`) -- 222 instances, four fifths of the
  original census. It did NOT move the program count at all (14 -> 14): a body
  count and a gap count are different measurements.
- Sets -- literal, binop, compare, and `x in s` over a real set, each of the
  last three invisible until the one in front was fixed.
- By-value aggregate parameters -- every record of 8 bytes or less and every
  by-value set parameter.
- `IR_VMTADDR` -- interface `is`/`as`. Found by running a peer's test, not by
  this census: nothing in the corpus casts to an interface.
- Aggregate returns through an indirect or virtual call.
- Calls through a METHOD POINTER (`99fa70c34`). The IR already carried the
  answer -- `IRC` on `IR_CALL_IND` is *extra leading Self args* -- and this is
  the only backend that has to read it, because it is the only one whose call
  sites are checked against a type.
- The compare-operand classifier (`2eef6bc98`): the IR tag could widen a
  pointer to a string and not narrow a string to a pointer, so
  `Pointer(s) = nil` -- which is `pystr_is_none`, how every NilPy `is None`
  test is answered -- refused as a string compare. That closed the LAST of the
  five tests excluded from this target.

**`builtin FreeMem (-46)` LEFT THE TABLE WITHOUT ANYONE FIXING FreeMem.**
wasm32 has had a working FreeMem arm throughout; `WasmEmitFreeMem` exits False
on its own `if WasmBodyBroken then Exit`, so once the refusal above it in the
same body latched, the arm reported itself. The report now names a builtin only
while the body is still unbroken (`99fa70c34`). A second gap standing behind a
first is usually the next real one -- it was, four times in this arc -- and it
can also be a GHOST of the first, so the test is whether it survives fixing the
one in front.

**Two findings on OTHER targets came out of tests written for this one**, which
is the argument for cross rows over wasm32-only ones:
`bug-a-a-parameter-after-a-by-value-set-parameter-reads-zero-on-xtensa` (fixed,
`724e04ea6` -- a by-value set parameter carried only its first four bytes) and
`bug-p-member-access-on-a-procedural-variable-call-result-is-rejected` (filed).
