---
track: A
prio: 55
type: chore
blocked-by: []
status: done
owner: frank-optimize
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

## 2026-08-30 (frank-optimize) — the seed BUILDS. It does not yet RUN, and that is a different bug.

Reproduced at HEAD before planning, as asked. It still failed — and with **10
errors, not the filed 5**, in the two files the ticket names. The ticket's own
warning ("`-Cr` stops at the first five errors per module; there may be more
behind them") was correct, and the line numbers had drifted (aarch64 1774 → 2409).

### Fixed: the constant-folding errors

All 10 sites wrapped as `Integer($XXXXXXXX)`. `fpc -O1 -g -gl -Crit` now exits 0,
and a second iteration of the build found nothing behind them.

The spelling was chosen by measurement, not preference, and the first candidate
I tested looked *catastrophically* wrong before I noticed my own test was
misconfigured — recorded because the trap is cheap to fall into:

| spelling | fpc `-Cr` | value |
| --- | --- | --- |
| `Integer($CA000000)` in **`{$mode objfpc}`** | accepts | `-905969664` ✓ |
| `Integer($CA000000)` with **no mode directive** | accepts | **`0`** ✗ |
| `LongInt($EA000000)` with no mode directive | rejects | — |

With no `{$mode}`, FPC defaults to `fpc` mode where `Integer` is **Smallint
(16-bit)**, so the cast silently truncates to the low 16 bits — `$CA000000` → 0,
`$B4000002` → 2. My scratch test had no mode line, so it printed `0 2 0 0` and
read exactly like "FPC miscompiles this". `compiler.pas` opens with
`{$mode objfpc}{$H+}`, where `Integer` is 32-bit and every value is correct.
**A dialect test written outside the dialect answers a different question.**

Verified in both compilers, in the real mode: `-905969664 / -1275068414 /
-369098752 / -373424128`, identical, matching the intended bit patterns.

### The bit patterns are unchanged — measured, not argued

The ticket's real requirement is that the encoders emit the same words. The
pre-change (`f2bfbb3c94a5`) and post-change (`d965960c9973`) compilers were built
and compared on **aarch64 and arm32**, four programs each (`test_cross_record`,
`test_cross_int64`, `test_cross_sets`, `test_cross_dynarray`): **8 of 8
byte-identical, 0 differ.**

Note the compiler's own sha *does* change (`f2bfbb` → `d965960c`), and that is
expected rather than a failure of the gate's "byte-identical" clause: the source
text changed, so the binary built from it differs. The clause is about what the
**encoders emit**, which is what the A/B above measures.

### Added

`make fpc-seed-checked` → `build/pxx-checked`, with the flag choice documented at
the target.

**`-Co` is deliberately excluded.** The ticket asked for `-Criot`, but `-Co`
(overflow) is a different argument from `-Cr` (bounds): this compiler wraps on
purpose in several places, and `-Co` rejects every one. The stated value of this
ticket is *"the only tool this repo has that reports an array index out of
bounds"* — that is `-Cr`. `-Ci` and `-Ct` are free and kept.

### NOT fixed, because it is a different bug in other lanes' files

**The checked seed builds and then traps at first use.** Dropping `-Co` does not
avoid it; `-Cr` alone still fires:

```
ERangeError: Range check error
  SYMNAMEFOLDHASH,  line 3730 of compiler/symtab.inc
  SYMHASHINSERT,    line 3750 of compiler/symtab.inc
  ADDCONST,         line 4908 of compiler/symtab.inc
```

`SymNameFoldHash` is FNV-1a: `h := (h xor LongWord(b)) * LongWord($01000193)`
overflows 32 bits **by design**. `-Cr` range-checks the assignment back into
`LongWord` and refuses it.

Fix shape measured and confirmed neutral — mask the product:

```pascal
h := ((h xor LongWord(b)) * LongWord($01000193)) and LongWord($FFFFFFFF);
```

Both compilers return `3959789884` for the same input; the unmasked form traps
under `-Crtoi` and the masked one does not. Applied **locally and reverted**, it
gets past the hash and the next trap is the hex-literal lexer,
`lexer.inc:2481` (`n := n*16 + digit` accumulating a 64-bit pattern) — so this is
a chain, not one site.

Those live in `symtab.inc` (frankwasm's, typeref) and `lexer.inc` (shared A/P).
**Not edited concurrently.** Diagnosis banked in
`bug-a-the-range-checked-seed-traps-on-deliberate-wraparound-arithmetic` with the
verified fix, per "bank the diagnosis and park it, never microfix as a
consolation".

**Resolving this ticket** on its own title and scope: the seed could not be
*built*, and now it can. That the built binary then trips on deliberate
wraparound is a defect nobody had seen, because nobody had got far enough to see
it.

### Gate

`make compiler/pascal26` converged, `d965960c9973`. `make fpc-seed-checked`
exits 0. Encoder A/B 8/8 identical on the two touched targets. `tools/gate.sh
quick` GREEN.

One process note, second occurrence this session: the stash-based A/B leaves the
**pre-change binary on disk** while the sources carry the change, and `gate.sh`
then reports a fixedpoint mismatch that looks like a miscompile. It is not — it
is the procedure. Rebuild before gating after any stash A/B.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
