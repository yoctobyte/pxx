# Handover: Nil Python ↔ C Library Binding And Signature-Directed Inference

**Filed:** 2026-06-02 20:49 (+0200)
**Author:** session continuing the Python-ready Variant work
**Prereqs landed this session:** commits `104dfff`, `cd01ef4`, `7d3a6f6` (see below)

This brief hands off a clear, phased plan for letting Nil Python (`.npy`)
consume C libraries — proven against SQLite imported from
`/usr/include/sqlite3.h` and linked as `libsqlite3.so.0`.

## Where we are (done, committed, regression-covered)

The C-header import path drives a real library end-to-end **from Pascal**:

- `104dfff` — C **function-pointer params** (e.g. `sqlite3_exec`'s callback
  `int (*)(void*,...)`) now map to `Pointer`, not the declarator's base `int`.
  Fix in `ParseCDeclType` (`compiler/cparser.inc`): detect `(` immediately
  followed by `*`, collapse to `Pointer`, skip the `(*name)` and `(params)`
  groups. Also mapped the `sqlite3` unit to its versioned soname
  `libsqlite3.so.0` (`compiler/parser.inc` ~5476).
- `cd01ef4` — **`const char*` marshalling**. `InternStr` (`compiler/emit.inc`)
  now writes an explicit NUL after the chars so the char data at `Offset+8` is
  always a valid C string. `PChar`/`PAnsiChar` recognised as pointer types and
  as a cast; `PChar(stringExpr)` skips the inline 8-byte length prefix (`+8`)
  to hand a `const char*` to C (`compiler/parser.inc` cast + type list,
  `compiler/ir.inc` `AN_PTR_CAST` sentinel `-2`). `PChar(somePtr)` stays a pure
  reinterpret. Proof: `test/test_sqlite_crud.pas` — open/exec/prepare/step/
  `column_int`/`column_text`(+`PChar` indexing)/finalize/close, wired into
  `make test`.
- `7d3a6f6` — **Nil Python `import`**. `import name[, name]` routes to the same
  `ParseUsesUnit` resolver as Pascal `uses`. Lexer rewrites `import`→`tkUses`
  (`compiler/pylexer.inc`); `ParsePyProgram` processes leading imports before
  the body (`compiler/pyparser.inc`). Proof: `test/test_nilpy_import_sqlite.npy`
  → `sqlite3_libversion_number()` → `3045001`, wired into `make test-nilpy`.

So: **Pascal does full CRUD against the raw header. Nil Python imports the
header and calls a scalar C function.** What is NOT yet possible: full CRUD
*driven from `.npy`*, because Nil Python v1 has no pointer surface (`@`,
`Pointer`, `PChar`, indexing) and sqlite's API is pointer-heavy.

## Design decisions (locked with the user)

1. **Nil Python consumes C libraries through a Pascal binding unit**, not a C
   one. Rationale: the binding's real job is translating between the C ABI and
   PXX-native types (managed strings especially). Only Pascal is fluent in
   *both* the C ABI and the PXX runtime. A C binding can swallow pointers on
   input but **cannot manufacture a managed `string`** on return, so the
   read-back side (`column_text`) would still hand `.npy` a raw `char*`. Pascal
   converts `char*`→`string` and returns a nilpy-native value.
2. **The C-header import still happens — inside the Pascal binding** (the unit
   does `uses sqlite3`). C import is the always-needed mechanism; the
   abstraction layer is a per-frontend, temporary patch, not a general policy.
   Pascal callers need no binding — they call the raw header directly (proven).
3. **Inference is call-site-directed checking, not global/flow inference.** The
   imported C header is a complete, concrete type oracle; push known callee
   types onto untyped args/results. Do NOT build Hindley-Milner.

## Plan forward (phased, dependency-ordered)

### Step 1 — Pascal binding + Nil Python CRUD proof — DONE (commit 2ed0dd8)

Shipped as `lib/rtl/sqlitedb.pas` + `test/test_nilpy_sqlite_crud.npy`
(`make test-nilpy` → `1 alice` / `2 bob`). Notes from doing it:
- Binding API is exactly the global-handle shape below; `db_col_str` does the
  `char*`→managed-`string` conversion via `PChar` indexing.
- Nil Python resolves a bare `name()` statement as an expression needing a
  value, so binding entry points must be **functions, not procedures**
  (`db_query_done` returns the finalize rc).
- `.npy` string literals reach a Pascal `const string` param correctly — no
  coercion gap found.
- Fixed alongside: Python `print` now space-separates successive args (synthetic
  space char arg, `.npy` path only; Pascal `writeln` unchanged).

Original design (for reference):

Write `lib/rtl/sqlitedb.pas` (or `test/`-local for the proof) that `uses
sqlite3` and exposes a pointer-free, nilpy-native API. **Hide handles in module
globals** (single connection + single active statement) so `.npy` never holds a
pointer-shaped value:

