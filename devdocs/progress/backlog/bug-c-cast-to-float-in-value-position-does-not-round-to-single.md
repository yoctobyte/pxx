---
track: C
prio: 55
type: bug
summary: "`(float)i` for ANY integer i keeps double precision unless the result is stored into a float lvalue: `(double)(float)16777217` gives 16777217 where C requires 16777216. Silently wrong values, not a crash; found by gcc_diff_probe, which has been reporting it as a NEW divergence with nobody filing it."
---

# A C cast to `float` in value position never rounds to single precision

- **Type:** bug (silently wrong value) — **Track C** (C frontend: cast
  lowering). Filed by Track T from `tools/gcc_diff_probe.sh`; T owns the tool,
  never the bug.
- **Found:** 2026-08-13, re-measuring the probe's `known` tags for
  `task-t-drop-stale-known-tags-on-string-h-probes`. The probe reports it as
  `1 NEW divergence` on x86-64 today — it is the only one — so it has been live
  and unfiled for some time.

## Repro

```c
#include <stdio.h>
int main(void) {
  unsigned int  ua = 4294967295u, ub = 16777217u;
  int           sa = 16777217;
  long long     lb = 16777217LL;
  printf("%.17g %.17g %.17g %.17g\n",
         (double)(float)ua, (double)(float)ub,
         (double)(float)sa, (double)(float)lb);
  return 0;
}
```

| | gcc (oracle) | pxx |
|---|---|---|
| `(float)4294967295u` | 4294967296 | **4294967295** |
| `(float)16777217u` | 16777216 | **16777217** |
| `(float)16777217` (int) | 16777216 | **16777217** |
| `(float)16777217LL` | 16777216 | **16777217** |

16777217 is 2^24+1, the smallest integer a `float` cannot represent, so the
correct answer is the neighbour. pxx returns the input unchanged: the cast did
not narrow at all.

## The boundary — it is the VALUE position, not the cast

Two mechanisms serve one concept, and only one of them converts:

```c
float f1 = (float)u;   /* store through a float lvalue */  -> CORRECT
float f2 = u;          /* implicit, same store          */  -> CORRECT
double d = (float)u;   /* cast as an rvalue             */  -> WRONG
(double)(float)u       /* inline                        */  -> WRONG
printf("%.17g", (float)u);  /* vararg                   */  -> WRONG
```

So the narrowing lives in the assignment path only. Any `(float)` whose result
is consumed as a value — initializer of a wider type, subexpression, argument,
`return` — is a no-op that hands on the double.

**Only integer sources are affected.** `(float)someDouble` in the same
positions is correct, including inline and as a vararg. So it is specifically
int -> float32 that loses its narrowing step; float64 -> float32 keeps it.

## Not the IR, and not the backend

The same conversion in value position is correct from the Pascal frontend —
passing a `LongInt` to a `procedure Show(s: Single)` yields 16777216.0, matching
FPC. The backend can therefore emit the narrowing; the C cast path is simply not
asking for it. That is what puts this in Track C rather than Track A. If the
fix turns out to need a new IR conversion op, file that as a Track A ticket per
the usual rule.

## Why it matters

It is the expensive shape: no crash, no diagnostic, a plausible wrong value that
is only wrong in the low bits — and it is wrong in the direction that makes
`(float)x == x` comparisons and float-keyed logic silently disagree with every
other C compiler. `-Wconversion`-style code that deliberately casts to `float`
to force single precision gets exactly the opposite of what it asked for.

Per `normalise-dont-special-case`: the fix should make the value path use the
same conversion the store path already does, not add a third.

## Gate

C tests green + self-host byte-identical + cross, and
`tools/gcc_diff_probe.sh` back to `0 NEW divergence(s)` on x86-64 (it is at 1
today, this one). Re-run `--target i386` and `--target arm32` too: both are at
0 new / 0 known as of 2026-08-13, so any change there is this fix's doing.
