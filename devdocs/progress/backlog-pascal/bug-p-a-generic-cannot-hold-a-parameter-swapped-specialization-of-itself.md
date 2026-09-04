---
slug: bug-p-a-generic-cannot-hold-a-parameter-swapped-specialization-of-itself
track: P
prio: 20
type: bug
status: backlog
blocked-by: []
created: 2026-09-04
found-by: frankB
summary: "`TPair<K, V> = class FSwap: TPair<V, K>; end;` -- a specialization of the same template with its parameters SWAPPED -- is refused with `circular generic specialization: TPair$LongInt$ShortInt requires TPair$ShortInt$LongInt, which requires TPair$LongInt$ShortInt back`. True as stated: pxx specializes by emitting each declaration before its users, and these two need each other. Both surfaces agree since the self-other fix. FPC 3.2.2 also refuses it (differently); real Delphi accepts it. Architectural, not a mis-parse -- the diagnostic is honest and the program does not compile wrong."
---

# A generic cannot hold a parameter-swapped specialization of itself

## Repro

```pascal
type
  TPair<K, V> = class          { and the objfpc spelling, identically }
    FSelf: TPair<K, V>;        { ok }
    FSwap: TPair<V, K>;        { refused }
  end;
var p: TPair<LongInt, ShortInt>;
```

```
pascal26:8: error: circular generic specialization: TPair$LongInt$ShortInt
            requires TPair$ShortInt$LongInt, which requires TPair$LongInt$ShortInt back
```

## Why it is filed at 20 and not higher

**The diagnostic is true and it names the real reason.** pxx specializes by
splicing a concrete declaration into the token stream before anything that uses
it, so a prerequisite must be emitted first — and here each of the two is the
other's prerequisite. Nothing compiles wrong; the program is refused, loudly,
with the cycle spelled out.

A compiler that specialized lazily (declare the name, fill the body on demand)
would take it. That is a change to how specialization is ORDERED, not a bug in
the recognizer, which is why this is not a rung of anything currently open.

Measured 2026-09-04 at binary a25505dd60d9, both surfaces, same message. FPC
3.2.2 refuses it too (`Syntax error, "identifier" expected but ";" found`) — so
this is not FPC compat either; it is Delphi compat, and no corpus we build asks
for it yet.

## Where it came from

Split out of
[[bug-p-a-different-specialization-of-the-same-template-inside-its-own-body]],
which fixed the NON-swapped case (`TOuter<ShortInt>` inside `TOuter<T>`). Before
that fix mode-Delphi answered `expected ':' before '>'` for both, so the two
looked like one defect; afterwards the swapped case reaches the same honest
refusal the objfpc surface always gave it, and the non-swapped one compiles and
runs. Filed so the remaining half is not rediscovered as new.
