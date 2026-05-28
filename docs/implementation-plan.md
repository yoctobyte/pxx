# Pascal Language Implementation Plan

**Date:** 2026-05-28  
**Status:** Ready to execute

Each phase is a discrete unit of work. Complete and confirm fixedpoint
before starting the next. Items within a phase are ordered by dependency.

---

## Phase 0 — Fix existing IR gap (before removing experimental tag)

**Prerequisite for promoting IR to default backend.**

### 0.1 — `AN_VIRTUAL_CALL` in IR lowering

**File:** `compiler/ir.inc`, function `IRLowerAST`  
**File:** `compiler/ir_codegen.inc`, function `IREmitNode`

`AN_VIRTUAL_CALL` is emitted by the parser and handled in `codegen.inc`
but has no case in `IRLowerAST`. Any program calling a virtual method
via the IR backend silently hits `IR_UNSUPPORTED`.

Fix: add `AN_VIRTUAL_CALL` case to `IRLowerAST`. Lower to:
- `IR_LOAD_MEM` of the VMT pointer (offset 0 of object)
- `IR_LOAD_MEM` of the vtable slot (VMT pointer + slot * 8)
- `IR_INDIRECT_CALL` through that slot address

Or add `IR_VIRTUAL_CALL` (IVal = VMT slot index; object in first arg)
and handle in `IREmitNode` — mirrors what `codegen.inc` already does.

Reference: `compiler/codegen.inc` — search `AN_VIRTUAL_CALL` for the
legacy implementation to mirror.

**Test:** any program with a virtual method call compiled with
`--experimental-ir-codegen` must produce correct output.
Confirm fixedpoint still holds after change.

---

## Phase 1 — Trivial parser/symtab items

These have no IR or codegen impact. Can be done in one session.

### 1.1 — `abstract` methods

**File:** `compiler/parser.inc`, class method declaration loop  
(around line 2913 where `virtual`/`override` are already parsed)

Parser already recognizes `virtual` and `override`. Add `abstract`:
- Set `isAbstract` flag alongside `isVirtual`
- Fill VMT slot with address of a `__abstract_error` stub that prints
  "abstract method called" and halts
- `__abstract_error` stub: emit once like `__frankon_unhandled`

### 1.2 — `out` parameters

**File:** `compiler/parser.inc`, `ParseSubroutine` param loop  
(where `var` is recognized for `isByRef`)

`out` is semantically identical to `var` at codegen level — passed by
reference, caller owns the initial value. Add `out` as an accepted
keyword that sets `isByRef := True`. No IR or codegen change needed.

### 1.3 — Enumerations

**File:** `compiler/parser.inc`, `ParseTypeSection`  
Currently hits `{ Skip non-enum type defs }` — enums are consumed silently.

Fix:
- Detect `(` after type name in `ParseTypeSection` as enum declaration
- Parse comma-separated identifier list
- Register each identifier in symtab as a typed constant with value 0, 1, 2...
- Register the enum type name as a new type kind or as `tyInteger` alias
  (simplest: enum values are just integers; `Ord(x)` works for free)
- `ParseTypeKind` must resolve the enum type name

### 1.4 — `goto` and `label`

**File:** `compiler/parser.inc`  
**IR:** already has `IR_LABEL` and `IR_JUMP` — no IR changes needed.

- Add `label` declaration parsing (list of label names at top of block)
- Register label names in symtab with a patch address (like forward proc refs)
- Add `AN_LABEL` / `AN_GOTO` AST nodes (or resolve to `IR_LABEL`/`IR_JUMP` directly)
- Forward-reference patch list: same pattern as `ApplyCallFixups`

---

## Phase 2 — `inherited`

**File:** `compiler/parser.inc`, expression/statement parser  
**IR:** resolve at parse time to `IR_CALL` — no new IR node needed.

When parser sees `inherited` keyword:
- Must be inside a method body (current proc has an owner class)
- Look up current method name in the parent class chain via `UClsParent`
- Find the parent's proc index for the same method name
- Emit `AN_CALL` (or directly `IR_CALL`) with that proc index and
  `Self` as first argument

