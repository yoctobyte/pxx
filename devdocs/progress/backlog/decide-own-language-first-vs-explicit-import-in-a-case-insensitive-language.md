---
track: U
prio: 60
type: decide
blocked-by: []
summary: "Own-language-first was decided with explicit import as its safety valve — 'nothing becomes unreachable, it just has to be asked for by name'. Measured: in Pascal there IS no distinct name to ask with, because Pascal is case-insensitive, so `uses './math.c'` does not ADD `exp` alongside `Exp`, it REPLACES it. The rule cannot be both a hard precedence and overridable by explicit import. Pick which gives."
---

# Own-language-first vs explicit import, when the language is case-insensitive

[[feature-a-own-language-first-symbol-resolution]] was decided on a model with
two halves:

> Implicit resolution prefers your own language; **explicit import overrides
> it.** Nothing becomes unreachable — it just has to be asked for by name.

The second half does not hold for Pascal, and the reason is structural rather
than a resolver defect.

## Measured 2026-08-14

```c
/* cm.c */  double exp(double x) { return 42.0; }
```
```pascal
program pm; uses math, './cm.c';
begin WriteLn(Exp(1.0):0:4); end.          { 42.0000 — the C body }
```

Order-independent. And the control that settles what it means — the same shape
with a *Pascal* unit rather than a C file:

| | `uses math, pexp` where pexp declares `Exp` | verdict |
| --- | --- | --- |
| pxx | `42.0000` | |
| FPC | `42.0000` | **pxx already matches the reference** |

So there is no cross-language defect underneath this. A used unit's routine
shadows a built-in; that is ordinary Pascal and FPC does it too. `uses './cm.c'`
imports the C file AS A UNIT and its `exp` shadows the intrinsic `Exp`
case-insensitively, exactly as a Pascal unit's would.

## The fork

**Pascal is case-insensitive, so a Pascal program cannot spell the difference
between its own `Exp` and an imported C `exp`.** Importing therefore REPLACES
rather than ADDS. "Ask for it by name" has no name to offer.

**Option A — hard precedence (the rule as decided).** `Exp` always resolves to
Pascal's. An imported C `exp` becomes unreachable from Pascal by an ordinary
call, so the promised override does not exist unless a spelling is added for it
(qualified `cm.exp(...)`, an `as` alias on the uses clause, something).
*Cost:* a new spelling to design and implement, or a genuine loss of capability.
*Benefit:* a Pascal program cannot lose its own standard library to a file it
imported for one function — which is the whole point of the rule.

**Option B — explicit import wins (today's behaviour).** Consistent with FPC's
unit-shadows-builtin rule, needs no new syntax, and the exposure is limited to a
file the programmer explicitly named — a much smaller blast radius than the
original `bug-c-pascal-math-names-hijack-libc-through-pxxcio`, which hit EVERY C
program with no opt-in at all. *Cost:* `uses './math.c'` silently redefines six
intrinsics, and nothing warns.

**Option C — B plus a diagnostic.** Keep the shadowing, but WARN when an
imported unit of another language captures a name the current language already
defines. Cheap, loses no capability, and turns a silent replacement into a
visible one. Composes with A later.

## Recommendation: C now, A later if it still matters

The measured facts favour it. The dangerous version of this bug — every C
program silently inheriting Pascal's math — is already gone, and what is left
requires the programmer to explicitly name a foreign file. That is a warning's
job, not a precedence rule's. C is small, breaks nothing, and buys the visibility
that was missing when this class of bug cost days.

A is still the right end state if mixed Pascal+C sources become common, but it
needs the override spelling designed first, and that is worth doing on evidence
of real use rather than ahead of it.

## Note on scope

This fork is about the PASCAL side. The C -> Pascal direction is closed
(measured: the Pascal RTL is not in scope for a C program at all since `pxxcio`
dropped `uses math`), and retiring the ten `__crtl_*` dodge-prefixes is
independent of whatever is decided here —
[[task-c-retire-the-crtl-name-dodge-prefixes]].

NilPy is untested for this and should be checked before A is built: `.npy`
imports resolve `.py` first, but the same "cannot spell the difference" question
may or may not arise there.
