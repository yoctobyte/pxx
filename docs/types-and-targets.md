# PXX Type System and Target Policy

**Status:** Scalar integer storage, scalar floating-point storage/arithmetic, and x86-64 target contract implemented.
**Documentation snapshot:** 2026-05-29. Implementation may change faster than this document.
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
| `Byte` | `tyUInt8` | 1 | No | Same storage/range as `Char`; numeric context |
| `ShortInt` | `tyInt8` | 1 | Yes | |
| `Char` | `tyChar` | 1 | No | Ansi character context |
| `Boolean` | `tyBoolean` | 1 | No | Stored as 0/1 |
| `Word` | `tyUInt16` | 2 | No | |
| `WideChar` | future | 2 | No | Distinct character type; not implemented |
| `SmallInt` | `tyInt16` | 2 | Yes | |
| `Integer`, `LongInt` | `tyInt32` | 4 | Yes | **Not pointer-sized** |
| `Cardinal`, `LongWord` | `tyUInt32` | 4 | No | |
| `Int64` | `tyInt64` | 8 | Yes | |
| `QWord` | `tyUInt64` | 8 | No | |
| `NativeInt`, `PtrInt` | `tyNativeInt` | target ptr | Yes | 4 on i386, 8 on x86-64 |
| `NativeUInt`, `PtrUInt` | `tyNativeUInt` | target ptr | No | |
| `Pointer` | `tyPointer` | target ptr | No | |
| class reference | `tyClass` | target ptr | No | |
| `Single` | `tySingle` | 4 | — | 4-byte IEEE-754 storage; SSE2 scalar arithmetic |
| `Double`, `Real` | `tyDouble` | 8 | — | 8-byte IEEE-754 storage; SSE2 scalar arithmetic |
| `Extended` | `tyExtended` | 10 | — | 10-byte x87 storage; arithmetic lowered through SSE2 double |
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
| 1 | `tyInteger` | Bootstrap-stable ordinal used for `Integer`; stored as 4-byte signed. |
| 2 | `tyBoolean` | Bootstrap-stable ordinal used for `Boolean`; stored as 1-byte unsigned. |
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

function TypeCompareUnsigned(lhs, rhs: TTypeKind): Boolean;
{ Selects unsigned relational code generation for ordinal comparisons. }

function TypeArithmeticResult(lhs, rhs: TTypeKind): TTypeKind;
{ Promotes integer arithmetic to signed or unsigned 64-bit evaluation. }

function TypeDivideResult(dividend: TTypeKind): TTypeKind;
{ Selects signed or unsigned division/modulo from the dividend type. }
```

---

## SizeOf Intrinsic

`SizeOf(TypeName)` is a compile-time constant expression that returns the byte
size of a type according to the table above. It is evaluated at parse time and
produces an `AN_INT_LIT` AST node. An unknown type is a compile error.

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

## Implementation Status

Implemented for the current x86-64 Linux target:

- Fixed-width scalar kinds and `SizeOf(TypeName)`.
- Width-correct scalar variable, parameter, array-element, and class-field loads/stores.
- Natural scalar alignment for variables, parameters, arrays, and class fields.
- Widened 64-bit integer arithmetic, with signed/unsigned relational and division code generation.
- Unsigned decimal output for eight-byte unsigned integer values.
- C `int` function bodies and Pascal calls under the four-byte `Integer` model.
- Predefined `PXX`, `CPU64`, `CPUX86_64`, and `LINUX` conditional symbols.
- Scalar float literals, variables, arithmetic, unary minus, comparisons, and
  mixed integer/float expression promotion in the direct backend.

Remaining target/type work:

1. Float output formatting and explicit cast/rounding intrinsics.
2. Float parity in the experimental IR backend.
3. Optional integer diagnostics and checking modes are deferred; for now,
   arithmetic wraps when a value is stored back into a narrower or overflowed
   machine-sized result, and mixed-sign expressions do not warn.
4. Additional ordinal surface: `WideChar`, explicit ordinal/range conformance,
   and associated compatibility tests. `Ord` is implemented as a compiler
   intrinsic today and may later be presented through the System/RTL builtin
   surface; it does not need ordinary external-library calling semantics.
5. General pointer syntax and semantics (`^T`, `@value`, dereference, `nil`,
   casts and checks). Pointer-sized storage and `SizeOf(Pointer)` are already
   established independently of that syntax work.
6. Explicit target selection (`--target=`).
7. i386 output after the type system and ABI surface are stable.

## Calling Conventions and Modifiers

### Subroutine Modifiers
* **`inline` / `register` / `overload`**: The compiler recognizes these subroutine modifiers case-insensitively (`inline`, `register`, `overload` and all casing variations) following a procedure or function declaration, and cleanly ignores them for the purposes of code generation.
  * *`inline`*: Frankonpiler currently compiles inlined functions as standard callable procedures. Since our compilation passes are extremely lightweight, this keeps code generation robust and simple.
  * *`register`*: Since the x86-64 backend naturally leverages register-based parameter passing (System V AMD64 ABI), register annotation is implicitly supported out-of-the-box.

### Calling Conventions
* **`cdecl` / System V AMD64 ABI**: Internally, Frankonpiler uses the standard System V AMD64 ABI calling convention for all procedures and functions. This matches the standard Linux `cdecl` calling convention on x86-64:
  * First 6 integer/pointer arguments are passed in `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`.
  * Float arguments are passed in `xmm0`–`xmm7`.
  * Return value is passed in `rax` (integers/pointers) or `xmm0` (floats).
  * Callee cleans up local stack frames, while caller manages stack-passed arguments.
* **`stdcall`**: Windows-specific calling conventions like `stdcall` are not supported on Linux and are not implemented.

---

## FPC ObjFPC Compatibility Goals

- `Integer` = 32-bit signed (matches FPC ObjFPC behavior)
- `Pointer`/class references = pointer-sized (8 bytes on x86-64)
- `NativeInt`/`PtrInt` for pointer-sized arithmetic
- `Char` is the current one-byte character type; `WideChar` remains future
  work rather than being treated as an alias for `Word`
- Source compatibility with FPC is a goal; FPC runtime/binary ABI is a separate, later question
- Default mode: ObjFPC-oriented

---

## What Is NOT Addressed Here

- Float Write/WriteLn and cast intrinsics: future work
- Full ordinal surface, including `WideChar`: future work
- General pointer expressions and typed pointer syntax: future work; pointer
  size/layout is already part of the implemented target contract
- Dynamic arrays: future work
- Interface types: future work
- FPC runtime library compatibility: separate policy document needed
- i386 ABI calling convention details: Phase 6 document
