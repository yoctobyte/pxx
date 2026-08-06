# Sqrt (and friends) need `uses math`, where FPC has them as system intrinsics

- **Type:** compat gap — Track P (Pascal frontend) / Track A (builtins)
- **Status:** done
- **Opened:** 2026-08-04
- **Found by:** `tools/fpc_diff_probe.sh`, `sqr-sqrt` case.
- **prio:** 30

## Symptom

    program q; begin writeln(Sqrt(16.0):0:2); end.

FPC compiles it; pxx says `error: undefined variable`. `Sqrt` lives in
`lib/rtl/math.pas` here and so needs an explicit `uses math`.

**`Sqr` is fine** — it is already a pxx builtin and works with no `uses`. The
two were found together in one probe case, so the failure initially looked like
it covered both; measuring them separately is what separated them.

## Scope — deliberately not just Sqrt

FPC's System unit provides `Sqrt`, `Sin`, `Cos`, `ArcTan`, `Ln`, `Exp`, `Pi`
without any `uses`. Anyone porting real Pascal hits this on the first
maths-using program, and the failure mode is a compile error naming a symbol
that visibly exists, which reads as a compiler bug rather than a missing
import. Worth doing as one batch, not one function at a time.

## Why it is not Track B

Making a name visible without a `uses` is not something `lib/rtl` can do — it
is either a compiler builtin (where `Sqr` already is) or an implicitly-imported
system scope. Filed for the owning lane rather than worked around in the RTL.

## Not a silent-wrong-value bug

Hard compile error, no miscompilation risk. Low priority accordingly.


## Resolved 2026-08-06 — duplicate of `compat-pascal-math-intrinsics-not-in-the-system-unit`

Same gap, filed twice a day apart (this one from the `sqr-sqrt` probe case, the
other from the FPC System-unit surface). The fix landed under the other slug in
`f2ef106e0`: the parser pulls `lib/rtl/math.pas` on demand rather than
redeclaring the functions in builtin, reusing the `textfile` mechanism.

This ticket contributed one thing the other missed — **`Pi`**, which was still
broken after that commit. The on-demand scan requires a following `(`, because
the names are short and `ln` is a plausible variable; `Pi` is paramless and
written bare, so it never matched. Now special-cased, verified against FPC
(`3.14159`), with the size cost recorded in the code: a program with a variable
named `pi` pays ~35KB of unreferenced math. That is size, not correctness — the
variable still shadows the unit's function, which works because of
[[bug-p-program-function-does-not-shadow-used-unit]], fixed the same night.

`Sqr` needed nothing, as this ticket already established: it is a pxx builtin.
Also spot-checked bare and correct: `abs`, `round` (banker's, matching FPC),
`trunc`.

**Resolved:** PENDING-COMMIT

## Log
- 2026-08-06 — resolved, commit PENDING-COMMIT.
