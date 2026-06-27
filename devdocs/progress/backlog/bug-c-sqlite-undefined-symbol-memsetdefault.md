# C: sqlite runtime undefined symbol `sqlite3MemSetDefault`

- **Type:** bug (C frontend / runtime / symbol resolution) — Track C
- **Status:** backlog
- **Owner:** unassigned
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
