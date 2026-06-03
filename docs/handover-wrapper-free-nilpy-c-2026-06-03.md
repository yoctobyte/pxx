# Handover: Wrapper-Free Nil Python ↔ C

**Filed:** 2026-06-03
**Goal:** a `.npy` program calls a C library imported from its header **directly**,
with **no hand-written Pascal wrapper unit**. Wrappers become *optional* sugar.

## Design law (locked with the user)

- Imports are usable directly from every frontend. **Hand-written wrappers are
  optional, never required.** A required wrapper (`lib/rtl/sqlitedb.pas`) counters
  the end goal.
- **Memory: whoever reserves, frees.** Never free foreign memory; borrow by
  default; **copy into our memory to keep** (then we own/free the copy); an
  explicit `close`/`free` is just a normal call. No GC needed for interop.
- Out-param auto-`&` is **in scope now** (it was only blocked while nilpy was
  pointerless; the user accepts giving nilpy a typed-handle surface). Pointer
  **depth** is already recorded (`CTypePtrDepth`), so `T**` is distinguishable
  from `T*`.

## Done (foundation)

- nilpy **holds and passes a raw C handle** — `p = malloc(64); free(p)` works,
  no wrapper. The local is inferred as a pointer from the callee return
  (callee-return inference + `ProcRetPtrElemTk/Rec`). Regression:
  `test/test_nilpy_c_pointer.npy`.
- All the C-side type machinery the arc needs already exists: typed pointers,
  pointer depth, struct field access, struct tags, `#define` int consts,
  auto `string`→`const char*`, function-return pointer-element typing.

## Delivered closure

Completed 2026-06-03 in `2b438a3`:

- Nil Python calls trailing depth-2 C out-params through return-lifting. The
  lifted expression returns the handle and drops the C integer status return.
- C `char*` returns used from Nil Python are copied into managed strings through
  the builtin `PCharToString` helper.
- `test/test_nilpy_sqlite_crud.npy` imports `sqlite3` directly and performs full
  CRUD with no `import sqlitedb`.
- `lib/rtl/sqlitedb.pas` is an optional pointer-free facade, not required for
  wrapper-free interop.

## Original remaining pieces (now closed)

### A. nilpy call with >4 arguments — **CLEARED (not a blocker)**
Verified 2026-06-03: `x = sqlite3_exec(0, "x", 0, 0, 0)` (5 args) compiles from
nilpy — the external-call path already spills args 5+. The 4-param cap is only on
`def` (defining nilpy routines), not on calls. Nothing to do here.

### B. Out-param handle: pick the ergonomic, then auto-`&` — DONE
`int sqlite3_open(const char*, sqlite3**)` — the handle comes back through a
`sqlite3**` out-param. nilpy has no `&` and no `nil`. Two options:

1. **Out-param return-lifting (recommended, Pythonic):** `db = sqlite3_open(path)`
   — the compiler allocates a hidden `sqlite3*` local, passes its address as the
   trailing `T**` out-param, and the call expression yields the handle. Decide rc
   handling (drop it, or expose a tuple/second form). Discriminate the out-param
   strictly by **depth == 2** (`CTypePtrDepth`); leave depth-1 `T*` as a normal
   pointer arg to avoid the `int*` array/buffer/out ambiguity.
2. **Explicit:** add `db = nil` (a typed-null pointer local) + auto-`&` when a
   `T**` param receives a `T*` local. Less Pythonic.

**auto-`&` mechanics:** at nilpy call-arg binding, if the param is `tyPointer`
with depth 2 and the arg is a pointer-typed local, wrap the arg in `AN_ADDR`
(LEA of the local's stack slot) instead of loading its value.

### C. Inbound `char*` → managed string — DONE
When a C function returns `char*` (e.g. `sqlite3_column_text`) and the nilpy
context wants a string, emit the copy loop (index the `PChar` to NUL into a fresh
managed string) at the call site — the mirror of the existing outbound
`string`→`const char*` auto-marshal. **Copy, per the ownership rule** (sqlite owns
the original and invalidates it on the next step).

### D. Proof — DONE
Rewrite `test/test_nilpy_sqlite_crud.npy` to `import sqlite3` directly —
open/exec/prepare/step/`column_int`/`column_text` — with **no** `import sqlitedb`.
When green, `lib/rtl/sqlitedb.pas` is demoted to an *optional example*, not a
requirement. That closes the arc.

## Gotchas
- Any codegen-output change needs the 2-stage self-host gate to stay
  byte-identical (`make bootstrap`; iterate to fixedpoint if it diverges once).
- `FindUClass`/`FindCTag`/`FindCTypedef`: the tag/typedef ones are hashed (an
  earlier linear `FindCTag` regressed GTK to O(n²)/544s). Keep lookups in any
  new hot path O(1) or accept the documented big-header slowdown.
- Test headers live in `test/*.h` (resolved via `SourceFileDir`); don't name a
  `uses` unit with a leading underscore (misresolves).

## Pointers (file:line, approximate)
- nilpy call codegen / arg passing: `compiler/pyparser.inc` (`PyParseDef` arg
  reg moves) and the AN_CALL lowering in `compiler/ir.inc`.
- Pointer depth/element: `ParseCDeclType` in `compiler/cparser.inc`
  (`CTypePtrDepth/CTypeElemTk/CTypeElemRec`).
- Outbound string→const char* adapter: `compiler/ir.inc` AN_CALL arg loop (`+8`).
- Return pointer-element + call-result postfix: `ApplyCallResultPtrSuffix` and
  `ResolveNodeRec` AN_DEREF/AN_CALL case.
- Related memory: `[[project_nilpy_c_binding_arc]]`, `[[project_c_header_import_arc]]`.
