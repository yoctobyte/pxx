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

## 2026-09-05 (frankS) — the "round exhaustion" reading is WRONG; this ticket's own analysis stands

I had this row noted privately as *deferral-round exhaustion rather than a real
cycle detector* — the worry being that `circular generic specialization` is
really "I ran out of rounds", which would mean **deep but acyclic** programs get
refused with a message naming a cycle that does not exist. That would have
refused legal source and moved the rank.

**Measured, and it is not what happens.** A strictly acyclic chain of twelve
generic classes, each naming the next, at `e0e0fb2ae4ed`:

| probe | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `deep_rev` — each names an EARLIER-declared template | **builds**, prints `DEEPOK` | **builds** |
| `deep_fwd` — each names a LATER-declared template | `unknown type: TBox1` | `Identifier not found "TBox1"` |

Two things follow. First, depth alone does not produce the circular message —
twelve levels resolve fine when declaration order allows it, so there is no round
budget being exhausted. Second, the forward case is refused by **FPC too, with
the same meaning**, so pxx is not diverging on ordering at all; `deep_fwd` is
simply not legal in either.

`unknown type` and `circular generic specialization` are therefore **different
paths**, and the circular one fires only on genuine mutual dependency. **The
ticket's own analysis is correct as written and prio 20 is right** — the
diagnostic is honest, it names the real reason, and the change that would accept
the construct is to how specialization is ORDERED (lazy: declare the name, fill
the body on demand), not a repair to the recognizer.

Recorded because the wrong reading was mine and it was the kind that survives:
"the detector is really exhaustion" is a plausible story about a true observation,
and nothing in the ticket contradicts it. The probe that settles it is the one
whose right answer differs from the failure answer — an acyclic chain deep enough
to exhaust a budget, which builds.
