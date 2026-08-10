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

## The diagnostic already exists — it just does not fire on the dangerous case

Found while fixing crtl's `nan()` (2026-08-09). Adding a PARAMLESS Pascal `NaN`
next to C's one-argument `nan(const char *)` produces:

```
warning: C declaration of 'nan' does not match the Pascal routine 'NaN' which
takes 0 parameter(s), not 1 — binding to the C declaration, not the Pascal
routine
```

So the compiler already notices the collision, already knows which side the C
caller meant, and already does the right thing — **when the arities differ.**

Every silent case in this ticket is a SAME-ARITY collision: `Pow(x,y)` against
`pow(double,double)`, `Log(x)` against `log(double)`, `CopySign(x,y)` against
`copysign(double,double)`, `Atan2(y,x)` against `atan2(double,double)`. Same
count, so no warning, and the Pascal routine silently wins.

That narrows the fix considerably: the machinery to detect and correctly resolve
these is present, and the rule it applies on arity mismatch ("bind to the C
declaration, not the Pascal routine") is exactly the rule that should apply
unconditionally for a name declared in a crtl header. Direction 1 below is
therefore mostly a matter of dropping the arity precondition — not new analysis.

## Directions

1. **C resolution should prefer crtl over Pascal units** for any name declared
   in a crtl header — the C program asked for `<math.h>`'s `pow`, so `<math.h>`'s
   `pow` should win, and a Pascal unit should never be consulted for it. This is
   already what happens on an arity mismatch (see above); the precondition is
   the bug.
2. **Or `pxxcio` should not export its dependencies' namespaces into C** — it
   needs `math` for its own bodies, not on behalf of its callers.
3. Failing either, an explicit deny-list is a bad third option: it needs
   maintaining against libc's full name set forever, and gets it wrong silently.

Direction 1 or 2 removes a whole class; the deny-list only postpones it.

## Gate

The probe above matching gcc with `Pow`/`Log`/`CopySign` restored to
`lib/rtl/math.pas`, plus `make lib-test` and the C suites green.

## 2026-08-10 — the fix is written and verified, and BLOCKED on a second bug

Attempted the split the user asked for (crtl owns its math; `pxxcio` drops
`uses math`). It works: the whole libm surface goes byte-identical to gcc,
`isnan(5.5)` stops answering TRUE, and the `--system-libs=c` red (b113) clears.

It cannot land yet. Removing `uses math` triggers
[[bug-c-crtl-auto-pull-depends-on-the-pascal-preludes-unit-count]] — with only
two units in pxxcio's uses clause the crtl auto-pull silently does not fire, so
`stdlib.c` and `string.c` are never emitted and any call into them jumps to
garbage. **Any third unit avoids it**, which is why this has never been seen:
`math` merely happens to be the third one today.

The verified implementation is banked on that ticket. **Do not land the two
halves separately** — adding crtl's four functions while `uses math` remains
makes things worse (two competing definitions; asin/acos/atan2 return NaN).

### Scope note, measured while doing it

Only FOUR names were still crossing the boundary by collision: `ceil`, `floor`,
`sqrt`, `fmod`. Every other crtl module already reaches shared code through
explicitly prefixed `__pxx_*` PAL entry points (100+ of them), and crtl already
defines 64 math functions of its own — the migration away from the Pascal
binding has been happening one incident at a time (`exp` after b377, then
log2/log10, then sin/cos/tan/sinh/cosh/tanh/hypot). Finishing it deliberately
is smaller than the next incident.

### The design rule this belongs to (user, 2026-08-10)

**"Own language first"**: a declaration from the caller's own language beats a
cross-language match, and that outranks import order. Cross-language binding
stays as the FALLBACK — it is the pxx interop feature, and making lookup
case-sensitive was explicitly rejected as defeating it. Companion: *share what
the machine provides, duplicate what the language specifies.*

