# Pascal Language Implementation Status

**Inventory date:** 2026-05-28  
**Compiler:** PXX / pascal26, self-hosted, IR fixedpoint confirmed  
**Methodology:** source grep of defs.inc / parser.inc / ir.inc / codegen.inc

This document is a point-in-time inventory. The regression suite is
authoritative for what is tested. Source is authoritative for what is
implemented. This doc is a map; the territory may move faster.

---

## Status Key

| Symbol | Meaning |
|--------|---------|
| ✓ | Implemented and regression-tested |
| ~ | Implemented but partially or untested |
| P | Parsed / accepted but not fully compiled or codegen-complete |
| ✗ | Not implemented |

---

## Scalar Types

| Type | Status | Notes |
|------|--------|-------|
| `Byte`, `ShortInt` | ✓ | |
| `Word`, `SmallInt` | ✓ | |
| `Integer`, `LongInt` | ✓ | 32-bit signed, FPC ObjFPC-compatible |
| `Cardinal`, `LongWord` | ✓ | |
| `Int64`, `QWord` | ✓ | |
| `NativeInt`, `PtrInt`, `NativeUInt`, `PtrUInt` | ✓ | Pointer-sized |
| `Pointer` | ✓ | Type exists, SizeOf works |
| `Boolean` | ✓ | |
| `Char` | ✓ | 1-byte unsigned |
| `WideChar` | ✗ | |
| `AnsiString` | ~ | PXX-internal layout; not FPC ABI-compatible |
| `WideString`, `UnicodeString` | ✗ | |
| `Single`, `Double`, `Extended` | ~ | Arithmetic done; `WriteLn(f)` not done |

---

## Composite Types

| Feature | Status | Notes |
|---------|--------|-------|
| Static arrays | ✓ | |
| Dynamic arrays (`array of T`) | ✗ | `SetLength` is string-only; no real dynarray |
| Records | ~ | Basic field layout; no packed, no variant |
| Packed records/arrays | ✗ | |
| Variant records | ✗ | |
| Sets | ~ | `in` operator works (IR); set type declaration and set ops missing |
| Enumerations | P | Type section consumes enum syntax but does not register constants |
| Procedure/function types | ✗ | No callbacks, no method pointers, no event handlers |
| `^T` typed pointer types | ✗ | `Pointer` type exists; typed pointer syntax not parsed |

---

## Pointer Expressions

| Feature | Status | Notes |
|---------|--------|-------|
| `Pointer` type, SizeOf | ✓ | |
| `^T` typed pointer syntax | ✗ | |
| Address-of `@expr` | ✗ | |
| Dereference `p^` | ✗ | |
| `nil` literal | ✗ | |
| Pointer arithmetic | ✗ | |
| Typed pointer casts | ✗ | |

---

## OOP / Classes

| Feature | Status | Notes |
|---------|--------|-------|
| Class declaration with fields | ✓ | |
| Non-virtual methods | ✓ | |
| Constructors (`.Create`) | ✓ | GetMem + field init |
| `virtual` / `override` methods | ✓ | VMT emitted in data section |
| Class inheritance | ✓ | `UClsParent` chain tracked |
| `inherited` call | ✗ | Keyword not recognized in parser |
| Properties (read/write) | ~ | Parser handles `property x: T read f write f`; codegen coverage unclear |
| Static class methods | ✓ | |
| Abstract methods | ✗ | Keyword not recognized; no error-stub VMT slot |
| `with` statement | ✗ | |
| Class references (`TClass` metaclass) | ✗ | |
| Interfaces (`IInterface`, GUID, `implements`) | ✗ | `interface` keyword exists for unit sections only |
| Visibility sections (`private`, `protected`, `public`, `published`) | ✗ | Parsed but not enforced |
| Destructors | ~ | Syntax accepted; finalization semantics not fully covered |

---

## Generics

| Feature | Status | Notes |
|---------|--------|-------|
| Generic classes (`TList<T>`) | ✓ | |
| Generic functions/procedures (B1 syntax) | ✓ | `generic function F<T>` + `specialize F<X> as FX` |
| Call-site generic sugar (`F<T>(a,b)`) | ✗ | |
| Multi-param generics | ✓ | |

---

## Overloading

| Feature | Status | Notes |
|---------|--------|-------|
| Routine overloading | ✓ | |
| Operator overloading | ✓ | `operator + (a,b: T): T` |
| Strict overload mode | ✓ | `{$strict_overload on}` / `--strict-overload` |

---

## Control Flow

