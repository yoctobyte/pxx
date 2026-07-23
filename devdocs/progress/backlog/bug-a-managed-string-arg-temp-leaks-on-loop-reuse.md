---
track: A
prio: 45
type: bug
---

# Managed-string arg-materialization temp leaks one handle per loop iteration

A frozen literal (or any materialized value) passed to a `const s:
AnsiString` / `const string` parameter is bound to a hidden owning temp
in IRLowerCallArg (7 sites, all `argIsManagedTemp` → `hiddenArgSym`):

```
IRAppend(IR_DEFAULT_MEM, <slotaddr>, ..., tyAnsiString);  { zero the slot }
IRAppend(IR_STORE_SYM, hiddenArgSym, value, ...);          { materialize + store }
```

The `IR_DEFAULT_MEM` zeroes the slot (plain `rep stosb` for a non-record
tyAnsiString — it does NOT release), so on every loop iteration it drops
the previous iteration's handle before the STORE's release-old can free
it. `mk('x')` in a 20k loop leaks 20k blocks (~640 KB); the same pattern
inside pyeval's PyHostCall/PyFindMethCI was the top per-exec leak the
valgrind libc-heap profile attributed to `PXXStrFromLit <- PyHostCall`.

## Reproduce

```pascal
function mk(const s: AnsiString): AnsiString; begin Result := s + '!'; end;
var i: Integer; m: AnsiString;
begin for i := 1 to 20000 do m := mk('x'); end.
```

`pascal26 -dPXX_LIBC_HEAP prog.pas out; valgrind --leak-check=summary ./out`
→ `definitely lost: 639,936 bytes in 19,998 blocks`. Passing a VAR arg
(`mk(v)`) instead of a literal → 0 lost (no materialization).

## Why the obvious fix is wrong

Removing the `IR_DEFAULT_MEM` (relying on the body-head SymIsHiddenArgTemp
nil-init + STORE's release-old) fixes the leak in isolation BUT breaks
the self-hosted compiler: it compiles uforth.py with a cwd-DEPENDENT
`dataclass ctor not registered` error (argv[0] length changes the heap
layout, exposing an uninitialized-slot read somewhere the body-head
nil-init doesn't reach). So some hidden-arg-temp slot is NOT nil before
its first STORE, and the DEFAULT_MEM's tolerate-garbage zeroing is
load-bearing. Reverted 2026-07-23 after `make bench-uforth` caught it.

## Correct fix (not yet done)

Two candidates, both need care:
1. Find WHICH slots reach STORE un-nil'd (the body-head pass is
   `CurProc >= 0` only — audit main-body and any temp allocated after the
   pass runs), guarantee nil-init for all SymIsHiddenArgTemp, THEN either
   drop the per-store DEFAULT_MEM or make IR_DEFAULT_MEM release-then-zero
   for tyAnsiString.
2. Emit the DEFAULT_MEM ONCE (hoisted to body head, like the nil-init
   pass) instead of per-call-site, so loop reuse goes straight through
   STORE's release-old.

Gate any fix on: `make test` + self-host fixedpoint + compile uforth.py
FROM THE REPO ROOT (not just via test-uforth's workdir — the cwd
sensitivity is the tell) + the valgrind probe above going to 0.
