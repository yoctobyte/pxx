---
track: C
prio: 55
type: bug
summary: "pxxcio is auto-pulled into EVERY C program and does `uses math`, so every name in lib/rtl/math.pas is in scope for C name resolution — adding a Pascal `Pow` made a C program's pow(2,10) answer 1 instead of 1024, and `CopySign` made copysign(3,-1) answer atan2's result"
---

# A Pascal RTL name can hijack a libc function in every C program

- **Type:** bug (silent wrong answer) — Track C / A (C name resolution)
- **Opened:** 2026-08-09
- **Found by:** Track B, adding the Python `math` surface to `lib/rtl/math.pas`
  for [[feature-rtl-math-surface-gaps]]. `make lib-test` went RED on
  `cscanf_math`, a C test that had nothing to do with the change.

## Measured

`test/cscanf_math.c` and a purpose-built probe, gcc as the oracle:

| call | gcc | pxx, after adding `Pow`/`Log`/`CopySign` to lib/rtl/math.pas |
| --- | --- | --- |
| `pow(2.0, 10.0)` | `1024` | **`1`** |
| `pow(2.0, 0.5)` | `1.41421` | **`1`** |
| `log(4.0)` | `1.386294361` | **`1.098612289`** |
| `copysign(3.0, -1.0)` | `-3` | **`0.785398`** — that is `atan2(1,1)` |
| `atan2(0.5, 1.0)` | `0.463647609` | **`0.785398163`** — that is `atan2(1,1)` |
| `isnan`, `isinf`, `nan`, `log10`, `log2`, `exp`, `sqrt`, `hypot`, `fmod` | | all still correct |

No warning, no error. The C program compiles and prints wrong numbers.

**`atan2` shipped broken for one commit** before this was caught, and the way it
escaped is worth recording: the first canary written for this bug checked only
`atan2(1.0, 1.0)`, whose arguments are SYMMETRIC and whose answer (pi/4) is also
`atan(1)` — so a hijacked, argument-swapped or argument-ignoring `atan2` passes
it. `test/cmath_trig_family_b385.c` (in `make test`, not `lib-test`) caught it,
which is Track T's whole purpose. The canary now uses asymmetric arguments.
A test for a substitution bug must use inputs whose answers DIFFER under the
substitution — a degenerate input tests nothing.

## The mechanism

`lib/rtl/pxxcio.pas` is auto-pulled into **every** C program (`ParseCProgram`,
the same way the Pascal driver pulls `builtin`/`textfile`), and its uses clause
is:

    uses platform, builtinheap, math;

So the whole Pascal `math` unit is in scope for C name resolution in every C
program ever compiled, and resolution is case-insensitive. Any name added to
that unit can therefore shadow a libc function of the same name.

This is not a new hazard, it is a known one that was worked around rather than
fixed — `lib/crtl/src/math.c` says so in its own comment:

> NOT named log2/log10: those collide case-insensitively with Pascal Log2/Log10
> (same silently-broken binding as exp/Exp, b377) — C callers come through the
> math.h function-like macros.

crtl protected ITSELF by renaming its functions `__crtl_log2` / `__crtl_log10`.
Nothing protects the other direction: the Pascal RTL has no idea it is
publishing into C's namespace, and `lib/rtl/math.pas` is a file Track B edits
routinely.

## Why the priority is not low

The failure mode is a **silent wrong answer in unrelated code**, which is this
project's worst class, and the trigger is an ordinary, correct-looking Track B
edit. It fired the same day it was possible to fire. Every future RTL addition
is a coin flip against libc's name list until this is fixed.

Track B's workaround for now is to simply not add those names, which costs
`math.pow`, `math.log` and `math.copysign` in NilPy
([[bug-n-math-trunc-and-log-need-frontend-intercepts]] carries them as
frontend intercepts instead) — a real feature loss to dodge a resolution bug.

## Directions

1. **C resolution should prefer crtl over Pascal units** for any name declared
   in a crtl header — the C program asked for `<math.h>`'s `pow`, so `<math.h>`'s
   `pow` should win, and a Pascal unit should never be consulted for it.
2. **Or `pxxcio` should not export its dependencies' namespaces into C** — it
   needs `math` for its own bodies, not on behalf of its callers.
3. Failing either, an explicit deny-list is a bad third option: it needs
   maintaining against libc's full name set forever, and gets it wrong silently.

Direction 1 or 2 removes a whole class; the deny-list only postpones it.

## Gate

The probe above matching gcc with `Pow`/`Log`/`CopySign` restored to
`lib/rtl/math.pas`, plus `make lib-test` and the C suites green.
