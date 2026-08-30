---
slug: bug-a-max-template-params-is-4-but-rtl-generics-declares-6
track: A
prio: 60
type: bug
status: backlog
owner:
blocked-by: []
summary: "MAX_TEMPLATE_PARAMS = 4 (compiler/defs.inc:1818). rtl-generics' TDictionaryEnumerable declares SIX type parameters, so generics.dictionariesh.inc:127 fails with `too many generic parameters (MAX_TEMPLATE_PARAMS)`. This is the CURRENT rtl-generics corpus wall (rung 6b) as of HEAD 4dae78ad9 + the IEnumerable RTL fix -- the whole compile is down to this ONE error. Raising the constant is one line but is NOT free: it is the stride of at least two flat arrays (TemplateParamNames[ti*MAX_TEMPLATE_PARAMS+kk], seenArg[si*MAX_TEMPLATE_PARAMS+k]) plus three locals in pasparser_generic.inc, so measure bss before and after rather than assuming."
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
next person measures rather than assumes. The constant is a **stride**, not just
a bound:

| site | shape |
| --- | --- |
| `pasparser_generic.inc:1235` | `TemplateParamNames[ti * MAX_TEMPLATE_PARAMS + kk]` — flat, global |
| `pasparser_generic.inc:1338` | `seenArg[si * MAX_TEMPLATE_PARAMS + k]` — flat |
| `:1079`, `:1083`, `:1084` | three locals, one sized `MAX_DGEN_TUPLES * MAX_TEMPLATE_PARAMS` |

Doubling 4 -> 8 doubles a `MAX_DGEN_TUPLES * MAX_TEMPLATE_PARAMS` array. **Take
`bss=` off the `ok:` line before and after** — `make compiler/pascal26` prints it
— and put both numbers in the resolve. 6 is the measured requirement; 8 is
headroom that may or may not be worth its bytes, and that is a measurement, not
a preference.

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
