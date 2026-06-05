# Interfaces

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §3 — intentionally deferred)

## Motivation

A real language gap, but not active: no current target source requires
interfaces, and even a lightweight Linux-native model adds substantial dispatch,
ABI, and lifetime surface. Revisit when a concrete compatibility target needs
them. Ordered **after** the LFM arc (reuses its class registry / RTTI).

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