Edge case: `inherited` with explicit method name (`inherited Create(x)`)
— parse the name and args, look up by name in parent chain.

`inherited` without a name inherits the current method name with the
same arguments passed through.

**Test:** derived class calling `inherited` in constructor and overridden
method. Confirm field initialization order is correct.

---

## Phase 3 — Pointer expressions

**Files:** `compiler/parser.inc`, `compiler/symtab.inc`,
`compiler/ir.inc`, `compiler/ir_codegen.inc`

IR already has `IR_LOAD_MEM`, `IR_STORE_MEM`, `IR_LEA` — codegen is
largely pre-built. The work is type system and parser.

### 3.1 — Typed pointer type declarations

- `ParseTypeKind`: recognize `^TypeName` as a pointer-to-type
- Add pointer-to-type record in symtab (base type kind + pointed-to kind)
- `tyPointer` already exists for untyped pointer; add typed variant

### 3.2 — `nil` literal

- Add `AN_NIL` AST node (or `AN_INT_LIT` with `tyPointer` type and value 0)
- IR: lower to `IR_CONST_INT(0)` with pointer type annotation

### 3.3 — Address-of `@expr`

- Add `AN_ADDR_OF` AST node; Left = lvalue expression
- IR: lower to `IR_LEA` — already exists and handles locals/params/globals

### 3.4 — Dereference `p^`

- Add `AN_DEREF` AST node; Left = pointer expression
- IR: lower to `IR_LOAD_MEM(IR_lower(Left), 0, pointed-to-type)`
- As lvalue (left of assignment): lower to `IR_STORE_MEM`

### 3.5 — Typed pointer casts

- `Pointer(x)`, `PInteger(x)` etc.: parse as type-cast expression
- IR: no-op cast (reinterpret bits); just change the type annotation

**Test:** linked list node, pointer arithmetic, nil check, typed read/write.

---

## Phase 4 — Procedure variables

**Files:** `compiler/defs.inc`, `compiler/symtab.inc`,
`compiler/parser.inc`, `compiler/ir.inc`, `compiler/ir_codegen.inc`

This also enables `IR_INDIRECT_CALL` which Phase 0.1 may need.

### 4.1 — `tyProc` type kind

- Add `tyProc` (and `tyMethod` for method pointers) to `TTypeKind`
  **as append-only** — do not reorder existing ordinals
- Symtab: store procedure signature alongside `tyProc` variables
  (param types + return type), needed for type-checking at call sites

### 4.2 — Procedure type declarations

- `ParseTypeKind`: recognize `procedure(args)` and `function(args): ret`
  as type expressions
- `ParseTypeSection`: `type TCallback = procedure(x: Integer)` registers
  a procedure type name

### 4.3 — Procedure variable assignment and call

- `ParseFactor`: identifier of `tyProc` type → `AN_IDENT` with proc type
- Assignment: `cb := MyProc` → store proc address (like `AN_ADDR_OF` of a proc)
- Call through variable: `cb(args)` → `AN_INDIRECT_CALL`
  (new AST node; Left = callee expr; Right = arg chain)
- IR: lower `AN_INDIRECT_CALL` to `IR_INDIRECT_CALL` (new IR node)
- `ir_codegen.inc`: `IR_INDIRECT_CALL` → load address into rax, `call rax`

### 4.4 — Method pointers (`of object`)

- `procedure(x: Integer) of object` — fat pointer (proc addr + self ptr)
- Defer until plain procedure variables are stable

**Test:** sort with comparator callback, event handler pattern.

---

## Phase 5 — Exception hierarchy

**Files:** `compiler/symtab.inc`, `compiler/codegen.inc`,
`compiler/ir_codegen.inc`

### 5.1 — Class name strings

Emit a name string into the data section for every user-defined class.
Add `UClsNameOffset`/`UClsNameLen` arrays alongside existing `UClsSize_`.
Immediately useful: `__frankon_unhandled` can print the class name.

### 5.2 — Class descriptor parent pointer

Add parent descriptor pointer to the emitted class descriptor (currently
only tracked in `UClsParent` at compile time, not emitted as runtime data).

