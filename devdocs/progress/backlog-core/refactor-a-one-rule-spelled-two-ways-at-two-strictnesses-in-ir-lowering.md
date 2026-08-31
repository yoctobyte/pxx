---
track: A
prio: 40
type: refactor
blocked-by: []
summary: "ir.inc:10426 reads `(CProgramMode or IsNodePChar(dest))` -- one rule expressed two ways at two different strictnesses, with the dialect flag standing in for the property it implies. Normalising it DELETES an entry from the C carve-out inventory rather than moving one, so it makes that refactor smaller."
status: new
owner: ""
---

# One rule spelled two ways at two strictnesses, with a dialect flag standing in for a property

- **Type:** refactor — **Track A** (`compiler/ir.inc`).
- **Found:** 2026-08-29 by frankC during the `cir.inc` carve-out inventory;
  routed here by the coordinator.

## The site

`compiler/ir.inc:10426`:

```pascal
(CProgramMode or IsNodePChar(dest))
```

**One rule, two spellings, two strictnesses.** `CProgramMode` is a *dialect*
flag; `IsNodePChar(dest)` is a *property of the node*. The disjunction says "in
C, always; in Pascal, only when the property holds" — which is either a
deliberate dialect divergence that nothing states, or the dialect flag being
used as a cheap proxy for the property it usually implies.

This is `normalise-dont-special-case` exactly: *"when a construct is reachable
through two shapes, normalise rather than growing a second path — because the
second path is the one that stays broken."*

## Why this one is worth doing before the carve-out

It is the rare case where the refactor makes the *other* refactor smaller.
Normalising this site **deletes** a Class-C entry from the `cir.inc` inventory
(a shared two-armed dialect decision) rather than relocating one. Every other
site in that inventory is work to move; this one is work to remove.

## The question that must be answered first

**Is the divergence intended?** Determine whether a C program can reach this
with `dest` not a PChar and whether the resulting behaviour is correct — i.e.
whether `CProgramMode` is load-bearing here or is standing in for
`IsNodePChar`. If it is a proxy, collapse to the property. If it is a genuine
dialect rule, say so in a comment, because right now the code does not
distinguish the two readings and the next reader will guess.

## Related

`refactor-a-c-exclusive-lowering-has-no-carved-out-file-so-track-c-cannot-be-staffed`
(Class-C entry), and `devdocs/dev/normalise-dont-special-case.md`.
