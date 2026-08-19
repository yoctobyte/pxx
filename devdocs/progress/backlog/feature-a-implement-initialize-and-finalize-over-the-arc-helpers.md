---
track: A
prio: 50
type: bug
owner: unassigned
blocked-by: []
summary: "RE-TYPED 2026-08-19 feature -> bug: MEASURED against FPC 3.x, `Finalize(s)` on an AnsiString leaves `len=5 [hello]` where FPC prints `len=0 []` — FPC-shaped code compiles, runs, and silently does not do what it says. The fix is unchanged: implement Initialize()/Finalize() over the ARC release helpers pxx already emits at scope exit. Zero in-tree callers, so no regression risk; the helpers already exist, so this is a mapping, not new machinery. Supersedes feature-pascal-initialize-finalize-intrinsics, whose premise is wrong."
---

# Implement `Initialize()` / `Finalize()` over the ARC helpers

**Implements [[decide-finalize-noop-vs-refusal]]** (user, 2026-08-19: *"if a programmer
wants to `Shoot.Foot()` it is able to — that is Pascal design in its purest. So yes,
Finalize should be implemented."*).

**Supersedes [[feature-pascal-initialize-finalize-intrinsics]]**, which asserts the
intrinsics are *missing*. They are not: `Finalize` is parsed, its arguments consumed, and
an empty sequence emitted (`compiler/parser.inc:23122`). Correct or close that ticket.

## What is wrong today

`Finalize(s)` leaves the value **intact** where FPC empties it — a documented v1 shortcut,
not an oversight. Its own comment records the accepted cost: *"a Finalize-reliant container
leaks managed elements until this maps onto the ARC release helpers."*

That is the failure shape the dialect work exists to remove: FPC-shaped code compiles,
runs, and quietly does not do what it says.

## What to build

`Finalize(x[, n])` = **for each managed field of `x`: release the reference, then nil the
field.** That is the *same* operation already emitted at scope exit, driven by a record
layout the compiler already knows — so **map onto the existing ARC release helpers rather
than writing new machinery.** The parser comment names this as the intended route.

`Initialize(x[, n])` = **zero the managed fields into a valid empty state**, without
releasing (the incoming bytes are not references — that is the whole point).

Two properties to preserve, both load-bearing:

- **Finalize nils after releasing, so it is idempotent.** A second `Finalize` on the same
  record decrements nothing. Do not lose this; it removes the obvious footgun.
- **It releases a REFERENCE, not the object.** If the string had refcount 3 because it was
  copied elsewhere, `Finalize` takes it to 2 and the copies stay valid.

## Why these exist at all — the case scope does not cover

Scope-exit cleanup covers variables the compiler declared. It emits nothing for a record
conjured from `GetMem`, which is just bytes to it:

```pascal
p := GetMem(SizeOf(TRec));   { raw bytes — the AnsiString field holds garbage }
Initialize(p^);              { now a valid empty state }
p^.Name := 'hello';          { safe ONLY because the field was nil'd }
Finalize(p^);                { release the string and the dynamic array }
FreeMem(p);
```

Skip `Initialize` and the assignment decrements a refcount through a garbage pointer — the
access violation. Skip `Finalize` and `FreeMem` drops the reference without decrementing —
a leak. Same hazard for `FillChar(rec, SizeOf(rec), 0)` over managed fields, which is the
one that catches careful people because it looks like the obvious "clear this record".

## In-tree beneficiary — do this one as part of the work

`lib/rtl/typinfo.pas:315` does `obj := GetMem(sz)` and then **hand-zeroes the instance**,
with a comment explaining that `GetMem` may hand back reused non-zero heap. That is
`Initialize` written out by hand because the intrinsic was unavailable. Replace it once the
intrinsic works — it is the proof the feature is not hypothetical.

## Risk

**Zero in-tree callers** of either intrinsic (measured 2026-08-19: the single `Finalize`
grep hit is the parser's own definition; `Initialize` has none). So nothing depends on the
current no-op and nothing can regress from implementing it.

## Gate

Track A: `make compiler/pascal26` (the byte-identical self-host fixedpoint) + a repro that
proves a `Finalize`d field is actually emptied and that a copy taken beforehand survives +
`tools/gate.sh quick`.

## Triage 2026-08-19 (Track D re-triage pass, pin v363) — RE-TYPED feature -> bug

Measured against the oracle rather than reasoned about:

```pascal
s := 'hello'; Finalize(s); WriteLn('len=', Length(s), ' [', s, ']');
```

| | output |
| --- | --- |
| pxx, pin v363 | `len=5 [hello]` |
| FPC 3.x (`-Mobjfpc`) | `len=0 []` |

The word in `type:` was the ranking error the re-triage mandate is about:
"feature" reads as optional, and this is a **silent wrong result** in
FPC-shaped code — the exact shape this repo's escape rule promotes to a bug
regardless of how it was filed. Nothing about the *work* changes; only its
class and how it ranks. The scope, the two load-bearing properties
(idempotent, releases a reference not the object) and the zero-in-tree-callers
argument all stand as written.