| Feature | Status | Notes |
|---------|--------|-------|
| `if`/`then`/`else` | ✓ | |
| `case` | ✓ | |
| `while` | ✓ | |
| `for` (ascending + descending) | ✓ | |
| `repeat`/`until` | ✓ | |
| `break`, `continue` | ✓ | |
| `exit` | ✓ | |
| `goto` / `label` | ✗ | |

---

## Exceptions

| Feature | Status | Notes |
|---------|--------|-------|
| `try/except` (catch-all) | ✓ | |
| `try/finally` | ✓ | |
| `raise <expr>` | ✓ | |
| `raise;` re-raise | ✓ | |
| `on E: TClass do` (exact class match) | ✓ | |
| `except else` | ✓ | |
| Exception hierarchy (`Exception` base, inherited matching) | ✗ | |
| Built-in exception classes (`EAccessViolation`, etc.) | ✗ | |
| `--no-unhandled-handler` | ✓ | |

---

## Procedures and Functions

| Feature | Status | Notes |
|---------|--------|-------|
| Procedures, functions | ✓ | |
| `var` parameters | ✓ | |
| `const` parameters | ~ | Accepted; no immutability enforcement |
| `out` parameters | ✗ | |
| Default parameter values | ✗ | |
| Open array parameters | ~ | Internally used; formal syntax limited |
| `forward` declarations | ✓ | |
| `inline` directive | ✗ | |
| `Result` implicit return var | ✓ | |

---

## Units

| Feature | Status | Notes |
|---------|--------|-------|
| `uses` clause (local Pascal units) | ✓ | |
| `uses` clause (C header import) | ✓ | |
| `unit` / `interface` / `implementation` sections | ~ | Parsed for compilation; no separate unit-file ABI |
| `initialization` / `finalization` sections | ✗ | |
| Separate compilation / unit files (`.ppu`) | ✗ | |

---

## Built-ins and I/O

| Feature | Status | Notes |
|---------|--------|-------|
| `WriteLn`, `Write` (integer, boolean, string, char) | ✓ | |
| `WriteLn(floatValue)` | ✗ | No float-to-string conversion |
| `ReadLn`, `Read` | ✗ | |
| `SizeOf` | ✓ | |
| `Ord`, `Chr` | ✓ | Compiler intrinsics |
| `Inc`, `Dec` | ~ | Partial |
| `New`, `Dispose` | ~ | `New` used internally for classes; formal surface limited |
| `GetMem`, `FreeMem` | ~ | Used internally |
| `SetLength` | ~ | String resize only |
| `Length` | ~ | String length only |
| `Copy`, `Delete`, `Insert`, `Pos` | ✗ | |
| `Format` | ✗ | |
| `High`, `Low` | ✗ | |
| `Assigned` | ✗ | |

---

## Directives and Compiler Switches

| Feature | Status | Notes |
|---------|--------|-------|
| `{$define}`, `{$undef}`, `{$ifdef}`, `{$ifndef}`, `{$else}`, `{$endif}` | ✓ | |
| `{$mode objfpc}` | ✓ | Accepted marker; no semantic mode switching |
| `{$strict_overload on/off}` | ✓ | |
| `-dNAME`, `-uNAME`, `-Mobjfpc` | ✓ | |
| `{$if expr}`, `{$elseif}` | ✗ | |
| Predefined: `PXX`, `CPU64`, `CPUX86_64`, `LINUX` | ✓ | |
| `{$H+}` and other FPC switches | P | Silently ignored |
| Inline assembler (`asm ... end`) | ✗ | |

---

## AST and IR Impact Analysis

The table below estimates the effort required for unimplemented features
in terms of AST node changes and IR node changes. Features with no AST/IR
impact are parser/symtab-only work.

### Legend: effort scale
- **Trivial** — no new nodes; parser/symtab change only
- **Low** — 1–2 new AST nodes; reuse existing IR
- **Medium** — 2–4 new AST/IR nodes; new codegen paths
- **High** — structural additions; new type system or runtime support
- **Very high** — fundamental new subsystem

---

### Enumerations

**AST impact:** None new. Enum constants are integers — `AN_INT_LIT` with a
typed annotation suffices. Need to register enum names and values in the
symbol table and teach `ParseTypeKind` to resolve enum type names.

**IR impact:** None. Enum values lower to `IR_CONST_INT`.

**Effort: Low.** Pure symbol table + type resolution work. No new nodes.

---

### `abstract` methods

**AST impact:** None. Parser recognizes `virtual; abstract;` and fills
the VMT slot with a stub (runtime error label). No AST node needed.

