# `object` — a rooted object-reference type

- **Type:** feature
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-16

## Idea

Add a built-in pointer-sized type that holds *any* class instance — an object
reference with no specific class bound. Semantically a pointer (instance pointer,
VMT at offset 0), but typed so the compiler/RTTI know it points at an object, not
raw memory. Call it `object` (per request) — a lightweight root, like `TObject`
without a unit.

Today there are two adjacent kinds (`compiler/defs.inc`): `tyClass` (6,
pointer-sized reference to a *specific* user class) and `tyPointer` (17, untyped).
The new type sits between them: a class reference with no class id — assignable
from any class, requiring an explicit cast to a concrete class to touch
fields/methods.

## Why

- **Polymorphic storage:** `array of object`, `object` fields, lists that hold
  mixed class instances (the collections/streams RTL wants this).
- **A cast root:** `TFoo(obj)` / eventual `is` / `as` need a common reference
  type to cast from.
- **Cleaner than `Pointer`:** raw `Pointer` loses the "this is an object" fact;
  RTTI, ownership, and future ARC/refcounting can key off the object kind.

## Sketch

- New `tyObject` kind (or reuse `tyClass` with a sentinel "no class" id —
  decide which is less invasive given RecName/UCls plumbing).
- Assignment: any class ref -> `object` (widening, no check). `object` -> a
  class ref only via an explicit cast `TClass(obj)` (no runtime check initially;
  `as` with a check is a later add).
- Member access on a bare `object` is an error — must cast first.
- Pointer-sized; passes/returns/stores like `tyClass`/`tyPointer`.
- RTTI: mark it as an object reference so streaming/typeinfo can tell it from a
  raw pointer.

## Naming caution

Legacy Object Pascal `object` means an **old-style value type** (record with
methods, by-value, no implicit heap/VMT) — different from this. Confirm the
keyword choice (`object` vs `TObject` vs another) before locking grammar, so we
don't collide with a future value-`object` feature or confuse FPC-literate users.

## Notes / constraints

- **Library-only is fine.** `compiler.pas` cannot use this (it is also compiled
  by FPC; classes/objects aren't in the self-host subset — see
  feature-fpc-vs-pxx-feature-boundary). The RTL/LCL (PXX-only) can use it freely;
  that is the intended consumer.
- Builds on the working class model (metaclass/VMT, constructors, the recently
  fixed direct-base-ctor managed-string path).
- Acceptance: declare `object` vars/fields/params/arrays; assign any class
  instance; cast back and call a method; store mixed classes in `array of object`
  and dispatch via cast. Cross-target where classes are supported (x86-64 today).

## Log
- 2026-07-03 — Implemented (Track A). Design: NOT a new TTypeKind and NOT a
  tyClass sentinel — `object` resolves in the type-name resolver
  (parser.inc, next to `pointer`/`pchar`) to tyPointer with
  PtrElemTk=tyClass, PtrElemRec=REC_NONE, mirroring the metaclass-alias
  representation (least invasive of the sketch's options; the tyClass
  element tag is the "this is an object" RTTI marker). Widening class→object
  assignment, `TFoo(o)` cast-back with virtual dispatch, `array of object`,
  record fields, params all work through existing pointer plumbing. Member
  access on a bare object errors in ParseLValueAST (covers expression and
  statement paths): "member access on a bare object reference; cast to a
  concrete class first". Naming caution resolved: `object` was never a
  keyword here (no legacy value-object support), no grammar collision.
  Regressions: test_object_reference.pas + test_object_reference_error.pas
  in `make test`. Self-host byte-identical (library-only feature; the
  compiler itself never uses it, per FPC-seed constraint).
