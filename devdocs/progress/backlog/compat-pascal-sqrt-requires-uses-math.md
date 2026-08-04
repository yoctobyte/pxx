# Sqrt (and friends) need `uses math`, where FPC has them as system intrinsics

- **Type:** compat gap — Track P (Pascal frontend) / Track A (builtins)
- **Status:** backlog
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