**IR impact:** None.

**Effort: Trivial.** Parser flag + VMT stub emit.

---

### `out` parameters

**AST impact:** None new. Identical to `var` params at codegen. Distinction
is type-system annotation only.

**IR impact:** None.

**Effort: Trivial.** Parser annotation; no codegen change.

---

### `goto` / `label`

**AST impact:** `AN_GOTO` (IVal = label name hash or symtab index),
`AN_LABEL` (IVal = label id).

**IR impact:** None new. `IR_JUMP` and `IR_LABEL` already exist. IR lowering
just emits `IR_LABEL` for label declarations and `IR_JUMP` for goto.

**Effort: Low.** IR infrastructure already there. Parser + forward-reference
patch list (same pattern as proc forward refs).

---

### `inherited` call

**AST impact:** `AN_INHERITED_CALL` (IVal = method name index; Left = arg
chain). Or: resolve at parse time to a direct `AN_CALL` with the parent
class's proc index — avoids a new node entirely.

**IR impact:** None new if resolved at parse time to `IR_CALL`.

**Effort: Low–Medium.** Parent-chain walk in symtab. Parse-time resolution
is cleaner than a new IR node.

---

### `with` statement

**AST impact:** None new if desugared at parse time. Parser pushes a scope
frame onto a "with-stack"; `AN_FIELD` access of an unresolved ident checks
the with-stack first.

**IR impact:** None.

**Effort: Medium.** Scope stack in parser; no new nodes, but interaction
with nested `with` and shadowing requires care.

---

### `ReadLn` / `Read`

**AST impact:** `AN_READLN` node (mirror of `AN_WRITELN`); argument list
of lvalue targets.

**IR impact:** `IR_READLN` — lowers to `sys_read` syscall + integer parse
for numeric targets, or direct buffer fill for strings.

**Effort: Low–Medium.** Straightforward syscall path. String input needs
a buffer and a length trim.

---

### AN_VIRTUAL_CALL in IR (existing gap)

`AN_VIRTUAL_CALL` is emitted by the parser and handled in the legacy
`codegen.inc` but is **missing from `ir.inc`**. Any program that calls a
virtual method via the IR backend hits `IR_UNSUPPORTED`.

**AST impact:** Node already exists (`AN_VIRTUAL_CALL = 32`).

**IR impact:** Add `IR_VIRTUAL_CALL` (IVal = VMT slot index; B = object
arg) **or** lower `AN_VIRTUAL_CALL` to `IR_LOAD_MEM` (load vtable pointer
from object) + `IR_INDIRECT_CALL` (call through pointer). The latter
reuses infrastructure that procedure variables also need.

**Effort: Low.** Missing case in `IRLowerAST`. The VMT layout and slot
indices are already computed at parse time.

---

### Pointer expressions (`^T`, `@`, dereference, `nil`)

**AST impact:**
- `AN_DEREF` — dereference `p^`; Left = pointer expr
- `AN_ADDR_OF` — address-of `@x`; Left = lvalue
- `AN_NIL` — nil literal (or just `AN_INT_LIT` with `tyPointer` type)

Typed pointer types (`^Integer`, etc.) need a new type kind or a
symtab-level pointer-to-type record.

**IR impact:**
- `IR_LOAD_MEM` already exists and loads through a pointer. The lowering
  of `AN_DEREF` can reuse it directly.
- `IR_LEA` already exists for address-of.
- `IR_STORE_MEM` already exists.

In practice: no new IR nodes needed. The IR already models memory
indirection. What is missing is the **parse-time type tracking** for
typed pointers and the **lvalue path** in `IRLowerAddress` for `AN_DEREF`.

**Effort: Medium.** Type system change (pointer-to-type), parser additions,
IR lowering additions. Codegen itself is largely pre-built.

---

### Sets

**AST impact:** `AN_SET_LIT` (list of element expressions or ranges) for
`[Red, Green]` literals. Set operators (union `+`, difference `-`,
intersection `*`) could reuse `AN_BINOP` with new operator tokens.

**IR impact:** For small sets (ordinal range ≤ 64 elements): lower to
`IR_CONST_INT` bitmask literals and `IR_BINOP` bitwise ops. `in` test
already exists in IR. For large sets: runtime heap representation needed
(new IR node or runtime call).

**Effort: Medium** for small sets (common case); **High** for large/arbitrary
sets.

---

### Procedure/function variables (callbacks)

**AST impact:** No new literal node — a proc variable is an `AN_IDENT` of
a new type kind. Calls through proc variables need `AN_INDIRECT_CALL`
(Left = proc-value expr; Right = arg chain).

