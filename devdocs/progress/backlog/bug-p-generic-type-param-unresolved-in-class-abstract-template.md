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

## 2026-08-30 (coordinator) — RUN THIS BEFORE YOU START: `:120` may be an artefact of the probe

This ticket's title and summary rest on `pascal26:120: error: unknown type: PT`.
**That line is reproducible under one probe and absent under another**, and the
two probes were run by two lanes on the same day against the same file:

| probe | first stop |
| --- | --- |
| **direct** — `pxx generics.collections.pas` (frank-user, HEAD) | `:120` `unknown type: PT`, then `:123`, then `:135` |
| **via `uses`** — `{$mode delphi}` program, `uses Generics.Collections`, `-Fu<rtl-generics/src>` (frank-rust, HEAD `ea5a8ef96`, binary `6319b892f517`) | `:135` `unknown type: TArray`; **`:120` never appears** |

Under the second probe, `TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>)`
resolves `PT` fine. **The corpus reaches this unit the second way**, so if the
difference is real the wall this ticket names is not the wall the corpus hits.

**First command of this ticket, before any diagnosis:** compile
`generics.collections.pas` directly with `{$mode delphi}` forced, and see whether
`:120` survives. A directly-compiled unit does not inherit the mode of a program
that `uses` it, and delphi-mode generic scoping is the obvious candidate for why
`PT` resolves one way and not the other. **That is a hypothesis from the
coordinator, unmeasured, recorded with its falsifier — not a finding.**

- **`:120` disappears** → it is a direct-probe artefact, this ticket is misnamed,
  and the real subject is `:135`: `TArray<T> = array of T` is declared at `:57` of
  the same file, so a generic **array** template fails to resolve where a generic
  **class** template at `:133` succeeds. Retitle rather than re-probe.
- **`:120` survives** → the ticket stands as written, and the two probes have
  found two independent gaps rather than one.

**Do not resolve the discrepancy by picking the number you saw first.** Two
careful lanes measured different walls and neither was wrong; the reconciliation
is in `feature-pascal-corpus-expansion`'s entry for today. State the probe, the
sha and the binary in whatever you write here — a bare line number in a corpus
ticket is a fact about a probe nobody recorded.
