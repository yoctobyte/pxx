# PXX Type System and Target Policy

**Status:** Phase 1 — Specify and test.  
**Reference:** [FPC ordinal/integer types](https://www.freepascal.org/daily/doc/ref/refsu4.html),
[NativeInt](https://www.freepascal.org/docs-html/rtl/system/nativeint.html)

---

## Design Principle: Three Separate Layers

PXX separates concerns into three distinct layers. Without this split, adding a
second backend (e.g. i386) would require duplicating and patching every implicit
assumption about register width.

| Layer | What it describes |
|---|---|
| **Source type semantics** | Pascal type names, signedness, valid operations, ordinal range |
| **Storage layout** | Size in bytes, alignment, record field offsets, array element stride |
| **Target ABI/backend** | Register width, calling convention, ELF format, syscall numbers |

---

## Pascal Type → Canonical Size Table

The sizes below are **source-language sizes**, not target-word sizes.  
`Integer` is 32-bit on both 32-bit and 64-bit targets, consistent with FPC ObjFPC mode.

| Pascal type(s) | PXX internal kind | Bytes | Signed | Notes |
|---|---|---|---|---|
| `Byte` | `tyUInt8` | 1 | No | Also `tyChar` alias for character context |
| `ShortInt` | `tyInt8` | 1 | Yes | |
| `Char`, `Boolean` | `tyUInt8` | 1 | No | Boolean stored as 0/1 in 1 byte |
| `Word` | `tyUInt16` | 2 | No | |
| `SmallInt` | `tyInt16` | 2 | Yes | |
| `Integer`, `LongInt` | `tyInt32` | 4 | Yes | **Not pointer-sized** |
| `Cardinal`, `LongWord` | `tyUInt32` | 4 | No | |
| `Int64` | `tyInt64` | 8 | Yes | |
| `QWord` | `tyUInt64` | 8 | No | |
| `NativeInt`, `PtrInt` | `tyNativeInt` | target ptr | Yes | 4 on i386, 8 on x86-64 |
| `NativeUInt`, `PtrUInt` | `tyNativeUInt` | target ptr | No | |
| `Pointer`, class reference | `tyPointer` | target ptr | No | |
| `Single` | `tySingle` | 4 | — | Floating point (future) |
| `Double` | `tyDouble` | 8 | — | Floating point (future) |
| `AnsiString` | `tyString` | varies | — | Heap/inline; see String Layout |

**Key rule:** A 64-bit target changes pointer-sized types (`Pointer`, `NativeInt`,
class references), not `Integer`. Pointer-sized arithmetic must use `NativeInt`/`PtrInt`,
not `Integer`.

---

## Target Configuration

The current and only supported target is:

```
--target=x86_64-linux   (implicit, currently fixed)
TARGET_PTR_SIZE  = 8
TARGET_WORD_SIZE = 8
CPU64     defined
CPUX86_64 defined
LINUX     defined
```

These symbols describe the *generated binary*, not the host running PXX.

Future planned target:

```
--target=i386-linux
TARGET_PTR_SIZE  = 4
CPU32     defined
CPUI386   defined
LINUX     defined
```

---

## Internal Type Kind Encoding

`TTypeKind` is an enumeration stored as a raw integer in bootstrapped binary.
**Ordinal values must not be reordered** once a stable binary is recorded.
New kinds are always appended after existing ones.

### Existing kinds (ordinals 0–6, fixed since bootstrap)

| Ordinal | Name | Meaning |
|---|---|---|
| 0 | `tyUnknown` | Unresolved / error |
| 1 | `tyInteger` | **Legacy:** currently 8-byte on x86-64. Migrating to 4-byte `tyInt32`. |
| 2 | `tyBoolean` | **Legacy:** currently 8-byte. Migrating to 1-byte `tyUInt8`. |
| 3 | `tyChar` | 1-byte unsigned character / `Byte` alias |
| 4 | `tyString` | Pascal string with inline length prefix |
| 5 | `tyRecord` | Struct / record type |
| 6 | `tyClass` | Object/class reference (pointer-sized) |

### New kinds (appended; ordinals 7–17)

| Ordinal | Name | Bytes | Signed |
|---|---|---|---|
| 7 | `tyInt8` | 1 | Yes |
| 8 | `tyUInt8` | 1 | No |
| 9 | `tyInt16` | 2 | Yes |
| 10 | `tyUInt16` | 2 | No |
| 11 | `tyInt32` | 4 | Yes |
| 12 | `tyUInt32` | 4 | No |
| 13 | `tyInt64` | 8 | Yes |
| 14 | `tyUInt64` | 8 | No |
| 15 | `tyNativeInt` | ptr | Yes |
| 16 | `tyNativeUInt` | ptr | No |
| 17 | `tyPointer` | ptr | No |

---

## Central Type Helper Functions

These helpers replace all scattered `if tk = tyInteger then 8 else 1` patterns.
They live in `compiler/symtab.inc`.

```pascal
function TypeSize(tk: TTypeKind): Integer;
{ Returns the byte size for storing a value of type tk.
  For pointer-sized types, returns TARGET_PTR_SIZE (currently 8). }

function TypeAlign(tk: TTypeKind): Integer;
{ Returns the alignment requirement for type tk (power of 2). }

function TypeSigned(tk: TTypeKind): Boolean;
{ Returns true if tk represents a signed integer type. }

function TypeIsOrdinal(tk: TTypeKind): Boolean;
{ Returns true for all integer and character types (not String, Record, etc.). }

function TypeIsPointerSized(tk: TTypeKind): Boolean;
{ Returns true for Pointer, NativeInt, NativeUInt, tyClass. }
```

---

## SizeOf Intrinsic

`SizeOf(TypeName)` is a compile-time constant expression that returns the byte
size of a type according to the table above. It is evaluated at parse time and
produces an `AN_INT_LIT` AST node.

```pascal
{ Examples }
writeln(SizeOf(Integer));    { 4 }
writeln(SizeOf(Int64));      { 8 }
writeln(SizeOf(Byte));       { 1 }
writeln(SizeOf(Pointer));    { 8 on x86-64 }
writeln(SizeOf(Boolean));    { 1 }
```

---

## String Layout (PXX-Internal)

String representation is PXX-internal and not guaranteed to match FPC's AnsiString ABI.

**Global strings (BSS):**
- 8-byte little-endian length prefix at `[base]`
- Character data starting at `[base+8]`
- Capacity: `STRING_CAP` bytes (1 MB) for globals, `LOCAL_STR_CAP` (256 bytes) for locals

**String parameters:**
- Passed as a pointer to the 8-byte-prefixed struct (caller's storage)

---

## Migration Strategy

The current bootstrap binary treats `Integer` as 8 bytes and `Boolean` as 8 bytes.
Migration is deliberate and phased to preserve fixedpoint:

1. **Phase 1** (this document): Specify the contract. Add `SizeOf` intrinsic.
   Add scalar-size regression tests that will currently fail for `Integer`.
2. **Phase 2**: Expand `TTypeKind` with new fine-grained kinds. Add helper functions.
   `ParseTypeKind` maps Pascal type names to the correct new kind.
3. **Phase 3**: Fix AMD64 load/store to emit correct-width instructions based on `TypeSize`.
   Update `AllocVar`/`AllocArray` to use `TypeSize` for BSS/frame allocation.
   Rerun bootstrap fixedpoint after each layout change.
4. **Phase 4**: Add `Pointer`, `PChar`, `NativeInt`, `PtrInt`. Prerequisite for C interop.
5. **Phase 5**: Explicit target configuration (`--target=`).
6. **Phase 6**: i386 output (only after type system is stable).

---

## FPC ObjFPC Compatibility Goals

- `Integer` = 32-bit signed (matches FPC ObjFPC behavior)
- `Pointer`/class references = pointer-sized (8 bytes on x86-64)
- `NativeInt`/`PtrInt` for pointer-sized arithmetic
- Source compatibility with FPC is a goal; FPC runtime/binary ABI is a separate, later question
- Default mode: ObjFPC-oriented

---

## What Is NOT Addressed Here

- Float/real types (`Single`, `Double`): future work
- Dynamic arrays: future work
- Interface types: future work
- FPC runtime library compatibility: separate policy document needed
- i386 ABI calling convention details: Phase 6 document