### 5.3 — `IR_EXC_MATCH` parent chain walk

`IR_EXC_MATCH` currently does exact class ID comparison. Change to walk
the class descriptor parent chain: match if raised class == handler class
OR any ancestor == handler class.

### 5.4 — Built-in `Exception` base class

Register `Exception` as a built-in user class at compiler startup
(before any source is parsed). Fields: `Message: AnsiString`.
`raise Exception.Create('msg')` then works without any source declaration.

**Test:** derived exception class caught by base-class handler.
Confirm `Message` field accessible in handler.

---

## Phase 6 — `ReadLn` / `Read`

**Files:** `compiler/parser.inc`, `compiler/ir.inc`,
`compiler/ir_codegen.inc`

- Add `AN_READLN` AST node; argument list = lvalue targets
- IR: `IR_READLN` — lowers to `sys_read(0, buf, N)` syscall
- For integer targets: `sys_read` into a temp buffer, parse decimal
- For string targets: `sys_read` directly into string buffer, trim newline
- `ReadLn` with no args: consume rest of input line (discard)

**Test:** read integer, read string, mixed read/write round-trip.

---

## Phase 7 — RTTI (opt-in)

**Files:** `compiler/symtab.inc`, `compiler/elfwriter.inc`,
`compiler/parser.inc`

See `docs/rtti-design.md` for full design.

- Add `published` visibility section parsing to class declarations
- At ELF-write time, emit `ClassDescriptor` / `FieldDescriptor` /
  `PropDescriptor` tables for classes with `published` members
- `TypeInfo(T)` compiler intrinsic returns pointer to class descriptor
- Zero cost for programs with no `published` declarations

---

## Phase 8 — Dynamic arrays

**Files:** `compiler/defs.inc`, `compiler/symtab.inc`,
`compiler/parser.inc`, `compiler/ir.inc`, `compiler/ir_codegen.inc`

Requires pointer expressions (Phase 3) to be stable.

- `array of T` type: header layout = `(length: Int64, data: T[])`, heap-allocated
- `SetLength(a, n)`: `GetMem(header + n * TypeSize(T))`, update length field
- `Length(a)`, `High(a)`, `Low(a)`: intrinsics reading header
- Array indexing: bounds-checked load/store through header pointer
- Lifetime: manual (`SetLength(a, 0)` + `FreeMem`); no GC, no reference counting
  (explicit policy — document clearly)

---

## Phase 9 — Interfaces (lightweight, no COM)

**Prerequisite:** Phases 0–8 must be stable. Especially proc variables
(Phase 4) and exception hierarchy (Phase 5).

See `docs/interfaces-design.md` for full design.

High-level steps:
- `interface` type declarations: parse method list, assign interface ID
- Per-class per-interface vtable: extend `UClsVMTOffset` to 2D table
- Fat pointer variable layout: 2-word locals/params for interface types
- `IR_INDIRECT_CALL` reused for interface dispatch (already from Phase 4)
- `as` / `is`: type-tag comparison (no GUID, no COM)
- No `AddRef`/`Release`/`QueryInterface` — lightweight model only

---

## Notes for agents

- **Fixedpoint rule:** after every phase, run `make test` and confirm
  `cmp gen1 gen2` is identical. Do not proceed if fixedpoint breaks.
- **Token ordinal rule:** never reorder `TTypeKind` or `TTokenKind` enums.
  Append only. Reordering breaks bootstrapped binaries.
- **`REC_UCLASS_BASE` rule:** whenever a new hardcoded record type is
  added to `symtab.inc`, bump `REC_UCLASS_BASE` past the new max.
- **Bootstrap when needed:** if a change requires a new global data
  structure unknown to the current seed, run `make bootstrap` (FPC path)
  before continuing self-hosted development.
- **Commit granularity:** one commit per logical unit. Do not batch
  multiple phases into one commit.
- **Reference:** `compiler/codegen.inc` is the legacy implementation.
  For any IR feature, find the equivalent in `codegen.inc` first and
  mirror the logic.
