---
track: A
prio: 45
type: feature
blocked-by: []
summary: "pxx has one no-value variant tag (VT_EMPTY), so VarIsNull and VarIsEmpty are the same question and `v := Null; VarIsEmpty(v)` answers True where FPC says False. variants.pas states the approximation in its header and asks for a ticket rather than a silent guess — this is that ticket. A VT_NULL tag is a compiler change, and decide-variant-tag-space-is-a-language-wide-commitment already settled that the tag space is Track A\'s to renumber freely."
---

# A variant has no NULL tag, so `Null` and `Unassigned` are indistinguishable

- **Type:** feature (a stated approximation, deliberately left open) — Track A
  (the tag lives in the compiler; `lib/rtl/variants.pas` is the Track B half)
- **Status:** backlog
- **Opened:** 2026-08-22, by a 30-program Variant differential against fpc 3.2.2

## Measured

```pascal
v := Null;  WriteLn(VarIsNull(v), ' ', VarIsEmpty(v));
```

| | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `VarIsNull(Null)` | True | True |
| `VarIsEmpty(Null)` | **False** | **True** |

## This is not an oversight — it is a documented request

`lib/rtl/variants.pas`'s header says it in as many words:

> *"FPC additionally distinguishes varNull (1) from varEmpty; pxx has no
> separate NULL tag, so VarIsNull and VarIsEmpty are the same question here and
> both answer 'is it unassigned'. Code that needs a real three-way
> empty/null/value distinction wants a ticket, not a silent approximation."*

So the library did the right thing and stopped at the boundary of what it can
decide. The tag set is the compiler's.

## Why the obvious blocker does not apply

[[decide-variant-tag-space-is-a-language-wide-commitment]] was raised on the
belief that variant tag numbers are a permanent public commitment, and was
**withdrawn** because they are not: FPC compatibility is explicitly disclaimed,
the numbers never matched FPC\'s anyway, and no tag reaches any durable format.
Renumbering is a mechanical refactor over the ~7 files that mention `VT_`. So
adding a tag is Track A\'s ordinary design call, with no escalation needed.

## The part that is bigger than the tag

Adding `VT_NULL` is the easy half. FPC\'s Null **propagates**, and that is the
work:

- `Null + 1` is `Null`, not 1 and not an error; the same for most operators.
- `Null = Null` is *Null* in FPC\'s strict mode and True in its default —
  check which before implementing, and write down which was chosen.
- `VarCompareValue` already has a considered answer for "one side holds no
  value" (`vrNotEqual`, with a comment explaining why it is not "different");
  that reasoning needs revisiting once there are two kinds of no-value.
- `AsText` / `AsNumber` need a Null arm, and `VarToStr(Null)` is defined by FPC
  as the EMPTY STRING rather than an exception — which is the whole reason
  callers prefer it to a cast (see [[bug-b-vartostr-is-missing-from-variants]]).

Do not land the tag without the propagation rules; a `VT_NULL` that behaves like
`VT_EMPTY` everywhere would make the two predicates disagree correctly and
everything else silently wrong, which is worse than today\'s honest
approximation.

## Prio

Low on purpose. Nothing in the corpus needs it today — fpjson, the reason
`variants` exists here at all, does not — and the current behaviour is stated
rather than hidden. Raise it the moment real code branches on
`VarIsNull` vs `VarIsEmpty`.

## Gate

Track A\'s: `make compiler/pascal26` (byte-identical fixedpoint) +
`tools/gate.sh quick`, plus a propagation table diffed against fpc 3.2.2 —
arithmetic, comparison, text conversion and both predicates, for Null and
Unassigned separately.
