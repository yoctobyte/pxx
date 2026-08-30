---
slug: bug-p-a-different-specialization-of-the-same-template-inside-its-own-body
track: P
prio: 35
type: bug
blocked-by: []
status: open
created: 2026-08-30
summary: "`TOuter<T> = class FOther: TOuter<ShortInt>; end;` -- a reference to a DIFFERENT specialization of the SAME template, from inside that template's own body -- does not compile. A different TEMPLATE's specialization in the same position is fine, and same-template-same-args was fixed by bug-p-a-nested-class-naming-its-enclosing-template-is-substituted-twice. Pre-existing: fails identically on pinned."
---

# P: a different specialization of the same template, inside its own body

## The three cases, and only this one is broken

```pascal
type
  TBox<T>   = class V: T; end;
  TOuter<T> = class
    V: T;
    FBox:   TBox<ShortInt>;     { different TEMPLATE          -> ok, runs }
    FSelf:  TOuter<T>;          { same template, same args    -> ok, runs (fixed) }
    FOther: TOuter<ShortInt>;   { same template, DIFFERENT args -> FAILS }
  end;
```

Two-parameter form fails the same way when the arguments are reordered, which is
the same thing said differently — `TPair<V, K>` inside `TPair<K, V>` is a
different specialization:

```pascal
  TPair<K, V> = class
    FSelf: TPair<K, V>;     { ok }
    FSwap: TPair<V, K>;     { FAILS }
  end;
```

## Pre-existing, and NOT the double-substitution bug

Verified against `pinned` (sha256 `abece5150983d95e`) as well as HEAD: both fail,
with the same error on the single-parameter case.

It is specifically **not** the defect fixed in
[[bug-p-a-nested-class-naming-its-enclosing-template-is-substituted-twice]] —
neither shape produces that ticket's `TOuter$LongInt  LongInt` signature. The
order-matching guard added there deliberately declines to collapse these, which
is correct: they denote a different specialization and must keep their argument
list. They then fail further along, for this older reason.

Reported as the negative-case half of that ticket's sibling sweep: the fix was
checked from both sides, and this is what the other side turned up.

## Where to look

Almost certainly the nested-specialization PREREQUISITE path rather than
substitution — `TOuter<ShortInt>` needs its own specialization emitted before
`TOuter<LongInt>`'s body can refer to it, and the emitting template is the one
being specialized. `ParseSpecialization`'s prerequisite scan and
`NestedSpecKnown` are the places to start.

## Priority

Low: the shape is legal and real but uncommon (a container holding a differently
parameterised instance of itself), and it fails loudly at compile time rather
than silently producing a wrong value. Filed so it is not rediscovered as new.
