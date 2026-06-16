# Interfaces

- **Type:** feature
- **Status:** backlog (deprioritized — bottom of the list)
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §3 — intentionally deferred)

## Priority note (2026-06-16)

**Deprioritized to last by project owner.** Interfaces are largely a COM-era
binary-contract mechanism — cross-application/cross-binary ABI stability (Windows
COM, OLE). PXX targets **standalone, all-in-one-binary applications** with no
cross-binary contracts, so that primary value does not apply here. The secondary
value (inheritance-free polymorphic abstraction + ARC lifetime) is adequately
covered by classes, abstract methods, and the proposed `object` reference type
(feature-object-reference-type). Revisit only if a concrete external-compatibility
target (e.g. a real COM/OLE interop need) ever forces it. Until then: last.

## Motivation (original)

A real language gap, but not active: no current target source requires
interfaces, and even a lightweight Linux-native model adds substantial dispatch,
ABI, and lifetime surface. Ordered **after** the LFM arc (reuses its class
registry / RTTI) if ever taken up.

## Decisions to lock first

- Refcount model: start **CORBA-style / no-refcount** (pure dispatch); defer
  COM-style ARC (`_AddRef`/`_Release` + `try/finally` injection) — the hard part.
- Root type: whether to require `IInterface`/`IUnknown`; corba can omit.
- GUIDs: parse `['{...}']`, ignore initially.

## Mechanism (the work)

1. Parse `IFoo = interface [guid] <signatures> end;`.
2. Class implements: bind each interface method to a class method by name+sig.
3. Per-(class,interface) Interface Method Table (IMT), distinct from VMT. Choose
   representation: Delphi-style hidden field + Self-adjusting thunks, **or** fat
   pointer `{IMT, instance}`. Document the choice.
4. Interface-typed variable storage + class→interface assignment + call slot[k].
5. `is`/`as`/`Supports` via the class registry.
6. Operators: assign, identity `=`/`<>`, params, results.

Synergy: Self-adjusting IMT thunks suit the new inline asm or a small IR op.
Out of scope: `implements` delegation, interface inheritance depth, method
resolution clauses, COM ARC.

## Acceptance

`IFoo`/class-implements/interface-call/`is`/`as`/`Supports` covered by tests;
self-host fixedpoint holds.

## Log
- 2026-06-06 — ticket opened from todo.md §3.
