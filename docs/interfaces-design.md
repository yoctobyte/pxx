# Interfaces — Design Notes

**Date:** 2026-05-28

---

## What interfaces are

A language-level contract: "any class implementing this interface
promises to provide these methods." The caller dispatches through the
interface, not through the concrete class. Multiple unrelated classes
can satisfy the same interface.

This is a general OOP concept. It appears in Java, Delphi, Swift, Go,
C#, and others. It is not Windows-specific.

---

## COM is not interfaces

COM (Component Object Model) is Microsoft's binary interop standard for
Windows. It happens to use the same fat-pointer/vtable layout that
interfaces require. Delphi chose to wire the two together: `IInterface`
maps to `IUnknown`, and every interface variable carries `QueryInterface`,
`AddRef`, and `Release` semantics plus a 16-byte GUID.

FPC inherits this design for Windows/COM compatibility.

**For PXX on Linux this is irrelevant.** We have no COM objects to call,
no Windows clients to satisfy, and no reason to pay the GUID and
reference-counting overhead.

---

## Three possible models

### 1. Full FPC / COM-compatible
`IInterface` = `IUnknown`. Every interface has a GUID. Variables are
reference-counted via `AddRef`/`Release`. `as` and `is` call
`QueryInterface` at runtime.

Needed only if targeting Windows COM interop or linking FPC COM libraries.
Not relevant for PXX's Linux/embedded target set.

### 2. Lightweight interfaces (recommended for PXX)
Vtable contract only. No GUIDs. No reference counting. `is`/`as` use a
simple type tag (integer class ID) instead of GUID matching. Fat pointer
still required — that cost is unavoidable regardless of model.

This is sufficient for all common uses: dependency injection, plugin
systems, testability, separation of concerns.

### 3. Structural / Go-style
No explicit `implements` declaration. The compiler matches any class
that provides the required methods. Cleanest for the programmer.
Hardest to implement: requires compile-time structural matching across
all types in the program. Not practical until the type system is
significantly more mature.

---

## Why the fat pointer cost is unavoidable

Regardless of model (1, 2, or 3), an interface-typed variable cannot
be a single pointer to the object. It must be two words:

```
[ object_ptr | interface_vtable_ptr ]
```

The interface vtable lists methods in **interface-declaration order**,
which is not the same as the class VMT order. The dispatcher needs both
the object (to pass as `Self`) and the right vtable (to find the method).

This changes:
- Variable size and alignment (2 words instead of 1)
- Load/store codegen for interface-typed locals and parameters
- Calling convention for procedures accepting interface parameters
- Assignment semantics (must select the correct vtable for the target interface)

There is no way to avoid this without abandoning the interface model
entirely.

---

## Why interfaces are last

Every other missing feature can be added without changing the variable
model. A `goto` is just a new AST node. Pointer expressions reuse
existing IR. Enums are symbol table entries. Procedure variables add
one new type kind and one new IR node.

Interfaces require:

1. **Procedure variables first** — interface dispatch is an indirect
   call through a vtable pointer. `IR_INDIRECT_CALL` must exist before
   any interface call can be emitted.

2. **`inherited` first** — implementing an interface on a derived class
   requires calling parent implementations. Without `inherited`, derived
   class interface implementations are broken by design.

3. **Exception hierarchy first** — real programs use interface-typed
   exception handling. Wiring `on E: ISomeInterface do` without an
   exception class hierarchy is a half-feature.

4. **Multi-vtable object layout** — our current `UClsVMTOffset` is one
   integer per class (one VMT per class). A class implementing N
   interfaces needs N additional vtable regions in the data section, plus
   a (class × interface) lookup table. This is a structural change to
   how class objects are laid out in memory.

5. **`as` / `is` across interface/class boundary** — requires runtime
   type descriptors that link interfaces to their implementing classes.
   The descriptor design affects how every class is emitted.

6. **Reference counting (if FPC-compatible)** — or a deliberate decision
   to diverge and document that PXX interfaces are not COM-compatible.

None of these are cosmetic. Each is a prerequisite that must be solid
before interfaces can be added correctly. Adding interfaces before the
prerequisites are in place means either a broken implementation or
immediate rework.

---

## Recommended order

```
abstract methods          (trivial — VMT stub)
inherited                 (low — parent chain walk)
procedure variables       (medium — IR_INDIRECT_CALL + tyProc type kind)
pointer expressions       (medium — IR ready, type system work)
exception hierarchy       (medium — class descriptor parent chain)
  ↓
interfaces (lightweight)  (high — fat pointers, multi-vtable layout,
                            type tag dispatch; all prerequisites above
                            must be solid first)
```

COM-compatible interfaces (GUIDs, AddRef/Release, QueryInterface) come
after lightweight interfaces if ever needed, and only if a Windows or
COM interop target is added.
