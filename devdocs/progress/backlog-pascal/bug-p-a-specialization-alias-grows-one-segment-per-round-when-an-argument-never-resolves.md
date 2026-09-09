---
track: P
prio: 60
type: bug
blocked-by: []
status: open
owner: frankS
summary: "The `generics.collections` wall `too many deferred specializations` is a NON-CONVERGING SPECIALIZATION-NAME FIXPOINT, not a missing dedup and not a cap that is too small. Measured 2026-09-09 at binary 5e00cec21466 / bab3814ad with `PXXDBG=p.mint:*`: 872 mints, and the aliases form a strict LADDER — 10 distinct aliases at each of 55 rungs, rung N+1 taking rung N's mangled alias as its argument (`tmpl=TEnumerable args=TEnumerable$TEnumerable$UInt32$PT$PT` -> `alias=TEnumerable$TEnumerable$TEnumerable$UInt32$PT$PT`). The pump is 110 mints, exactly 55 from `TEnumerator` and 55 from `TCustomPointersEnumerator`, whose ALIAS carries more `$PT` segments than its own `args=` does — so the mangled name is not a function of the argument list, and the surplus segment is what the next round reads back. The unresolved argument is `PT`, the class-nested `PT = ^T` of `TEnumerable<T>` used through a DESCENDANT at generics.collections.pas:144/212; it is carried into the name literally instead of resolving, which is [[bug-p-a-class-nested-type-as-a-specialization-argument-resolves-at-unit-scope]] territory — NOT PROVEN to be the same defect, and the discriminator is whether the ladder stops once PT resolves. RAISING `MAX_SPECIALIZATIONS` IS NOT THE FIX AND WAS MEASURED: at 1024 the run reaches `token character pool overflow` with one alias carrying ~120 `TEnumerable$` and ~130 `$PT`. The 256 cap is masking a runaway, and `too many deferred specializations` is the mask, not the defect."
---

# A specialization alias grows one segment per round when an argument never resolves

**Blocks [[feature-pascal-corpus-generics]]** — this is the `uses Generics.Collections`
wall on rung 3, at binary `5e00cec21466` (`bab3814ad`).

## What the instrument says

`PXXDBG=p.mint:*`, driver `uses Generics.Collections`, corpus staged at
`library_candidates/rtl-generics/packages/rtl-generics/src`:

```
mints: 872        aliases carrying an already-mangled name in args=: 650
ladder: 0:109  1:10  2:10  3:10 ... 54:10  55:3     (count of "TEnumerable$" in the alias)
alias has MORE $PT than args=: 110   — 55 tmpl=TEnumerator, 55 tmpl=TCustomPointersEnumerator
all 55 mints of TEnumerator$PT are kind=deferred
```

One rung, verbatim:

```
PXXDBG p.mint deferred alias=TEnumerable$TEnumerable$TEnumerable$UInt32$PT$PT
                        tmpl=TEnumerable args=TEnumerable$TEnumerable$UInt32$PT$PT
```

The argument at rung N+1 *is* the alias minted at rung N. Ten aliases per rung,
55 rungs, and the only thing that stops it is `MAX_SPECIALIZATIONS = 256`.

## Where it starts

`generics.collections.pas`:

```pascal
TEnumerable<T> = class abstract
public type
  PT = ^T;                                   // :131 — class-nested
...
TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>);   // :144
...
  TPointersEnumerator = class(TCustomPointersEnumerator<T, PT>)       // :212
```

At :212 the bare `PT` is the nested type INHERITED from `TEnumerable<T>`. It does
not resolve; it is carried into the mangled name as the literal text `PT`, and
the seed row shows the surplus directly — `alias=TCustomPointersEnumerator$UInt32$PT`
against `args=UInt32`. A name that is not a function of its arguments cannot
dedup against a previous registration, so every round mints rather than matches.

The corpus's own comment above :144 reads `// error: no memory left for
TCustomPointersEnumerator<PT> version` — fpc 3.2.2 nevertheless compiles the file.

## Two things NOT to do

- **Do not raise the cap.** Measured: `MAX_SPECIALIZATIONS = 1024` (binary
  `860aca3da02e`, experiment reverted, not landed) trades the diagnostic for
  `pascal26:30: error: token character pool overflow` with ~120 `TEnumerable$`
  and ~130 `$PT` in one alias. Same runaway, worse readout.
- **Do not add a dedup on the alias string.** It would collapse rung N and rung
  N+1 only if they were the same name, and they are not — by construction.

## Where the fix belongs

Either the mangler must derive the alias from the substituted argument list ONLY
(so a name can never gain a segment its `args=` does not have), or `PT` must
resolve at :212 so the argument list stops carrying an unresolved name. The
second is frankZ's ticket. **The first is testable independently of it** and is
the reason this is filed separately: the 110-row surplus is a property of the
mangler, measurable in one run, and it is what turns an unresolved argument into
a runaway instead of a plain `unknown type`.

**Dead end already paid for:** extending `CollectHoistCandidates` to walk the
ancestor chain (so `PT` is found through `TEnumerable<T>`) HANGS this driver —
>90s, 176 mint lines, then `unknown type: TList$UInt32$PT`. Recorded on frankZ's
ticket too.
