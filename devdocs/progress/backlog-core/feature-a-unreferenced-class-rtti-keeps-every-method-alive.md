---
prio: 30
track: A
---

# An unreferenced class keeps every one of its methods alive

- **Type:** feature (codegen / emission size) — Track A, tag O
- **Status:** backlog — opened 2026-08-21
- **Follows:** [[feature-emission-size-dce]] (`--dce`, landed)

## What

`--dce` drops unreachable routine BODIES. It cannot drop a method, because a
method's address sits in a VMT slot (`MethodFixups`) and an address that is
taken can be called from anywhere — so every VMT slot is a root.

The VMT itself is emitted for every class the program declares, used or not. So
a `writeln('hello')` still carries, measured after `--dce`:

```
  953  PXXTIOGetInterface
  663  PXXIntfIMTOf
  555  PXXVarStrAppend
  489  PXXVarClear
  256  TInterfacedObject._Release
  134  TInterfacedObject.QueryInterface
  100  TInterfacedObject._AddRef
   44  TInterfacedObject.Destroy
```

A hello-world uses neither interfaces nor variants. ~3.2 KB of the 15.6 KB that
survives DCE is reachable only through a class nothing instantiates.

## The mechanism

Data-side reachability, one level up from the code-side pass that exists:

1. A class's RTTI blob is reachable if the program constructs it, names it in
   `is`/`as`/a class reference, or a reachable class inherits from it (the
   parent backlink is a real edge — dropping a parent breaks `is`).
2. An unreachable blob's `MethodFixups` entries stop being roots, and the
   existing code-side walk drops the bodies for free.
3. The blob's own bytes go too, which is `.data`, not `.text`.

## Watch out

- `TObject`'s blob is reached from every class — the chain has a root whether
  or not the program mentions it.
- RTTI is what `TypeInfo()`/`ClassName`/published-property access reads at
  RUNTIME with no static reference: anything that can look a class up by NAME
  (a class registry, a streaming/serialisation path) makes every registered
  class reachable, and the pass must see that or refuse.
- Same discipline as `dce.inc`: refuse rather than guess, and say why under
  `--dce-report`.

## Acceptance

`hello` loses the interface/variant residue; no behaviour change on the corpus;
`--dce-report` explains every blob it keeps. Rides the same `-O3` gate, so
`tools/optdiff.sh` sweeps it.
