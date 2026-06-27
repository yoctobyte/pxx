# C: global struct-array initializer with a fn-ptr cast field stores garbage

- **Type:** bug (C frontend → global aggregate init / codegen) — Track C
- **Status:** done
- **Owner:** Track CA
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), while fixing the fn-ptr cast-call
  wall. Banked as a runtime follow-up; sqlite's `aSyscall[]` table needs it.
- **Closed:** 2026-06-27

## Symptom

A file-scope struct-array initialised with a function-pointer cast field does
not store the function address; calling through the field segfaults.

```c
typedef void (*syscall_ptr)(void);
static int posixOpen(const char *z, int f, int m){ return 42; }
static struct unix_syscall { const char *zName; syscall_ptr pCurrent; }
aSyscall[] = {
  { "open", (syscall_ptr)posixOpen, 0 },
};
#define osOpen ((int(*)(const char*,int,int))aSyscall[0].pCurrent)
int main(void){ return osOpen("x", 0, 0); }   /* SIGSEGV */
```

The **runtime-assigned** equivalent works (exit 42):

```c
int main(void){ aSyscall[0].pCurrent = (syscall_ptr)posixOpen; return osOpen("x",0,0); }
```

So the indirect-call lowering is fine (fixed in the cast-call commit); the gap is
the **global aggregate initializer** not materialising a fn-pointer-cast element
(`(syscall_ptr)posixOpen`) into the data image — the field is left zero/garbage.

## Likely shape of the fix

The C global-init path (PendingInit / data-image emit) must handle a struct
field initialised to a cast-of-function-name: emit a relocation to the proc's
body address (like a plain `&func` / `func` initializer). Check how a non-cast
fn-pointer global field initializer is handled and extend the cast case.

## Fix

`ParseCGlobalVarDecl` already had a `PendingInitKind=2` proc-address path for a
pointer field initialized from a bare function name. Added a parser-local
recognizer for `(fn_pointer_type)function_name` while walking file-scope
struct-array aggregate initializers, so the casted form records the same
proc-address PendingInit and `CompilePendingGlobalInits` emits an `AN_PROCADDR`
assignment before `main`.

## Regression

Added `test/cglobal_struct_array_fnptr_cast_b98.c`, wired after b97 in
`make test-core`.

## Acceptance

- The repro returns 42 (no segfault).
- sqlite's `aSyscall[]` syscall table dispatches; the sqlite compile now
  advances to the existing `fsync` header wall at `sqlite3.c:31615`.
- Regression b98 passes; compiler self-host is byte-identical.