**IR impact:** `IR_INDIRECT_CALL` — call through a register holding a proc
address. On x86-64: `call rax`. This is also needed for virtual calls
(see above) if the "load vtable + indirect call" lowering strategy is used.

**Type system impact:** New type kind `tyProc` or `tyFunc` carrying the
signature. `ParseTypeKind` must handle `procedure of object`,
`function(args): ret`, etc.

**Effort: High.** The type system change is the hard part. Once `tyProc`
exists and the parser can parse proc-type declarations and assignments,
codegen is one new IR node.

---

### Default parameter values

**AST impact:** None new at call site. Defaults stored in symtab alongside
param descriptors. At call site, if arg count < param count, inject
`AN_INT_LIT` / `AN_STR_LIT` defaults.

**IR impact:** None.

**Effort: Medium.** Symtab extension + call-site arg count check +
default value injection. No new nodes.

---

### Exception hierarchy (Exception base, inherited matching)

**AST impact:** None new. `AN_TRY_EXCEPT` / `AN_EXC_HANDLER` already model
typed handlers. The class descriptor needs a parent pointer.

**IR impact:** `IR_EXC_MATCH` already exists. It needs to walk the class
descriptor parent chain instead of doing exact comparison. One additional
field in the class descriptor (parent descriptor pointer).

**Effort: Medium.** Class descriptor extension + `IR_EXC_MATCH` change
from exact-compare to chain-walk. The `Exception` base class itself is
just a user class registered at compiler startup.

---

### Dynamic arrays

**AST impact:**
- `AN_SETLENGTH` (array, new length)
- `AN_DYNARRAY_ELEM` (array index, bounds-checked)
- Or: lower to `AN_CALL` of runtime helpers to avoid new nodes

**IR impact:** `IR_HEAP_ALLOC` (or lower to a runtime `GetMem` call via
`IR_CALL`). Array header (pointer + length + capacity) needs a defined
layout. Reference counting or manual lifetime management decision needed.

**Effort: High.** Runtime memory management, header layout, bounds check
codegen, `High`/`Low`/`Length` intrinsics, and the GC/RC policy question.

---

### Interfaces

**AST impact:** `AN_INTERFACE_CALL` (interface vtable dispatch). Interface
variables are fat pointers (object pointer + interface vtable pointer).
`as` / `is` operators for interface type testing.

**IR impact:** `IR_INTERFACE_CALL` — load vtable from fat pointer, index
into interface vtable, indirect call. Two-word variable layout for
interface-typed locals.

**Type system impact:** Interface type records (GUID, method list, vtable
layout). Class descriptor must list implemented interfaces and per-interface
vtable offsets. `QueryInterface` / `AddRef` / `Release` semantics.

**Effort: Very high.** Interfaces are the deepest OOP feature. Every part
of the type system, codegen, and runtime is touched. Recommend deferring
until class hierarchy, procedure variables, and `inherited` are stable.

---

### Inline assembler (`asm ... end`)

**AST impact:** `AN_ASM_BLOCK` containing raw token sequence.

**IR impact:** `IR_ASM` — pass-through opaque bytes. Optimization is
blocked across ASM nodes.

**Effort: High** (parsing) + **arch-specific** (encoding user-written
mnemonics). Parsing AT&T or Intel syntax into machine bytes is a
substantial project. Defer until after multi-arch target work, since
inline asm is inherently arch-bound.

---

## Summary by effort tier

### Trivial — parser/symtab only, no new AST/IR nodes
- `out` parameters
- `abstract` methods  

### Low — 1–2 new nodes or missing cases, existing IR sufficient
- `goto` / `label` (IR already has `IR_LABEL` + `IR_JUMP`)
- `AN_VIRTUAL_CALL` in IR lowering (existing gap, one missing case)
- Enumerations (symbol table registration only)

### Medium — new nodes or non-trivial type system work
- `inherited` call
- `with` statement (scope stack)
- `ReadLn` / `Read`
- Pointer expressions (`^T`, `@`, deref, nil) — IR ready; type system needed
- Sets (small ordinal range)
- Default parameter values
- Exception hierarchy (class descriptor parent chain)

### High — new runtime or structural additions
- Procedure/function variables (new type kind, `IR_INDIRECT_CALL`)
- Dynamic arrays (runtime alloc, header layout, lifetime policy)
- Sets (large/arbitrary ordinal range)
- Inline assembler

### Very high — new subsystem
- Interfaces (fat pointers, vtable layout, QueryInterface, GUID matching)
