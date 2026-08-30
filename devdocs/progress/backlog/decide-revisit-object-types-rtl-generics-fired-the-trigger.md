---
slug: decide-revisit-object-types-rtl-generics-fired-the-trigger
title: "The `object`-types revisit trigger has fired: rtl-generics needs exactly one, and it needs none of the expensive machinery"
track: U
prio: 40
type: decide
blocked-by: []
status: backlog
owner: ""
created: 2026-08-30
summary: "decide-old-style-object-types chose option A (do not implement) with an explicit revisit trigger: 'the moment actual source someone wants to build needs it. Not an FPC test — a program.' generics.collections.pas needs it, which blocks rung 6 of feature-pascal-corpus-expansion (prio 75). But the measurement changes the cost case: the corpus contains exactly ONE `= object`, it has no fields, no inheritance, no virtual methods and no constructor, and the equivalent generic record-with-methods compiles and runs on HEAD today. The decision's cost analysis — a second object model with different storage, lifetime, assignment and VMT — does not apply to the thing actually blocking us."
---

# The `object` revisit trigger fired — with a much smaller bill than the decision priced

[[decide-old-style-object-types]] (in `decided/`, commit `28c19f214`) chose
**option A: do not implement `object` types**, and stated its revisit trigger
unambiguously:

> **Option B, in full, the moment actual source someone wants to build needs it.**
> Not "an FPC test needs it" — a program.

That condition is now met, and this ticket exists because the *terms* of the
revisit also changed. I am not deciding it — filing per "escalate, don't guess".

## What fired it

`generics.collections.pas` (FPC's rtl-generics — rung 6 of
[[feature-pascal-corpus-expansion]], prio **75**) fails to compile:

```
pascal26:146: error: generic templates must be class, record, interface, array
                     or procedure declarations
  near:  T  PT   >>> object strict private
```

`generics.strings` and `generics.defaults` both compile end to end on HEAD;
`generics.collections` is the unit the rung is for, and this is its wall.

## Why the cost case is not the one the decision priced

The decision refused option B on the strength of a real cost:

> Adding a second object model with different storage, different lifetime,
> different assignment semantics and different inheritance …

**The type actually blocking us has none of those.** Measured, `generics.collections.pas:146`:

```pascal
TCustomPointersCollection<T, PT> = object
strict private type
  TLocalEnumerable = TEnumerable<T>;
protected
  function Enumerable: TLocalEnumerable; inline;
public
  function GetEnumerator: TEnumerator<PT>;
end;
```

| decision's cost driver | present here? |
| --- | --- |
| fields / storage layout | **no** — the type has no fields at all |
| inheritance (`object(TParent)`) | **no** |
| `virtual` methods → VMT | **no** |
| constructor / destructor protocol | **no** |
| `new`/`dispose` lifetime | **no** — it is reached by `@`, as `PPointersCollection` |

It is a **stateless, methods-only handle**, used through a pointer to give
`TEnumerableWithPointers<T>` a `Ptr` property.

And the corpus contains **exactly one** `= object` across all six units
(`collections` 1; `strings`, `defaults`, `hashes`, `helpers`,
`memoryexpanders` 0 each), with 7 references to it.

## The equivalent record compiles today

On HEAD, this runs and prints 42:

```pascal
type
  TColl<T> = record
  strict private type
    TLocal = TInner;
  private
    function Inner: TLocal;
  public
    function Get: Integer;
  end;
  PColl = ^TColl<Integer>;
```

So a generic record with methods, a `strict private type` section, and
pointer-to-specialization access are all already supported. The deltas between
that and the corpus's declaration are exactly two:

1. the keyword `object` has no arm in the type-declaration position (it is
   claimed by an unrelated meaning — the rooted object *reference* of
   [[feature-object-reference-type]], `pasparser_decl.inc:492`);
2. `protected`, which records refuse ("records do not inherit") — and which is
   **inert here**, since nothing derives from this type.

## The fork

- **A (stand pat).** Keep option A. Rung 6 stops at `generics.collections`, and
  the corpus campaign either skips the unit or ends there. Cost: zero work, and
  a prio-75 rung stays blocked on one type.
- **B (option B in full, as the decision specified).** Real value-objects:
  layout, VMT, constructor protocol, `SizeOf`, `object abstract`/`sealed`. Track
  A, its own ticket chain. Correct and large, and **the corpus does not need any
  of it**.
- **C (narrow, and NOT the "bad middle" the decision refused).** Accept
  `object` in the type-declaration position and lower a value-object **that has
  no ancestor and no `virtual`/`constructor`/`destructor`** exactly as a
  record-with-methods, permitting `protected` in it; **hard-error** on
  inheritance or `virtual` with a message naming this ticket.

  The decision refused option C as *"accepting the keyword while silently
  refusing `virtual`"* — trading a clean error for a worse one deeper in. That
  objection is precise and it is about **silence**. A version that errors loudly
  on exactly the constructs it does not implement is a different proposal, and
  it is the one shape whose failure mode is a diagnostic rather than a wrong
  program. Whether that distinction is real enough to reverse the refusal is
  the actual question here, and it is the user's.

## Recommendation

**C**, and only if rung 6 is still wanted. It unblocks a prio-75 rung for
something close to the cost of a parser arm plus an access-specifier relaxation,
and it keeps every construct it cannot honour loud. If the answer is that one
type is not worth a second spelling of `record`, then **A** and the corpus
campaign should say out loud that rtl-generics stops at `generics.collections` —
which is a legitimate outcome and better than a rung that silently idles.

I have not implemented anything. `decide-old-style-object-types` stays decided;
this ticket asks whether its trigger, now fired, changes the answer.

## Related

- [[decide-old-style-object-types]] — the standing decision and its trigger
- [[feature-p-legacy-value-object-types]] (p15, `gated-by` the above) — the work
  item, whose framing assumes option B's full scope
- [[feature-pascal-corpus-expansion]] — rung 6, the thing blocked
