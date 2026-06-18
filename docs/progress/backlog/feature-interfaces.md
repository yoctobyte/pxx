# Interfaces

- **Type:** feature
- **Status:** backlog (CORBA vertical slice landed 2026-06-18; follow-ups open — see Log)
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §3 — intentionally deferred)

## Priority note (2026-06-16, refined 2026-06-18)

**Low priority, but the OOP-family capstone — not "never".** Interfaces are
largely a COM-era binary-contract mechanism (cross-binary ABI stability: Windows
COM, OLE). PXX targets **standalone, all-in-one-binary applications**, so that
primary value does not apply, and the secondary value (inheritance-free
polymorphic abstraction + ARC lifetime) is covered by classes, abstract methods,
and `object` (feature-object-reference-type). So it stays **low** — but it is the
last gap in the OOP feature set, and deferring it forever means repeatedly
bumping into it. Do it eventually, after the other OOP pieces; pull forward only
if a concrete interop need appears.

**Effort is MEDIUM, not the scary arc the original note implied** — the expensive
substrate already exists: VMT + virtual dispatch, the RTTI class registry, ARC
refcounts (managed-string `IncRef`/`DecRef`), and scope-exit + exception-unwind
finalisation. CORBA-style (no refcount, fat-pointer `{IMT, instance}`, `is`/`as`/
`Supports` via the RTTI walk) is ~2–4 focused days; COM-style ARC is an
incremental add reusing the existing ARC + scope-cleanup machinery.

**Item 5 is extracted.** Class `is`/`as`/`Supports` (the runtime type-walk) is now
its own ticket **feature-class-is-as** — useful independently (class downcasts,
the demos) and a prerequisite this ticket reuses.

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
- 2026-06-18 — **CORBA vertical slice landed** (commit 3a7b0c5). Working end to
  end on all 4 Linux targets, byte-identical to FPC {$interfaces corba}: declare
  `IFoo = interface ... end`, class implements via the parent list, interface var
  (fat pointer {IMT, instance}, 2*TARGET_PTR_SIZE), class→interface assignment,
  and interface method dispatch (0-arg + args, procedure-as-statement, Self field
  read/mutation, same-instance identity). Per-(class,interface) IMT emitted in
  Data[] and wired via MethodFixups like the VMT; call dispatches through the
  existing IR_CALL_IND. New: UClsIsInterface, IMT table + FindIMT, IR_IMTADDR,
  AN_INTF_CALL. make test + cross-bootstrap byte-identical.
  **Mechanism decisions locked:** CORBA/no-refcount; fat pointer (not Delphi
  thunks); GUIDs parsed+ignored; IMT slot = interface method declaration order.
  **Still open (decide/build next):** is/as/Supports on interfaces (reuse the
  feature-class-is-as VMT walk — but interface identity is the IMT, needs a
  per-instance interface-table lookup or a Supports helper); interface-typed
  params/results across function calls; interface inheritance; assigning a
  base-class-typed value (dynamic dispatch through interface); COM ARC; operator
  `=`/`<>` identity. The slice captures the IMT from the RHS *static* class, so
  polymorphic class→interface through a base-typed var uses the base's IMT
  (acceptable v1; revisit with dynamic IMT lookup).
- 2026-06-18 — **`obj is IFoo` landed** (commit b8f9289): real implementation
  query via the closed-world VMT-set (interface target → classes with a matching
  IMT). All 4 targets; cross-bootstrap byte-identical. Verified already-working:
  interface params + results (64-bit targets), method dispatch. Narrowed the
  remaining open items: `as IFoo`/`Supports` (checked cast to an interface
  value), implicit class→interface coercion at call sites, 16-byte interface
  params on i386 (32-bit aggregate-param ABI), interface inheritance, COM ARC.