```
function  db_open(path: string): Integer;   // rc; stores db in a unit global
function  db_exec(sql: string): Integer;     // rc
function  db_query(sql: string): Integer;     // rc; arms a unit-global stmt
function  db_step: Boolean;                    // sqlite3_step = SQLITE_ROW(100)
function  db_col_int(i: Integer): Integer;
function  db_col_str(i: Integer): string;      // char* -> managed string (the
                                                //   conversion only Pascal can do)
procedure db_query_done;                        // finalize
function  db_close: Integer;
```

Inside: use `PChar(s)` for `const char*` args, the global db/stmt pointers, and
read `column_text` via `PChar` indexing into a `string` (pattern proven in
`test/test_sqlite_crud.pas`). Then a `.npy` proof:

```python
import sqlitedb
db_open("/tmp/nilpy_crud.db")
db_exec("DROP TABLE IF EXISTS t;")
db_exec("CREATE TABLE t(id INTEGER, name TEXT);")
db_exec("INSERT INTO t VALUES(1, 'alice');")
db_query("SELECT id, name FROM t ORDER BY id;")
while db_step():
    print(db_col_int(0), db_col_str(1))
db_query_done()
db_close()
```

Wire both into `make test` / `make test-nilpy`. **Watch:** Nil Python local
inference (see Step 2) — `rc = db_open(...)` currently won't infer `rc`'s type
from the callee. Until Step 2 lands, annotate or assign through a typed
expression. Verify whether `.npy` string literals (`'alice'`) reach the Pascal
binding param as a proper `string`/`AnsiString`; if not, that is a small
coercion gap to fix in the call-arg path.

### Step 2 — Phase A inference: locals from callee return type (small, sound)

`PyInferExprType` (`compiler/pyparser.inc` ~238) widens over RHS *tokens* but
only consults variables (`FindSym`) — **not function return types**. When the
RHS is `name(...)`, look up `FindProc(name)` and use its `RetType`. Then
`db = db_open(path)` types `db` with no annotation. Needs no pointer depth.
~10 lines. Add a `.npy` regression that relies on call-return inference.

### Step 3 — Phase B: preserve pointer depth (the keystone)

This is what lets raw `.npy` call C without a hand-written binding for the
common cases. Today `ParseCDeclType` collapses every `*`/`**` to one
`tyPointer` — destroying the info that distinguishes an opaque handle
(`sqlite3*`) from an out-param (`sqlite3**`). The carrier already exists
(`PtrElemTk`, `AliasElemTk`, `LastTypePointerElemTk`); the C path just flattens
it. Record **one level of depth** (ptr vs ptr-to-ptr) on imported params/return.

With depth back, add **signature-directed argument adaptation** at the call
site (the checking, not magic):

- string arg + char-pointer param → auto `PChar` adapter (machinery exists).
- `char*` return + nilpy string target → auto wrap to managed `string`.
- **out-param auto-address:** param is `T**` *and* arg is a **bare local
  lvalue** → silently pass its address. Never for expressions. This removes the
  one irreducibly un-Pythonic construct (`&db`).

After Phase B, the hand-written binding shrinks to genuinely awkward cases only
(callbacks, varargs) — it is a crutch for the language era, not the language.

## Gotchas for the next session

- **Self-host fixedpoint on codegen-output changes.** Any change that alters
  emitted bytes (e.g. the `InternStr` NUL) makes the 2-stage `make` gate
  (`build` emitted by old codegen vs `verify` by new) differ once. Iterate to
  fixedpoint: `b1=oldout; b1 src b2; b2 src b3; cmp b2 b3; promote b2`. Pure
  parser/lexer changes (no codegen delta) converge in the normal 2 stages.
- **`TSymbol` field landmine** still applies — don't add fields to `TSymbol`
  (MAX_UFIELD overflow breaks self-host); use parallel arrays.
- **Managed string only via Pascal** — see decision 1. Don't try to return PXX
  strings from C.
- **Pointer-as-int** is safe on this flat ELF (load base `0x400000`, all
  addresses < 4 GB), which is why an under-typed pointer "works" by luck. Do
  not rely on it once real 64-bit addresses appear; type pointers properly.
- Nil Python v1 caps: ≤4 params, `//` not `/`, range step must be 1, param and
  result annotations required (locals inferred). See `test/test_nilpy_*_fail.npy`.

## Pointers (file:line)

- C type mapping / fn-ptr / pointer-depth flatten: `compiler/cparser.inc:138`
  (`ParseCDeclType` star loop + fn-ptr skip).
- Header→soname table: `compiler/parser.inc` (search `libsqlite3.so.0`).
- `PChar` cast + type: `compiler/parser.inc` (search `pchar`); adapter lowering
  `compiler/ir.inc` `AN_PTR_CAST` (sentinel `-2`); NUL term `compiler/emit.inc`
  `InternStr`.
- Nil Python import: `compiler/pylexer.inc` (`'import'`→`tkUses`),
  `compiler/pyparser.inc` `ParsePyProgram` (import loop) + `PyInferExprType`.
- Proofs: `test/test_sqlite_crud.pas`, `test/test_nilpy_import_sqlite.npy`.
