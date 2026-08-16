---
track: C
prio: 50
type: task
blocked-by: []
summary: "Ten functions in lib/crtl/src/math.c are named __crtl_exp/__crtl_log2/... purely to dodge a case-insensitive collision with Pascal's Exp/Log2, reached through #defines in crtl's math.h. Measured 2026-08-14: that collision no longer fires — the Pascal RTL is not in scope for a C program at all. Try de-prefixing them; it may need no compiler change."
status: done
owner: claude-acpn
---

# Retire the `__crtl_*` dodge-prefixes in crtl math

`lib/crtl/src/math.c` defines ten functions under deliberately wrong names, with
the reason in the source:

```c
/* NOT named `exp`: that name collides case-insensitively with Pascal Exp
   (two definitions -> silently broken call binding). C callers reach this
   through `#define exp(x) __crtl_exp(x)` in crtl math.h. */
double __crtl_exp(double x) { ... }
```

`__crtl_exp`, `__crtl_log2`, `__crtl_log10`, `__crtl_sin`, `__crtl_cos`,
`__crtl_tan`, `__crtl_sinh`, `__crtl_cosh`, `__crtl_tanh`, `__crtl_hypot`, plus
the matching `#define`s in `lib/crtl/include/math.h`.

## The collision they dodge no longer fires — measured

`pxxcio.pas` no longer does `uses math` (it is `uses platform, builtinheap`), so
**the Pascal RTL is not in scope for an ordinary C program at all**. Probed
2026-08-14:

- `extern double Power(double, double);` (Pascal-only) does not resolve — the
  compiler warns it will come from the system C library;
- a C body named `exp` with no `<math.h>` macro in the way binds ITSELF. All ten
  spellings do, each measured in its own program.

So the hazard the prefixes exist for appears to be gone, and this may be a pure
deletion.

## Why it is filed separately from the rule

[[feature-a-own-language-first-symbol-resolution]] names de-prefixing these as
its acceptance test. The measurement above says the two are **independent**: the
C-to-Pascal direction is already closed, while the rule is needed for the
Pascal-to-C direction (a Pascal program that `uses './math.c'` loses its own
`Exp` — see that ticket). Blocking a cheap cleanup behind a large resolution
change would be wrong, hence this ticket.

If de-prefixing turns out to fail, that failure is evidence FOR the rule and
belongs back on that ticket — say so there rather than re-prefixing silently.

## Work

1. De-prefix the ten in `lib/crtl/src/math.c`; delete the ten `#define`s in
   `lib/crtl/include/math.h` (keep the `NAN` one — different mechanism).
2. Check nothing else references the old names (`grep -rn __crtl_` across
   `lib/crtl` and `test/`).
3. Run the C corpus. A silent binding change is the failure mode, so compare
   RESULTS, not just exit codes — `tools/gcc_diff_probe.sh` is the instrument for
   the math ones.

## Also — three stale docs, same visit

- `devdocs/dev/c-linking-and-crtl-autopull.md` still describes math.c's
  `sqrt`/`sin`/`pow` as "a thin bridge to the Pascal RTL". Stale — they have real
  double-double C bodies now (`math.c:959` etc.).
- `lib/crtl/README.md` and `lib/crtl/src/README.md` both still say `src/` is
  *"reserved for the matching implementations once real candidates need them"*.
  It holds a 114-function correctly-rounded libm, `stdio`, `string`, and more.

Background for all of it: `devdocs/dev/math-implemented-twice.md`.

## Gate

C tests green, the corpus unchanged in OUTPUT (not merely in exit status), plus
self-host byte-identical since nothing in `compiler/**` should move.

## Done 2026-08-16 — a pure deletion, and the feared case measured

All ten de-prefixed; the ten `#define`s deleted from `lib/crtl/include/math.h`
(the `NAN` union kept — different mechanism). No compiler change was needed, as
the ticket predicted.

**The one thing worth recording is the case the source comment kept them alive
for.** `lib/crtl/src/math.c`'s header said the prefixes "must stay" because
*"while pxxcio no longer imports math, a user program that does `uses math`
itself would resurrect exactly that"*. That is a testable claim and it is false:

```pascal
program mixed;
uses math, './cm.c';        { BOTH an `exp` and an `Exp` are visible }
begin
  writeln(cexp2x(1.0):0:15);   { the C exp  -> 2.718281828459045 }
  writeln(Exp(1.0):0:15);      { the Pascal -> 2.718281828459045 }
end.
```

Both sides answer correctly. So the collision is closed in the C-to-Pascal
direction by pxxcio dropping `uses math`, not merely hidden by the prefixes.

**Verified by RESULTS, not exit codes**, since a silent binding change is the
failure mode: `gcc_diff_probe.sh` at 0 NEW divergences on x86-64, and all
eighteen `cmath_*` tests plus `crtl_trig_huge` pass — including the four
correctly-rounded suites whose expectations are 80-digit decimal references, so
a wrongly-bound call could not pass them by luck.

Test files and the three docs that described the dodge (`lib/crtl/src/README.md`,
`devdocs/dev/math-implemented-twice.md`, the `math.c` header) are updated with
the change rather than left to rot, and each says what to do if it regresses:
record it on [[feature-a-own-language-first-symbol-resolution]], do not
re-prefix silently. That ticket is unaffected — it is needed for the
Pascal-to-C direction, which is still open.

## Log
- 2026-08-16 — resolved, commit PENDING-COMMIT.
