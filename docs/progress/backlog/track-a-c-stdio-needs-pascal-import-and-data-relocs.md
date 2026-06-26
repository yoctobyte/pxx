# C stdio (printf family) blocked — needs Pascal import + global data relocs

- **Type:** Track A (shared compiler internals: cross-language linking, ELF
  data relocations, global initializer lowering). Raised by Track C (C frontend,
  worktree `feat/cfront`) while building the `lib/crtl` stdio veneer for lua.
- **Opened:** 2026-06-26
- **Goal it unblocks:** pxx-compiled lua RUNS with output. lua's print path is
  `lua_writestring` → `fwrite(s,1,n,stdout)` and number formatting →
  `snprintf("%.14g",...)`. The printf/snprintf **formatting engine** is pure C
  and is Track C's to write (`lib/crtl/src/stdio.c`) — *that part needs no
  compiler change*. What it cannot do without Track A is reach a byte sink and
  define the `stdout`/`stderr`/`stdin` data symbols.

## Design constraint (authoritative)
C stdio must stay **libc-free** and **reuse the EXISTING Pascal RTL IO** (C
imports Pascal libraries; the Pascal RTL already does PAL-aware file/console IO —
`PalBackendWrite(handle, buf, len)` in
`lib/rtl/platform/posix/platform_backend.pas`). So the C veneer is a thin C-ABI
binding onto the Pascal RTL, not a second IO path. See
`bug-c-libc-data-symbol-stdio.md`.

## Blockers found (each reproduced on current `feat/cfront` compiler)

### 1. C cannot import / link a Pascal routine  ← core blocker
A C `extern` referencing a Pascal symbol is emitted as an undefined **dynamic
(libc-style) import**; nothing links the Pascal unit in, so it fails at runtime.
This is the mechanism "C imports Pascal libraries" depends on.

```c
extern int AddTwo(int a, int b);          /* AddTwo is a Pascal unit function */
int main(void){ return AddTwo(40, 2); }
```
```
$ pascal26 -Fu<dir-with-myrtl.pas> cimp.c cimp26      # compiles "ok"
$ ./cimp26
symbol lookup error: ./cimp26: undefined symbol: AddTwo   # want 42
```
Need: a way for a C program to pull + link a Pascal unit (a C-visible `uses`
equivalent / cross-language symbol binding) so `fwrite`→`PalBackendWrite`
resolves internally. Without this, the "reuse Pascal RTL" design cannot be wired
at all.

### 2. No libc-free byte sink for C
Today the only working C byte output is the `printf`→`AN_WRITE` frontend
intercept (inline write syscall, format args ignored beyond the literal).
`write()`/`read()` *do* resolve — but only as **libc.so.6 dynamic imports** (the
exe is `NEEDED libc.so.6`), which violates the libc-free constraint. And libc
imports are unreliable anyway: `memcpy` imported from libc **segfaults**.
```c
extern void *memcpy(void*,const void*,unsigned long);
char b[8]; int main(void){ memcpy(b,"abc",4); return b[1]; }   /* SIGSEGV */
```
Need: a libc-free fd write/read usable from C — either (1) once blocker #1 is
solved, bind `write`/`read` to the Pascal RTL `PalBackend*` (PAL-aware:
posix syscall / ESP-IDF), or (2) a `__pxx_write`/`__pxx_read` intrinsic that
emits the syscall the way `AN_WRITE` already does. Prefer (1) — one shared IO
layer with Pascal.

### 3. Global pointer initialized to address-of-global segfaults (data reloc)
```c
typedef struct { int fd; } F;
static F obj = { 7 };
F *p = &obj;                 /* relocation to obj's address */
int main(void){ return p->fd; }   /* SIGSEGV; want 7 */
```
Scalar/struct/union global init already works; an **address-of-global static
initializer** (needs an ELF data relocation) does not. Blocks the standard
`FILE *stdout = &__stdout_obj;` definition of the std streams.

### 4. Global array initializer ignored → BSS-zeroed (ANY element type)
Every initialized global **array** drops its data and lands in BSS zeroed — not
just arrays of struct. Scalar-element too:
```c
static int counts[4] = { 10, 20, 30, 40 };
int main(void){ return counts[0] + counts[3]; }   /* returns 0; want 50 */
```
```c
struct KV { const char *name; int v; };
static struct KV tbl[] = { {"a",1}, {"b",2}, {"c",3} };
int main(void){ return tbl[0].v + tbl[2].v; }       /* returns 0; want 4 */
```
(`bss=12B`/`24B`, `data` holds only the string literals.) Reading a `.name`
pointer back out then segfaults on the zeroed slot. This is lua's static
`luaL_Reg` registration-table pattern. SINGLE scalar/struct/union global init
work; an **array** initializer does not, regardless of element type. The
existing `test/cglobal_array_init_b28.c` only checks brace-skip *parse* survival
(returns 42 from a local) — it never reads the global array data, so the gap is
unguarded.

### 5. (already filed) `bug-c-double-vararg` — `%f` reads 0
printf `%f`/`%g` need the double-in-vararg fix. Engine code will be correct C;
blocked at runtime until that lands. See `bug-c-double-vararg.md`.

## What Track C does on its side (no compiler change)
- Write the full printf/snprintf/sprintf/fprintf formatting engine + the
  fwrite/fputs/fputc/puts/putchar mapping in `lib/crtl/src/stdio.c`, funneled
  through ONE byte-sink call (so blocker #2 is a single binding point).
- Name-mapping of the C stdio API → the sink + the Pascal RTL handles.

## Acceptance
- A C program can call a Pascal RTL routine and link it (blocker #1).
- C stdout/stderr/stdin defined without an `&global` static init, OR blocker #3
  fixed so the standard definition works.
- A C global `array-of-struct` initializer reaches the program (blocker #4).
- Resulting lua exe prints with **no `NEEDED libc.so.6`** for IO.
