---
slug: bug-a-max-template-params-is-4-but-rtl-generics-declares-6
track: A
prio: 60
type: bug
status: working
owner: frankA
blocked-by: []
summary: "MAX_TEMPLATE_PARAMS = 4 (compiler/defs.inc:1818). rtl-generics' TDictionaryEnumerable declares SIX type parameters, so generics.dictionariesh.inc:127 fails with `too many generic parameters (MAX_TEMPLATE_PARAMS)`. This is the CURRENT rtl-generics corpus wall (rung 6b) as of HEAD 4dae78ad9 + the IEnumerable RTL fix -- the whole compile is down to this ONE error. Raising the constant is one line but is NOT free: it is the stride of at least two flat arrays (TemplateParamNames[ti*MAX_TEMPLATE_PARAMS+kk], seenArg[si*MAX_TEMPLATE_PARAMS+k]) plus three locals in pasparser_generic.inc, so measure bss before and after rather than assuming. PRECEDENT: MAX_NESTED_SPECS was raised 24->96 for this same corpus (defs.inc:1832) and its comment is the model -- measured trigger, insufficient-vs-runaway, and the cost stated in the same breath; its cost clause is NSpecArg, sized 96*MAX_TEMPLATE_PARAMS, so this change multiplies against that 96."
---

# `MAX_TEMPLATE_PARAMS = 4`, but real generic code declares six

## Measured

Binary `e8cbe7767cc6` (self-host fixedpoint at HEAD `4dae78ad9`), plus the
`IEnumerable<T>`/`IEnumerator<T>` declarations added to `lib/rtl/classes.pas`
by [[bug-b-rtl-provides-no-ienumerable-generic-interface]]. Probe
`program gcprobe; uses Generics.Collections; begin end.` The **entire** output
is one error:

```
pascal26:127: error: too many generic parameters (MAX_TEMPLATE_PARAMS)
  in: .../src/inc/generics.dictionariesh.inc
```

The declaration there is

```pascal
  TDictionaryEnumerable<TDictionaryEnumerator: TObject; TDictionaryPointersEnumerator,
    T, CUSTOM_DICTIONARY_CONSTRAINTS> = class abstract(TEnumerableWithPointers<T>)
```

and `generics.collections.pas:32` is

```pascal
{$DEFINE CUSTOM_DICTIONARY_CONSTRAINTS := TKey, TValue, THashFactory}
```

so the real arity is **6**: `TDictionaryEnumerator`,
`TDictionaryPointersEnumerator`, `T`, `TKey`, `TValue`, `THashFactory`.
`compiler/defs.inc:1818` says `MAX_TEMPLATE_PARAMS = 4`, and its own comment
(`<TKey, TData>`) shows 4 was sized for the two-parameter case with slack, not
against real code.

## Why this is not just `s/4/8/`

Raising it is one line **plus a memory question**, and the ticket exists so the
next person measures rather than assumes. The constant is a **stride**, not a
bound, and `compiler/defs.inc` alone sizes six arrays by it:

| line | array | multiplier |
| --- | --- | --- |
| 1926 | `TemplateParamNames` | `MAX_TEMPLATES *` |
| 1946 | `NSpecArg` | `MAX_NESTED_SPECS *` (**96**) |
| 1949 | `NSpecIns` | `MAX_NESTED_SPECS * (8 + 2*...)` |
| 1963 | `SpecConcreteNames` | `MAX_SPECIALIZATIONS *` |
| 1964 | `SpecConcreteKinds` | `MAX_SPECIALIZATIONS *` |
| 1898/1919-21 | `SpecSub*` | flat, cheap |

plus `seenArg` / `argTok` / `ins` as locals in `pasparser_generic.inc:1079-84`.
So 4 -> 8 does not add four slots; it doubles several arrays whose *other*
dimension is already in the dozens-to-hundreds.

### There is a precedent, and it is the method to copy

`MAX_NESTED_SPECS` at `defs.inc:1832` was raised **24 -> 96 for this exact
corpus**, and its comment is the model answer:

> `was 24 -- MEASURED insufficient: rtl-generics' generics.collections exhausts
> 24 at line 1313 and compiles past it at 96. Not a runaway; raising it moved
> the frontier ~1200 lines further into the unit. Cost is 96 AnsiStrings x2 +
> 96*MAX_TEMPLATE_PARAMS TRawTokens.`

Three things that comment does and this change should do too: it records the
**measured** trigger, it distinguishes *insufficient* from *runaway* (the
frontier moved and then stopped, so the limit was a real bound rather than a
symptom of unbounded recursion), and it states the **cost in the same breath**.
Note its last clause: that array is `NSpecArg`, sized `96 * MAX_TEMPLATE_PARAMS`
— so this change multiplies directly against the 96 that change chose.

**Take `bss=` off the `ok:` line before and after** — `make compiler/pascal26`
prints it — and put both numbers in the resolve. **6 is the measured
requirement; 8 is headroom that may or may not be worth its bytes**, and that is
a measurement, not a preference.

## Probe timing — a success that reads as a hang

The corpus probe went **75s -> 118s** as the two walls before this one fell. That
is the compiler getting *further*, not a hang, and it will get slower again if
this ticket lands and the compile reaches deeper into the unit. Two consequences,
both measured rather than predicted:

- **A 2-minute default timeout truncates a SUCCESSFUL run.** It cost one run
  here, and the truncated output is indistinguishable from a hang. Give it 480s.
- **Do not read a longer run as a regression** while walls are falling. Wall-clock
  on this probe is a function of how far the compile gets, so it moves the wrong
  way on progress.

## Gate

`make compiler/pascal26` (byte-identical self-host fixedpoint) + re-run the
corpus probe above. Per CLAUDE.md that is the whole loop; Track T sweeps breadth.

## Provenance

Found by [[feature-pascal-corpus-expansion]] rung 6b advancing twice in one
session: the `TKey` template-capture overrun (fixed, `28b2851cd`), then
`unknown type: IEnumerable` (fixed as a Track B RTL gap), leaving this. Filed
from Track B rather than fixed there — `compiler/defs.inc` is Track A's.

**Corpus is gitignored**, so "same commit" cannot identify it. Content hash of
`generics.collections.pas`: `5a3402725ab53181...`.
