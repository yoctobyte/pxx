---
slug: bug-p-a-property-in-an-interface-declaration-is-rejected
track: P
prio: 45
type: bug
status: backlog
owner:
blocked-by: []
summary: "`property Current: T read GetCurrent;` inside an `interface` declaration is rejected -- `expected 'end' before 'property'`. FPC's IEnumerator (rtl/objpas/objpas.pp:79) declares exactly that, so lib/rtl's IEnumerator had to ship WITHOUT it. Generic or not makes no difference; mode DELPHI and mode PXX both fail. THE TRAP: an UNINSTANTIATED generic interface carrying a property compiles clean, because its body is never parsed -- so the obvious quick check returns a FALSE GREEN and you must instantiate to see the failure. Control included (+1 proc) proving the instantiating probe really generated code."
---

# A `property` inside an `interface` declaration is rejected

## Measured

Binary `e8cbe7767cc6` (self-host fixedpoint at HEAD `4dae78ad9`). Five probes,
pass/fail read off the **exit code** — note that pxx prints its success line
`ok: ... [code=... procs=N]` on stdout, so "produced output" is not a failure
test and a harness that treats it as one reports every probe as FAIL:

| probe | interface | property? | instantiated? | result |
| --- | --- | --- | --- | --- |
| a | non-generic | yes | — | **FAIL** `pascal26:6: expected 'end' before 'property'` |
| b | generic | no | no | ok, 129 procs |
| c | generic | **yes** | no | **ok, 129 procs — VACUOUS** |
| d | generic | yes | **yes** | **FAIL** `pascal26:6: expected 'end' before '.'` |
| e | generic | no | yes | ok, **130 procs** |

`a` is the plain statement of the bug: nothing generic is involved.

## The trap, which is the reason this ticket is worth its length

**`c` is a false green.** A generic interface whose body is never instantiated is
buffered as tokens and never parsed, so a property inside it is never seen. The
natural way to check "does pxx accept a property on an interface?" is to declare
one and compile — and that answers **yes**, incorrectly.

`e` is the control that makes `d` a claim rather than an impression: 129 -> **130
procs** shows the instantiation in the `d`-shaped probe genuinely generated code,
so `d`'s failure is the property and not a probe that quietly did nothing. This
is the same non-vacuity discipline [[feature-pascal-corpus-expansion]] uses for
rung 6a (+11 procs), and it is needed for exactly the same reason.

Note also that `d`'s message differs from `a`'s (`before '.'` vs `before
'property'`) while pointing at the same line 6 — the property line. Do not treat
the two messages as two bugs.

## Impact

Low-to-moderate, and honestly bounded: **nothing is blocked on it right now.**
`lib/rtl/classes.pas` ships `IEnumerator<T>` without FPC's
`property Current: T read GetCurrent;` and the rtl-generics corpus does not care,
because it never references `IEnumerator` at all — it uses only
`IEnumerable<T>`, six times, all as `AddRange` parameter types. Callers write
`GetCurrent` instead of `.Current`. It becomes real when someone wants `for..in`
over an interface-typed enumerable, or FPC-parity source that reads `.Current`
off an interface.

## Gate

`make compiler/pascal26` + probes `a` and `d` above compiling clean, with `e`
re-run to confirm the control still holds.

## Provenance

Flagged as an unknown by [[bug-b-rtl-provides-no-ienumerable-generic-interface]]
("`property ... read` on an interface is the one shape that should be checked
rather than assumed") and confirmed by measuring it. The flag was right.
