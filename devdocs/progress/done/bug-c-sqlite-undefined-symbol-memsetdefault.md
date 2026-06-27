# C: sqlite runtime undefined symbol `sqlite3MemSetDefault`

- **Type:** bug (C frontend / runtime / symbol resolution) — Track C
- **Status:** DONE (2026-06-27)
- **Owner:** Track C+A
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), immediately after the
  function-pointer-array global wall
  ([[bug-c-null-pointer-literal-call-arg-sqlite]]) was cleared.

## Symptom

`sqlite3.c` now fully compiles and links; a small driver

```c
int main(void){
  sqlite3 *db;
  int rc = sqlite3_open(":memory:", &db);
  if (rc==0) sqlite3_close(db);
  return rc;
}
```

builds to an executable but faults at run time before producing output:

```text
symbol lookup error: ...: undefined symbol: sqlite3MemSetDefault
```

## Notes

`sqlite3MemSetDefault` is a real sqlite memory-subsystem routine, selected at
build time by the `SQLITE_SYSTEM_MALLOC` / `SQLITE_MEMDEBUG` / `MEMSYS*`
configuration. Under the amalgamation's default config one of the `mem*.c`
implementations defines it; the symbol is reachable (referenced by
`sqlite3MallocInit`) but its definition is apparently behind a preprocessor
branch the cfront preprocessor is dropping, so the linker emits an undefined
extern instead of binding it internally.

Likely a `#ifdef`/`#if defined(...)` (or a `SQLITE_DEFAULT_MEMSTATUS`-gated)
block whose definition is not being emitted — investigate which `mem1/mem2/...`
arm should be active and whether the cfront preprocessor evaluates that
condition the same way the C amalgamation expects. This is the next sqlite
runtime wall; the compile/lowering path is clean.

## Acceptance

- `sqlite3MemSetDefault` (and any sibling memory-subsystem routines exposed the
  same way) resolve internally; no undefined-symbol fault at startup.
- `sqlite3_open(":memory:")` + `sqlite3_close` runs to completion.

## Resolution (2026-06-27, Track C+A)

Not a symbol-resolution bug — a **preprocessor arithmetic** bug. sqlite selects
its allocator with:

```c
#if defined(SQLITE_SYSTEM_MALLOC) + defined(SQLITE_WIN32_MALLOC) \
  + defined(SQLITE_ZERO_MALLOC) + defined(SQLITE_MEMDEBUG) == 0
# define SQLITE_SYSTEM_MALLOC 1
#endif
```

The cfront `#if` evaluator (`cpreproc.inc`) had **no additive / multiplicative /
shift / bitwise levels at all** — its chain was `Or → And → Compare → Unary →
Atom`. So `a + b`, `a & b`, `a << b` silently dropped everything after the first
operand: `0 + 5` evaluated to `0` (the `+ 5` was never consumed; `5 + 0` only
"worked" because the left operand `5` is already truthy). The `defined()+…==0`
sum therefore never fired, `SQLITE_SYSTEM_MALLOC` stayed undefined, the `mem1`
allocator block (`#ifdef SQLITE_SYSTEM_MALLOC`) — which defines
`sqlite3MemSetDefault` — was excluded, and the linker emitted an undefined
extern.

Fix: implemented the full C `#if` constant-expression precedence hierarchy in
`cpreproc.inc` — unary (`! ~ - +`) → `* / %` → `+ -` → `<< >>` → `< <= > >=` →
`== !=` → `&` → `^` → `|` → `&&` → `||`, each left-associative, with two-char
guards so `&`/`&&`, `|`/`||`, `<`/`<<`, `>`/`>>` don't collide. Self-host
byte-identical (C-only code path); `make test` green. Regression
`test/cpreproc_if_arith_b110.c` (exit 42).

`sqlite3MemSetDefault` now resolves. `sqlite3_open(":memory:")` advances to the
next wall — `undefined symbol: fabs` (libm math functions aren't getting a
DT_NEEDED), filed as [[bug-c-sqlite-math-libm-not-linked]].
