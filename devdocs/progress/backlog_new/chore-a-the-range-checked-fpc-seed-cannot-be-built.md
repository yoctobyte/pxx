---
track: A
prio: 35
type: chore
blocked-by: []
status: backlog
owner: ""
summary: "`fpc -Cr compiler/compiler.pas` does not compile: five `$`-constants in the aarch64/arm32 encoders are rejected as out of Integer range while being folded into an Integer parameter. So the one build that would report an array index out of bounds — the FPC seed with range checking — is unavailable, and the repo debugs out-of-bounds writes by guessing instead."
---

# The range-checked FPC seed cannot be built

Found 2026-08-24 while diagnosing
[[bug-a-aarch64-o3-segfaults-the-compiler-on-an-empty-program]] — an
out-of-bounds write into three parallel arrays. A range-checked build would have
named the array and the index in one run. It could not be built.

## Measured

```
$ fpc -O1 -g -gl -Crtoi -Tlinux -Px86_64 -opxx-dbg compiler/compiler.pas
ir_codegen_aarch64.inc(1774,40) Error: range check error while evaluating constants (3019898882 must be between -2147483648 and 2147483647)
ir_codegen_arm32.inc(312,34)    Error: ... (3925868544 ...)
ir_codegen_arm32.inc(333,34)    Error: ... (3120562176 ...)
ir_codegen_arm32.inc(334,34)    Error: ... (3388997632 ...)
ir_codegen_arm32.inc(357,33)    Error: ... (3925868544 ...)
Fatal: There were 5 errors compiling module, stopping
```

Five sites, all the same shape: a machine-code word written as a hex literal
with the top bit set, passed to a routine taking an `Integer`.

```pascal
EmitOvfCheckA64($B4000002);             { cbz x2, skip }
BrArm32(bSt, CodeLen, $EA000000);       { b   .st      }
```

Without `-Cr` FPC folds these silently as the intended bit patterns; with it,
the fold is checked against `Integer`'s range before the (wrapping) assignment
and fails. Note it is a **constant-folding** error, not a runtime check — the
code is correct, the *spelling* is what `-Cr` will not accept.

## Why it matters more than five lines suggest

`-Cr` is the only tool this repo has that reports an array index out of bounds
with a file, a line and the offending value. The self-hosted compiler has no
such mode, and an out-of-bounds write into a parallel-array family is a failure
shape this codebase has by construction: `symtab.inc` alone grows ~30 arrays in
lockstep, `defs.inc` warns *"a missed one is a silent out-of-bounds"*, and the
bug that prompted this ticket was three arrays sized for the wrong backend.

The alternative used today is to reason about which table might overflow and
test the guess — which worked, and took far longer than a checked run would.

## Shape

Write the five constants in a form both FPC-with-`-Cr` and pxx accept — a
`LongWord`/`Cardinal`-typed constant, or an explicit cast at the call site —
then add a make target (`make fpc-seed-checked` or similar) that builds
`compiler/compiler.pas` with `-Criot -g -gl`, so the checked seed is one command
away the next time something writes past an array.

**Check the whole set, not just the five that error today.** `-Cr` stops at the
first five errors per module; there may be more behind them. And the constants
must keep their exact bit patterns — an encoder that emits a different word is a
far worse bug than the one this closes, so the gate is the encoders' own cross
tests, not just "it compiles".

## Gate

`fpc -Criot -O1 -g -gl compiler/compiler.pas` builds and runs; the resulting
binary compiles the test corpus; `make compiler/pascal26` fixedpoint
byte-identical (the constants must not change what is emitted); `tools/gate.sh
quick` GREEN, plus cross rows for aarch64 and arm32 since those are the two
files touched.
