---
slug: bug-p-generic-type-param-unresolved-in-class-abstract-template
track: P
prio: 70
type: bug
blocked-by: []
status: open
created: 2026-08-30
summary: "A generic template's own type parameter is not in scope inside a `class abstract(...)` body: generics.collections' TCustomPointersEnumerator<T, PT> reports `unknown type: PT` for its own PT. This is the wall the rtl-generics corpus hits now that bug-p-object-value-types-standard-meaning cleared the one 26 lines later that used to abort the parse first."
---

# P: a generic type parameter is unresolved inside a `class abstract` template

## Repro

From `library_candidates/rtl-generics/packages/rtl-generics/src`, with a
one-line program that only does `uses Generics.Collections`:

```
pascal26:120: error: unknown type: PT
  in: generics.collections.pas
  near: class abstract protected function DoGetCurrent  >>> PT  virtual
pascal26:123: error: unknown type: PT
  near: abstract  public property Current  >>> PT read DoGetCurrent
pascal26:135: error: unknown type: TArray
  near:  ACount  SizeInt   >>> TArray  UInt32
pascal26:135: error: unexpected token
```

The declaration at :120 is:

```pascal
TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>)
protected
  function DoGetCurrent: PT; virtual; abstract;   { <-- PT unknown here }
public
  property Current: PT read DoGetCurrent;
end;
```

`PT` is the template's OWN second type parameter. It resolves in the ancestor
clause (`TEnumerator<PT>` is accepted) and not in the member bodies.

## Why it surfaced only now

It did not regress; it was unreachable. `pinned` aborts at :146 on
`TCustomPointersCollection<T, PT> = object`, a *syntactic* error 26 lines
LATER, and the parse stops there before any specialization is streamed — so
these semantic errors, which are reported against the template's own line
numbers when the specialization is instantiated, never got a chance to fire.
Clearing :146 (`bug-p-object-value-types-standard-meaning`, this session) makes
:120 the live wall.

That ordering is worth keeping in mind for the corpus generally: an *earlier*
line number in the error output does not mean an earlier failure, and "the wall
moved backwards" is the expected shape after a syntax fix, not a regression.

## Scope

Two distinct-looking symptoms, possibly one cause — establish which before
fixing (root-cause-over-microfix):

1. `PT` unknown in member signatures / property types of the template body;
2. `TArray` unknown at :135, inside `class procedure` parameters — `TArray<T>`
   is itself a generic alias, so this may be the same scope gap one level up
   rather than a second bug.

Vary the shape first: does a two-parameter `class` (not `abstract`) template see
its second parameter? Does a one-parameter one? Is it `abstract` that matters, is
it the second parameter specifically, or is it any parameter used in a member
whose ancestor clause also mentions it?

## Consequences

- This is the current blocker for rung 6 of [[feature-pascal-corpus-expansion]]
  (p75); it inherits that priority, which is why this sits at 70.
- Filed from [[bug-p-object-value-types-standard-meaning]], which cleared the
  previous wall and whose before/after measurement is in its commit.
