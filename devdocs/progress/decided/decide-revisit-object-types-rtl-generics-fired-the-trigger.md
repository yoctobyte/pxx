---
slug: decide-revisit-object-types-rtl-generics-fired-the-trigger
title: "The `object`-types revisit trigger has fired: rtl-generics needs exactly one, and it needs none of the expensive machinery"
track: U
prio: 70
type: decide
blocked-by: []
status: decided
owner: user
created: 2026-08-30
summary: "decide-old-style-object-types chose option A (do not implement) with an explicit revisit trigger: 'the moment actual source someone wants to build needs it. Not an FPC test — a program.' generics.collections.pas needs it, which blocks rung 6 of feature-pascal-corpus-expansion (prio 75). But the measurement changes the cost case: the corpus contains exactly ONE `= object`, it has no fields, no inheritance, no virtual methods and no constructor, and the equivalent generic record-with-methods compiles and runs on HEAD today. The decision's cost analysis — a second object model with different storage, lifetime, assignment and VMT — does not apply to the thing actually blocking us."
---

> **prio 40 → 70 by the coordinator, 2026-08-30, and the mechanism matters more than the
> number.** This ticket blocks rung 6 of `feature-pascal-corpus-expansion` [P p75] — but the
> block is stated **in the umbrella's prose and not in its frontmatter**, so the ranker's
> dependency propagation (a blocker inherits the priority of what it unblocks) **never fired**.
> A U item sat at 40 in the owner's queue while gating a 75, and nothing in either ticket was
> wrong: the umbrella's Status line says *"parked 2026-08-30 — rung 6 blocked on
> decide-revisit-object-types…"* in plain English, one line above a frontmatter block that says
> only `prio: 75`.
>
> **Raised directly rather than by adding the edge**, deliberately. `blocked-by` on the umbrella
> would remove the whole ladder from `ready`, and only rung 6 is blocked —
> `bug-p-two-different-nested-specializations-of-one-template-collide` [P p65] is explicitly
> independent of this decision. So the edge would buy correct ranking for this ticket by hiding
> several workable rungs, which is a worse trade. **70 rather than 75** because it gates one
> rung, not the ladder.
>
> The general lesson, since this is the third time this umbrella has gone stale on its own prose:
> **a blocking relationship stated in prose has no owner and nothing re-checks it.** `progress.sh
> check`'s STALE-PARK aperture exists for exactly this and reads prose in `unfinished/`,
> `blocked/` and `working/` — it cannot see a prose edge that should have been frontmatter, only
> a prose edge whose named ticket has since closed.


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


# DECIDED 2026-08-30 — owner

## The answer

**Option C, and the rooted-reference `object` is RETIRED rather than kept
alongside it.** `object` gets its standard Object Pascal meaning — a value type,
i.e. a record with callables — with a **hard error** on inheritance, `virtual`,
`constructor` and `destructor` rather than silent half-support. Refiled as a
**Track P bug** (`bug-p-object-value-types-standard-meaning`), not a feature:
per CLAUDE.md's compat table, *"real Pascal source compiles wrong, or not at
all -> bug, own lane, own prio, not compat"*, and `generics.collections.pas` is
real Pascal that does not compile.

Option B is rejected for the reason the owner gave: `object` is not `TObject`
and neither FPC nor Delphi treats it as such. B prices inheritance, VMTs and a
constructor protocol that the corpus does not use and that nothing has asked
for. Option A is rejected because standing pat means shipping a dialect that
rejects ordinary FPC source *because the keyword was spent on something else*.

## Why the keyword was taken — the part neither ticket recorded

Not a sneak, and **not the C frontend** (owner's hypothesis, tested and
disproved: commit `7859911e3` touched only `Makefile`, `parser.inc`, the two
tests and docs; `clexer/cparser/cpreproc` contain no reference to `object`; the
C frontend landed 2026-05-26 and is unrelated). It was a **stopgap that outlived
its gap**:

```
2026-06-16   ticket filed: "a lightweight root, like TObject WITHOUT A UNIT"
2026-06-23   explicit class(TObject) / class(TInterfacedObject) base
2026-07-03   `object` implemented  (7859911e3)
2026-07-12   builtin TObject class — var o: TObject + TObject.Create  (c53dd8953)
```

`RegisterBuiltinTObject` mints the System root at `ParseProgram` start. So the
justification — "without a unit" — was **true when written** and **false nine
days later**, and nothing went back to retire the placeholder. Both commits are
in `parser.inc`.

Three review points let it stand:

1. The ticket's own **Naming caution** asked not to collide with a *future*
   value-`object` feature. It was closed with *"`object` was never a keyword
   here (no legacy value-object support), no grammar collision"* — a fact about
   the present answering a question about the future.
2. **Nobody revisited it when builtin `TObject` landed** and obsoleted the
   entire rationale.
3. The stated consumer never arrived: *"the collections/streams RTL wants
   this"* — usage is still **4 lines, all inside its own two regression tests**,
   seven weeks on. Nothing in `lib/`, `examples/` or `compiler/`.

**General lesson, worth more than this ticket:** a workaround has no expiry date
and nothing re-checks whether the thing it worked around still exists. Same
shape as the prose-blocker edge in this ticket's own header.

## Why retirement is safe — measured, not argued

Substituting `TObject` for `object` throughout `test/test_object_reference.pas`
compiles on the **pinned** stable compiler and produces byte-identical output
and identical code size:

```
TObject version                        object version
code=63287B data=4276B bss=42532B      (same test, unmodified)
Rex: woof / Tom: meow / Rex: woof / Tom: meow / Rex: woof / nil ok / OK   (both)
```

Every use survives: widening assignment from any class, cast-back with virtual
dispatch, `array of`, record field, parameter, `nil` compare. `TObject` is
strictly better — being a real class, it permits `Free`/`ClassName`/`Destroy`
without a cast, where the bare reference required one.

**Residual risk, stated:** the deletion is safe as far as this repo can see (4
uses, all in its own tests). Pascal source *outside* this checkout using
`var x: object` would break. The owner accepted this; the feature is seven weeks
old and its intended RTL consumers never materialised.

## Consequences

- Rung 6 of [[feature-pascal-corpus-expansion]] (p75) unblocks.
- [[feature-p-legacy-value-object-types]] (p15) — its framing assumes option B's
  full scope; it should be rewritten to C's scope or closed in favour of the new
  P bug.
- [[decide-old-style-object-types]] stays decided; its revisit trigger fired and
  this is the revised answer.
