---
slug: bug-a-max-template-params-is-4-but-rtl-generics-declares-6
track: A
prio: 60
type: bug
status: done
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

---

# Resolution — raised to **6**, the measured requirement, and the wall moved

**Done, 2026-08-30 by frankA.** Fixedpoint `414252435fb1` (1 round),
`tools/gate.sh quick` GREEN.

## Insufficient, not a runaway — the discrimination the precedent demands

| `MAX_TEMPLATE_PARAMS` | wall | error kind | wall clock |
| --- | --- | --- | --- |
| 4 | `generics.dictionariesh.inc:127` | `too many generic parameters` | 123 s |
| 6 | `generics.collections.pas:**4165**` | unexpected token in implementation | 476 s |

`generics.collections.pas` is **4165 lines long**, so the frontier moved from
line 127 of an *included header* to the **last line of the main unit**, and the
error changed **kind** — a capacity message became a syntax one. That is
`MAX_NESTED_SPECS`'s 24→96 outcome, and it is the opposite of the failure mode
worth fearing here: **if raising a limit moves the failure to exactly the new
limit, the limit was never the constraint** — it is recursion wearing a capacity
error's clothes, which is what happened to the C preprocessor's include-nesting
cap tonight (17 → 128 moved the error from level 17 to level 129; the real cause
was a self-including header, `1672aeaad`). Neither the line nor the message
tracked the constant here.

**The longer wall clock is the compile getting further, not a regression**, as
this ticket warned. 476 s exceeded the 480 s I first allowed by enough to be
killed once; the run that produced the row above had a 2400 s cap.

## Cost — measured off the `ok:` line, three builds at one sha

```
   4   bss=100985812   code=9813784
   6   bss=101027356   code=9813784    +41544 B   +0.041%
   8   bss=101068900   code=9813784    +83088 B   +0.082%
```

Exactly linear at **+20772 B of bss per slot**, and `code` is byte-identical
across all three — the constant is a stride into bss and nothing else.
Cross-checked at a second HEAD after a pull: 6 still reads `bss=101027356`, so
the delta is attributable to the constant rather than to whatever else landed.

## Why 6 and not 8 — and 8 was RUN, not just costed

**Addendum, after the ticket landed as `0fc18aad6`.** The confirming probe at 8
finished and reaches **exactly the same wall**:

```
  6   generics.collections.pas:4165   unexpected token   476.41 s   maxRSS 69208 KB
  8   generics.collections.pas:4165   unexpected token   462.64 s   maxRSS 69460 KB
```

Same file, same line, same message; the 14 s difference is box noise on a host
running three other self-host builds, and it goes the *wrong* way for a
"bigger is slower" story. **So the two extra slots buy nothing today** — not a
line of extra compilation — and the decision below is now a measurement rather
than a judgement call. Had 8 gone further than 6, this ticket would have landed
8 instead, and that is the whole reason the probe was run rather than reasoned
about.

8 was built and costed (above) precisely so the choice is not a preference. It
is not taken: **6 is measured, 8 is two slots bought on a guess** — and the guess
is poorly founded, because this corpus hides its arity behind
`{$DEFINE CUSTOM_DICTIONARY_CONSTRAINTS := TKey, TValue, THashFactory}`, so
"surely 8 is plenty" is exactly the reasoning that sized 4 for `<TKey, TData>`
with slack. When something needs 7, it will say so in one line and the next
person will have this table.

## The next wall names two different files, and whoever reduces it should know

The new error reports `generics.collections.pas:4165` — the unit's `end.` —
while its `near:` window is `(Index: Integer; const S: string`, which does not
occur anywhere in the rtl-generics corpus. It is `lib/rtl/classes.pas:315`
(`procedure Put(Index: Integer; const S: string); virtual; abstract;`), verified
independently by frank-coordinator. **Reducing from that error text reduces the
wrong file.** Not filed from here: it is `lib/rtl/classes.pas`, which frankB
edited tonight, and it may be a recurrence of
`bug-a-the-near-context-window-is-stale-after-a-token-splice` rather than
anything new. Relayed to frankB, who can tell.

## Gate

`make compiler/pascal26` fixedpoint `414252435fb1` + `tools/gate.sh quick`
GREEN + the corpus probe above, re-run at 6.

## Log
- 2026-08-30 — resolved, commit 0fc18aad6.
