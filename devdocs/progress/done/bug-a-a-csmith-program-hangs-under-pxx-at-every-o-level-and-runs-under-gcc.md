---
track: C
prio: 55
type: bug
status: done
blocked-by: []
owner: ""
summary: "DIAGNOSED, and the lane moved to C. The spin is not in func_58 but one frame below it, in lib/crtl/src/stdlib.c:528 __pxx_builtin_clz64, whose loop cannot terminate when x is 0: no left shift ever sets the MSB. Four routines are affected -- clz32/clz64/ctz32/ctz64, six spellings -- while the other 12 builtins agree with gcc at zero; ffs is already guarded, with a comment naming clz/ctz as the deliberate exception. Reduces to three lines: int main(void){ volatile unsigned long long v=0; return __builtin_clzll(v); }. clz(0) is UB in C and gcc's answers are garbage (64/36/63 from one expression), so the property to match is that gcc TERMINATES. Guarding the four routines makes the full 1939-line repro print gcc's checksum 5ABA20EA -- but that checksum is insensitive to the guard value (0, 7 and 63 all give it), so it proves termination only. Fix is Track C's file; frankA did not edit it."
---

# A csmith program hangs under pxx at every `-O` level, and runs under gcc

- **Found:** 2026-08-30 by frankC, first run of the csmith `--builtins` axis.
- **Repro:** `test/csmith/hang_builtins_700082.c` (kept verbatim — see that
  directory's README for why a seed is not enough).
- **Compiler:** self-host fixedpoint `883476f0abaf`, `converged after 1 round(s)`.

## The measurement

```
gcc  -w -I/usr/include/csmith          -> runs, prints "checksum = 5ABA20EA", exit 0
pxx  -I/usr/include/csmith ...         -> compiles clean (exit 0), binary HANGS
```

The compile is fine — `ok: ... [code=585496B data=14648B bss=69192B procs=829]`,
exit 0. The failure is entirely at runtime.

## What has been ruled out, by measuring rather than reasoning

**1. It is not an optimizer bug.** Every level hangs, including `-O0`:

| `-O0` | `-O1` | `-O2` | `-O3` |
| --- | --- | --- | --- |
| hang | hang | hang | hang |

This matters for where to look: a pass cannot be the culprit if the level with
no passes also hangs. (It also means the CLAUDE.md caveat about the self-host
gate proving only the default `-O` is not the story here.)

**2. It is not a wrong builtin, despite being found on the `--builtins` axis.**
The program uses 15 distinct builtins. I tested every one of them directly
against gcc over `{0, 1, 2, MSB-set, all-ones, 0x0123456789ABCDEF}`:

```
__builtin_clz clzl clzll ctz ctzl ctzll popcount popcountl
parity parityl parityll ffsl ffsll bswap32 bswap64
```

**All agree with gcc, every value.** So `--builtins` found this bug by
generating a program shape, not by exercising a broken builtin — worth stating
plainly so nobody re-runs that comparison.

**3. Two specific loop hypotheses, both refuted.** `func_58` contains loops
whose termination depends on exact integer typing, and the obvious suspects are
wrong:

- `for (g_195 = -27; g_195 > 14; g_195 = safe_add_func_uint64_t_u_u(g_195,4))`
  — `g_195` is `int32_t`, so gcc never enters. A minimal version agrees with gcc
  (`iterations=0 g=-27`). **Not it.**
- `for (l_671 = 25; l_671 != 19; l_671 = safe_sub_func_uint16_t_u_u(l_671,2))`
  — `!=` termination driven by a `uint16_t` subtraction, the most fragile shape
  in the function. Minimal version agrees (`n=3 l=19`), as do `l_817`'s `!=`
  counter and `p_63`'s unsigned-wrap guard. **Not it either.**

Recording these because they are the two anyone would try first, and both cost a
measurement to eliminate.

## Where it is

Entry instrumentation (a one-shot `printf` at the top of each generated
function, applied to both compilers' builds of the SAME instrumented source):

```
gcc:  enters all 10 functions, ends "checksum = 5ABA20EA"
pxx:  enters 8, last is  ENTER func_58,  then spins
```

So the defect is inside `func_58` (definition at line 1012 of the repro, ~349
lines) or something it calls. It is not reached-and-returned: the 9th and 10th
functions gcc enters are never entered.

## What is NOT established — read before assuming a lane

**The lane is a guess.** Filed **A** because a runtime hang that survives `-O0`
and does not reduce to a small loop shape is most likely IR lowering or codegen,
which is A's — the fuzz-routing convention (`IR/codegen -> A, dialect/frontend
-> P, RTL -> B`). But nothing here proves it is not the C frontend's lowering,
and `func_58` has not been reduced to a minimal case. **If reduction lands it in
`cparser.inc`, re-file it to C rather than arguing the letter** — the evidence
above is lane-neutral.

No reducer is installed on this box (`creduce`/`cvise` both absent), which is
the single thing that would most speed this up; a `--builtins` finding that
survives reduction is a much smaller ticket than 1939 lines.

## Frequency

3 hits over 120 iterations, **1 distinct** (seeds 700082, 700093, 700106 all
reduce to the same finding). The other 117: 40 agreed with the gcc oracle, 77
were skipped because the native validity filter could not build them — see the
campaign ticket for why that skip rate is a property of the axis, not a fault.

## Related

- Campaign: `feature-c-csmith-differential-fuzzing`
- Why the program and not the seed: `bug-t-a-fuzz-finding-cited-by-seed-alone-cannot-prove-a-fix`


---

# DIAGNOSED — 2026-08-30, frankA. Root cause found; the lane was wrong.

Compiler: self-host fixedpoint `2b3c4389cd35`, `converged after 1 round(s)`.

## It is not in `func_58`, and it is not codegen

`func_58` is where the entry instrumentation stopped, so the ticket reasonably
localized there. It is one frame too high. The spin is in the **C runtime
library**:

```
lib/crtl/src/stdlib.c:528   __pxx_builtin_clz64
  while (!(x & 0x8000000000000000ull)) { x <<= 1; n++; }
```

**`x` is 0.** With no bit set, no amount of left-shifting sets the MSB, so the
loop cannot terminate. Measured, not read — a breakpoint conditioned on an
iteration count no legitimate call can reach (`n > 200`; the honest maximum is
63):

```
Breakpoint 1, __pxx_builtin_clz64 (x=0) at lib/crtl/src/stdlib.c:528
$1 = 0x0    n = 201
#1  func_58 (...) at test/csmith/hang_builtins_700082.c:1359
#2  func_38 (p_39=0)   #3  func_28 ()   #4  main ()
```

Line 1359 is `__builtin_clzl(safe_mul_func_uint8_t_u_u(255UL, ...))`, whose
argument evaluates to 0 at runtime.

Found by step-sampling rather than by reduction: 30,000 `stepi` under gdb,
histogrammed by (function, line). **28,420 of 30,000 samples — 95% — sit on that
one line.** No reduction was needed, and frankC's reducer was never run.
(ptrace attach is blocked by yama on this box; launching under gdb works.)

## The 1,939-line repro reduces to three lines

```c
int main(void) { volatile unsigned long long v = 0; return __builtin_clzll(v); }
```

pxx: hangs. gcc: exits. The literal form `__builtin_clzll(0)` hangs under pxx
too — we do not constant-fold it, we call the helper.

## The sibling census — 4 routines, 6 spellings, and 12 that are fine

Per `normalise-dont-special-case`, swept every builtin the program uses at zero,
**each in its own process** so one hang could not mask another:

| builtin(0) | gcc | pxx |
| --- | --- | --- |
| `clz` `clzl` `clzll` | 31 / 63 / 63 | **HANG** |
| `ctz` `ctzl` `ctzll` | 0 / 0 / 0 | **HANG** |
| `popcount{,l,ll}` `parity{,l,ll}` `ffs{,l,ll}` `bswap{16,32,64}` | 0 | 0 (agree) |

Four distinct routines: `__pxx_builtin_clz32`, `clz64`, `ctz32`, `ctz64`. The
loops in `popcount`/`parity` are `while (x)`, which exits immediately at zero,
and `bswap` has no loop.

**The zero case was already known in this file.** `ffs32`/`ffs64` carry
`if (x == 0) return 0;` under a comment reading *"Unlike clz/ctz, ffs is DEFINED
at zero -- do not route it through ctz."* So the author guarded the one that is
defined at zero and deliberately left the two that are not. This is a comment
recording a hazard on one arm while the sibling arms stay unguarded —
[[a-comment-recording-a-bug-is-not-a-guard-against-it]].

## Why the ticket's "all 15 agree with gcc, including 0" did not catch it

Not disputed, but it cannot have exercised this path — clz/ctz at zero hang
here in every form tried, literal and runtime. Worth knowing which harness
produced that row before it is relied on again, because a builtin check that
reports agreement at zero on a routine that cannot return at zero is measuring
something other than the routine.

## The C standard's view, which decides how this should be fixed

`__builtin_clz(0)` is **undefined behaviour** — gcc documents the result as
undefined at zero, and its answers above prove it: the same expression yields
64 folded, 36, and 63 depending only on how the argument reaches it. So gcc is
not "right" here in the sense of having an answer we should match. **gcc's
property that matters is that it TERMINATES.** Ours does not, and an infinite
loop is the worst available response to a UB input: unlike a garbage value it
cannot be checked, timed out around, or fuzzed past.

## The fix, measured end to end — and what that measurement does NOT prove

Adding `if (x == 0) return <width>;` to the four routines (tested against a
scratch COPY of `lib/crtl`, leaving Track C's file untouched):

```
pxx WITH guards:  checksum = 5ABA20EA   exit 0
gcc oracle:       checksum = 5ABA20EA   exit 0
```

The full 1,939-line program now runs and matches the oracle exactly.

**But the checksum is insensitive to the returned value, so it validates
termination and nothing else.** Falsified rather than assumed — re-ran the whole
program with the guard returning 0, 7 and 63:

```
guard returns 0  -> checksum = 5ABA20EA
guard returns 7  -> checksum = 5ABA20EA
guard returns 63 -> checksum = 5ABA20EA
```

Identical every time. Anyone reading "matches the oracle" as evidence that 64 is
the correct value would be reading a constant. The value has to be argued
separately: **the width** (64/32) is what the hardware `lzcnt`/`tzcnt`
instructions return at zero, and what gcc's own constant folder produced for the
literal, which is the only self-consistent choice available.

## LANE: this is Track C, not Track A

The ticket said the lane was a guess and to re-file rather than argue if
reduction moved it. It did — just not to `cparser.inc`. `lib/crtl/src/stdlib.c`
is Track C's file, so **the fix is frankC's to make**; frankA did not edit it.
Everything needed is above: the 3-line repro, the 4 sites, the value argument,
and the end-to-end check with its own limit stated.

## For the fuzzing campaign — the bigger finding

**The `--builtins` axis is generating programs with undefined behaviour.** This
one calls `__builtin_clzl(0)`, and csmith's value proposition is UB-free output.
That bears on every finding from this axis, not just this one: where the
generated program is UB, a pxx-vs-gcc difference is not by itself a defect,
because gcc's own answer is not stable either (64 / 36 / 63 above, from one
expression). Worth deciding before the axis is trusted at scale —
`feature-c-csmith-differential-fuzzing`. Note this cuts only one way here: the
UB does not excuse the hang, it just means the *checksum* comparison on such
programs proves less than it appears to.

## RESOLVED — `__builtin_clz(0)` spun in `lib/crtl`. And one claim above is FALSE.

Diagnosed by frankA (`defee4ab2`), fixed under Track **C** (`99b556c43`) since
`lib/crtl` is C's. The lane guess in this ticket was wrong in the direction the
ticket said to expect — it was not IR/codegen — and re-filing rather than arguing
the letter is what the "lane is a guess" note was for.

```c
int __pxx_builtin_clz64(unsigned long long x) {
  int n = 0;
  while (!(x & 0x8000000000000000ull)) { x <<= 1; n++; }   /* x == 0: never terminates */
```

Six spellings over four routines (`clz`/`clzl`/`clzll`, `ctz`/`ctzl`/`ctzll`).
`ffs` in the same file was **already guarded**, under a comment saying ffs is
DEFINED at zero "unlike clz/ctz" — so the defined case was protected and the two
undefined ones were left to spin.

### The false claim: "all 15 builtins agree with gcc, six values each including 0"

**That row is wrong and should not be relied on.** My harness guarded the
bit-scan builtins:

```c
if (u[i])  printf("clz %d=%d ctz=%d\n", i, __builtin_clz(u[i]), __builtin_ctz(u[i]));
```

`u[0]` is 0, so `clz`/`ctz` **never saw zero** — the harness skipped precisely the
input that hangs, then reported agreement. A check that reports agreement at zero
on a routine which cannot return at zero is measuring something else. frankA
questioned the row rather than accepting it, which is how it was caught.

The other builtins (`popcount`, `parity`, `ffs`, `bswap`) were genuinely tested at
zero and do agree.

### `func_58` was as close as entry-counting can get

The instrumentation named the last **instrumented** frame. The routine that never
returned is in the runtime library and had no probe of its own, so the method
could not point past it. Found instead by step-sampling: 30,000 `stepi` under gdb,
histogrammed by (function, line), 95% on one line.

### Carry-in for the campaign — the axis generates UB

`__builtin_clz(0)` is **undefined** in C, and gcc's own answers vary with how the
argument arrives (64 folded for a literal, other values at runtime). That does not
excuse a hang — a hang is never an acceptable response to UB, and this one is
fixed — but it does mean **a checksum divergence on such a program is not by
itself a defect**. `feature-c-csmith-differential-fuzzing` should carry a
UB-rejecting predicate before `--builtins` is trusted at scale; noted there.

Regression test `test/c_builtin_bitscan_zero.c`, wired with a **timeout**, because
the failure mode is a hang and a plain run of a hanging test hangs the suite
rather than failing it.

## Log
- 2026-08-30 — resolved, commit be131e1dc.
