# RTTI / Reflection — Design Notes

**Date:** 2026-05-28

---

## What RTTI is

Run-Time Type Information. Lets a program inspect its own types at
runtime: enumerate fields by name, read/write properties dynamically,
call methods by name, walk the class hierarchy. Used by serializers,
ORMs, component frameworks, debuggers, and dependency injection systems.

In Pascal/Delphi this is `TypeInfo()` and the associated descriptor
types (`PTypeInfo`, `PClassData`, etc.).

---

## Two flavors

### Old-style FPC RTTI
Descriptors for `published` members only. Name, size, field list
(name + offset + type kind), property getter/setter pointers.
Opt-in: only `published` declarations get descriptors.

### Extended RTTI (Delphi 2010+)
Full reflection including private members, methods, constructors,
custom attributes. Significantly larger binary footprint.

**PXX target: old-style, opt-in.** Extended RTTI is a later question.

---

## The key insight: compiler already has everything

The symtab already knows, at compile time:
- Every field name, byte offset, and type kind
- Every method name and proc address
- Every class's parent class
- Every property's getter/setter

RTTI is not a hard semantic problem. It is a **data-emission problem**:
take what the compiler already knows and write it into the binary as
runtime-accessible tables.

---

## What needs to be emitted

Per class, into the data section:

```
ClassDescriptor:
  name_ptr     : pointer to class name string
  parent_ptr   : pointer to parent ClassDescriptor (or nil)
  instance_size: Integer
  field_count  : Integer
  fields_ptr   : pointer to FieldDescriptor array
  prop_count   : Integer
  props_ptr    : pointer to PropDescriptor array
  method_count : Integer
  methods_ptr  : pointer to MethodDescriptor array

FieldDescriptor:
  name_ptr  : pointer to field name string
  offset    : Integer
  type_kind : TTypeKind

PropDescriptor:
  name_ptr  : pointer to property name string
  type_kind : TTypeKind
  getter    : pointer (field offset or method address)
  setter    : pointer (field offset or method address)

MethodDescriptor:
  name_ptr  : pointer to method name string
  proc_ptr  : pointer to method code
```

All of this is available in the symtab at compile time. The code
generator just needs to walk the class table at ELF-write time and
emit the descriptor structures.

---

## Binary size impact and the opt-in gate

PXX targets tiny binaries (Hello World = 325 bytes). Emitting
descriptors for every type in every program would break this.

Solution: `published` visibility as the opt-in gate, mirroring FPC.
Only `published` members get descriptor entries. A program with no
`published` declarations pays zero cost — no descriptor tables emitted.

A compile flag (`--no-rtti` or `{$RTTI none}`) can suppress all
descriptor emission even if `published` is used, for minimal embedded
binaries that never need reflection.

---

## What RTTI does NOT require

Unlike interfaces, RTTI does not require:
- Fat pointers or a new variable model
- Multi-vtable object layout
- Reference counting
- COM GUID machinery

It is purely a read-only data emission step. No new AST nodes are
strictly required; `TypeInfo(T)` can be a compiler intrinsic that
returns the address of the emitted descriptor.

---

## Prerequisites

| Prerequisite | Why |
|---|---|
| Properties working (read/write codegen complete) | PropDescriptor needs valid getter/setter pointers |
| Class hierarchy stable | ClassDescriptor parent_ptr chain |
| Visibility sections enforced | `published` as the opt-in gate |

Does **not** require interfaces (unlike FPC's `ITypeInfo` — that is a
COM-ism PXX avoids on Linux targets).

---

## Position in the feature order

```
abstract, out, inherited     (low effort)
procedure variables          (medium — IR_INDIRECT_CALL, tyProc)
pointer expressions          (medium — type system work)
enumerations                 (low)
exception hierarchy          (medium — class descriptor parent chain)
  ↓
RTTI / reflection            (medium — data emission, opt-in via published)
  ↓
interfaces (lightweight)     (high — fat pointers, multi-vtable layout)
```

RTTI comes before interfaces because it does not restructure the object
model. It only adds read-only metadata tables the compiler already has
in hand.

---

## Relationship to class name strings

Exception unhandled diagnostics already want class name strings
(`__frankon_unhandled` should print the class name). That is the first
slice of RTTI — emit name strings per class. The full descriptor tables
build on top of that first slice.

Start there: add class name strings to the data section for every
user-defined class. Cost is small, immediately useful for exception
messages, and is the first increment toward full RTTI.
