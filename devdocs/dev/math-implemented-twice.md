# Math is implemented twice — C's and Pascal's, deliberately

`lib/crtl/src/math.c` and `lib/rtl/math.pas` are two independent maths
libraries in one compiler. That is **intended**, it is not duplication to be
cleaned up, and this page exists because the reverse assumption has already cost
real time twice.

## The rule

> **Share what the machine provides. Duplicate what the language specifies.**

Heap, syscalls, threads, ELF, the IR — one implementation, reached through
explicitly prefixed entry points (`__pxx_malloc`, `__pxx_read`, 100+ of them in
crtl). Those are properties of the *machine*, identical whoever asks.

`floor`/`Floor`, `round`/`Round`, truthiness, index base, integer division — each
language's **own**, because each language *specifies* them differently. A shared
implementation cannot be right for both; it can only be right for one and quietly
wrong for the other.

## The evidence: each side matches its OWN reference, exactly

Measured 2026-08-14, same expressions on both sides, each against its own oracle.

**C side — pxx vs gcc, 10/10 identical:**

```
round 2.5 = 3.0   round 3.5 = 4.0   round -2.5 = -3.0
floor -2.5 = -3.0  ceil -2.5 = -2.0  fmod -7,3 = -1.0
pow 0,0 = 1.0      pow -8,1/3 = -nan  log 0 = -inf   sqrt -1 = -nan
```

**Pascal side — pxx vs FPC, 9/9 identical:**

```
Round 2.5 = 2     Round 3.5 = 4     Round -2.5 = -2
Floor -2.5 = -3   Ceil -2.5 = -2    FMod -7,3 = -1.0
Power 0,0 = 1.0   Trunc -2.7 = -2   Frac -2.75 = -0.75
```

Both are correct. **They disagree with each other**, and that is the whole point.

## The divergences that bite

### 1. `Round` — the flagship

| | 2.5 | 3.5 | -2.5 |
| --- | --- | --- | --- |
| Pascal `Round` | **2** | 4 | **-2** |
| C `round` | **3** | 4 | **-3** |

