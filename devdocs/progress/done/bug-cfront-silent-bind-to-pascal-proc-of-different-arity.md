---
track: A
prio: 30
type: bug
status: done
owner: claude-AC
---

# A C call binds to a Pascal routine of a DIFFERENT arity, silently

cfront resolves an undeclared-or-extern C function name through `FindProc`,
which spans the C and Pascal namespaces **case-insensitively**. That is
deliberate and useful — lua's `<math.h>` `sqrt`/`sin`/`cos` bind to the RTL's
Pascal `Sqrt`/`Sin`/`Cos`, which is how a C corpus gets a math library at all.

There is no check that the two agree on anything. When they do not, the call is
compiled anyway and the failure is a crash somewhere else entirely:

- `time(NULL)` in a C unit bound to sysutils' `function Time: TDateTime` — no
  parameters, Double result — the moment the program also used sysutils
  ([[bug-c-unit-crashes-when-sysutils-is-used]]; the crash looked like a heap
  bug in third-party C for weeks);
- the same shape produced `exp(x) = e^(previous result)` in b377, because the
  argument never arrived.

Both were found only by disassembling. A one-line arity comparison would have
named either in seconds.

## RUNG 1 LANDED @ e63a59747 (2026-07-28) — this ticket is now rung 2 only

`WarnCrossNamespaceArity` (cparser.inc) is in place at BOTH bind sites: the C
declaration path and the undeclared-CALL path (the dangerous one — a `.c` that
calls `time()` without including `<time.h>` still binds the Pascal routine).
C-declared and variadic procs are skipped; the warning honours `-Werror`:

```
warning: C call to 'time' binds to the Pascal routine 'Time' which takes
0 parameter(s), not 1 — the argument list will not arrive as written
```

So the multi-week-hunt hazard is closed: a mismatched bind now names itself at
compile time. Prio drops 70 → 30 accordingly — what remains is hardening, not a
live silent-crash risk. (Found stale at the top of the global queue on
2026-07-29; the fix had landed the day before without the ticket being moved.)

**The evidence rung 2 was waiting for already exists.** e63a59747 measured the
whole C suite — 220/220 c-conformance plus lua, sqlite, quickjs, tcc and zlib —
and got **ZERO warnings**. No corpus needs a mismatched bind, so the escalation
below is unblocked; it just needs doing and re-measuring.

## What to do (original, rung 1 now done)

At the bind site in `cparser.inc` (the `procIdx := FindProc(name)` fallback,
around the `forceSystemExternal` block), when the found proc is a PASCAL proc
(not `ProcCdecl`) and its `ParamCount` differs from the C declaration's, either

1. **warn** — cheap, keeps every current binding working, and turns a
   multi-week hunt into a compile-time line; or
2. **do not bind** — register the C name as its own proc, so an unresolved
   extern surfaces at link time instead.

(1) first, since it cannot break a corpus. Measure how many hits the existing
corpora produce; if the answer is zero or all-genuine, escalate to (2).

A type-compatibility check on the parameters is the obvious next rung, but
arity alone catches both bugs seen so far.

## Known collision surface

Cross-namespace names that exist on BOTH sides today (crtl headers vs
`lib/rtl/*.pas` globals), collected mechanically:

```
abs ceil close copy cos cosh exp floor fmod gethostbyname htonl htons hypot
isspace log10 log2 mkdir ntohl ntohs open poll read remove sin sinh sqrt
strcat strlen tan tanh write
```

Some are intentional (the math family, already routed through `__crtl_` macros
where the convention differs), some are harmless (Pascal METHODS do not
collide — only globals do), and some are latent copies of the `time` bug.
The diagnostic above is what tells them apart without auditing the list by hand.

## RUNG 2 LANDED (2026-08-03) — the bind is now REFUSED, not just warned

Escalated to option (2) on the evidence this ticket already recorded (zero
warnings across the whole C suite, so no corpus needs a mismatched bind), plus a
fresh measurement from the sibling
[[bug-cfront-c-name-binds-to-pascal-routine-at-wrong-arity]]: a mixed Pascal+C
build calling `time(&now)` without `<time.h>` returned 0 where gcc returns 1 —
the out-parameter was never written, so the caller read uninitialised memory
behind a plausible return value. The warning was right; the binding was not
harmless.

`WarnCrossNamespaceArity` became the predicate `CCrossNamespaceArityMismatch`,
and the two bind sites act on it:

- **C declaration path** — drop the Pascal twin, register the C name as its own
  cdecl proc, so the C declaration is what gets called (warns; the message now
  says what happened rather than predicting breakage).
- **Undeclared-call path** — refuse with an error naming both routines and the
  fix, since there is no C declaration there to prefer.

Same arity still binds, so the intentional cross-namespace routing (lua's
`<math.h>` `sqrt`/`sin`/`cos` → the RTL's Pascal `Sqrt`/`Sin`/`Cos`) is
untouched. Pinned by `test/test_c_cross_ns_arity{,_fail}.pas` + their `.c` units.

The parameter TYPE-compatibility check named as "the obvious next rung" is still
open, and so is the collision surface list above — arity alone catches every
case seen so far.

## RUNG 3 LANDED (2026-08-03) — the parameter TYPE check, scoped to float-class

The "obvious next rung" named at the top of this ticket, done the same way
rungs 1 and 2 were: implement as a warning, MEASURE the corpora, then escalate.

**Scope: float vs non-float only**, on each parameter and on the result. That is
the class which picks the register file — XMM vs general-purpose on x86-64 — and
with it the whole marshalling path, so a disagreement there cannot produce a
right answer. It is exactly the b377 shape (`exp(x)` returning e^(previous
result)). **int-vs-pointer is deliberately NOT checked**: both travel the GP
path and the corpora interchange them constantly, so checking it would be the
"crying wolf on every mixed build" failure this ticket warned about.

Measured with the check as a warning:

| corpus | float-class warnings |
| --- | --- |
| zlib | 0 |
| lua | 0 |
| quickjs | 0 |
| c-conformance (220 cases) | 0 |
| the C suite | 0 |

Zero everywhere — the same evidence bar that unblocked rung 2 — so it escalated
to refusing the bind: the C declaration wins and registers its own cdecl proc,
identical to the arity path. Verified firing on the b377 shape (`int exp(int)`
against the RTL's `function Exp(x: Double): Double`).

Note the intentional cross-namespace routing is untouched, because it AGREES on
float-ness: lua's `<math.h>` `sqrt`/`sin`/`cos` are `double(double)` and the RTL's
`Sqrt`/`Sin`/`Cos` are `Double`→`Double`.

**Still open:** width mismatches (`long` vs `Integer`) and int-vs-pointer, both
deliberately out of scope above; and the collision-surface list earlier in this
ticket has not been audited by hand — the diagnostics are what make that
unnecessary.

## Log
- 2026-08-03 — resolved, commit 0fa768c5d.