Pascal rounds half to **even** (banker's rounding); C rounds half **away from
zero** (C99). Same name, same argument, different answer, both right. A shared
implementation would have to pick one and silently corrupt the other language's
arithmetic — and it would do so only on exact halves, which is exactly the input
a casual test does not use.

### 2. Return TYPE — `Floor`/`Ceil`/`Trunc`

Pascal's return an **Integer**; C's return a **double**. Not a style difference:
it gives the Pascal versions a range, and therefore a failure mode C does not
have.

```
C:      floor(1e30) = 1000000000000000019884624838656    (exact, no range to leave)
Pascal: Floor(1e30)  = 2147483647                         (pxx — saturates)
        Floor(1e30)  = EInvalidOp                         (FPC — raises)
```

This is why `Floor64`/`Ceil64` exist on the Pascal side and have no C
counterpart — the C signature never needed them.

**pxx saturates where FPC raises, and that is BY DESIGN — not an oversight.**
Decided 2026-08-14 (`decide-may-uses-math-cost-the-heap-and-exception-runtime`,
user: *"We do it our way unless strict-fpc is set."*). Three reasons, all
measured:

1. **pxx follows IEEE MASKED semantics.** `1/0` is `Inf` here and a runtime
   error in FPC. IEEE-754 specifies *flags*, not traps; x86, ARM, RISC-V and
   Xtensa all leave FP exceptions masked, and FPC deliberately **unmasks** them.
   Raising from `Floor` alone would be an island in our own behaviour.
2. **The dependency is not free.** `Exception` is only reachable via `uses
   sysutils`, and pulling it into `math` roughly doubles code and quadruples bss
   for anything that says `uses math` (52 KB → 123 KB → 251 KB code; 9.5 KB →
   9.5 KB → 42.7 KB bss). On an ESP32 that is decisive, and an embedded program
   should not abort on a math edge case.
3. **`Floor(1e30) = 0` was the real defect**, and it is gone. INT64_MIN narrowed
   to `Integer` keeps its zero low half, so an out-of-range *magnitude* became
   the *smallest* answer and `if Floor(x) > limit` passed. Saturation to
   `High`/`Low` of the return type makes that guard fire.

Only the **Int64** conversion is policed. `Floor(3e9)` converts to Int64 fine and
then wraps on the narrowing to `Integer` — FPC returns `-1294967296` there and
does **not** raise, and pxx matches it. NaN takes the negative sentinel.

FPC's raise is to become opt-in under a strict flag; enrolling it in the
`--strict-fpc` umbrella is a separate call, since it would change what that
umbrella costs for the corpora it is proven to compile.

### 3. The surfaces do not even align by name

Not a subset relationship in either direction:

| concept | Pascal | C |
| --- | --- | --- |
| natural log | `Ln` | `log` |
| log to base n | `LogN(base, x)` | — |
| exponentiation | `Power`, `IntPower` | `pow` |
| arctangent | `ArcTan`, `ArcTan2` | `atan`, `atan2` |
| int-ranged floor | `Floor`, `Floor64` | — |
| fractional part | `Frac`, `Int` | `modf` |
| combinatorics, gcd/lcm | `Comb`, `Factorial`, `Gcd`, `Lcm` | — |
| float classification | `IsNan`, `IsInf` | `isnan`, `isinf` |
| — | — | `cbrt`, `expm1`, `log1p`, `nextafter`, `frexp`, `ldexp`, `copysign` |

`log` and `Ln` are the same function under different names; `Log10`/`Log2` exist
on both sides. Nothing about these lines up well enough for one library to serve
both.

## Accuracy: crtl's libm is correctly rounded, and does NOT match glibc

Decided 2026-07-20 (`decide-crtl-libm-glibc-bit-parity`): crtl's libm keeps
**correct rounding** where glibc is not correctly rounded. We do not reproduce
glibc's errors to make differential testing quieter. 114 functions on
double-double kernels.

**Claims discipline applies here.** State it as *"correctly rounded, judged
against high-precision references"* — **never** *"matches glibc"*. The entire
point is that in those cases we deliberately do not match it, and calling it a
match would be both false and self-defeating.

## Why this page exists — the two incidents

**1. Sharing was tried and it broke C.** `pxxcio.pas` is auto-pulled into every C
program and did `uses math`, putting the whole Pascal math unit in scope for C
name resolution, case-insensitively. Adding a Pascal `Pow` made C's `pow(2,10)`
return 1. `CopySign` made `copysign(3,-1)` return `atan2`'s result. Then a
*correct* Track B change — `Floor` returns Integer, FPC-faithful — broke a C
test, because C's `floor` had silently bound to it months earlier.

Neither side could see the other. **A Track B author improving the Pascal RTL had
no way to know they were editing C's standard library.**

The user's retrospective is the sharpest statement of the rule:

> *"no shame in double code. since, math.c and math.pas do not behave identical.
> there are more differences. the choice for 'oh, and C can just use pascal's
> math library' was a wrong one, in retrospect."*

**2. The name scars are gone (2026-08-16).** Ten functions in
`lib/crtl/src/math.c` were named `__crtl_exp`, `__crtl_log2`, `__crtl_sin`, …
purely to dodge the case-insensitive collision, reached through `#define`s in
crtl's `math.h`. The collision stopped firing when `pxxcio.pas` dropped
`uses math` — the Pascal RTL is not in scope for an ordinary C program — and
`task-c-retire-the-crtl-name-dodge-prefixes` de-prefixed all ten. The case that
kept them alive was measured, not assumed: a Pascal program that does
`uses math` AND `uses './x.c'` gets the right answer from `exp(1.0)` in C and
`Exp(1.0)` in Pascal, both.

That does NOT retire the rule below — it closes the C-to-Pascal direction only.
A Pascal program that `uses './math.c'` still loses its own `Exp`, which is what
`feature-a-own-language-first-symbol-resolution` is for.

## Consequences for name resolution

This is *why* "own language first" is a rule rather than a nicety: with two real
implementations of `exp`, "which one does this call mean" has to be answered by
the caller's language, not by import order. The rules, what is built and what is
not, and the open design fork are in **`name-resolution.md`**.

## Where things live, and what is stale

| | |
| --- | --- |
| C maths | `lib/crtl/src/math.c`, declared in `lib/crtl/include/math.h` |
| Pascal maths | `lib/rtl/math.pas` |
| how a C program finds crtl | `c-linking-and-crtl-autopull.md` |

Two stale docs to fix when someone is in there (both Track C/B files, not touched
from here): `lib/crtl/README.md` and `lib/crtl/src/README.md` still describe
`src/` as *"reserved for small C runtime implementations once a candidate needs
them"*. It holds a 114-function correctly-rounded libm. And
`c-linking-and-crtl-autopull.md` still calls math.c's `sqrt`/`sin`/`pow` *"a thin
bridge to the Pascal RTL"* — they have had real double-double C bodies since the
2026-08-10 split.

## The general shape

Math is the worked example, not the only case. The same split applies wherever a
language *specifies* behaviour rather than exposing the machine: string
semantics, integer division and modulo sign, truthiness, index base, exception
hierarchies (`sysutils` and `pylib` each declare their own `Exception`). When in
doubt, ask **"does the language specify this, or does the machine provide it?"** —
specify means duplicate, provide means share behind a prefixed entry point.
