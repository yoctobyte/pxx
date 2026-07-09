---
prio: 55
---

# C frontend: missing `__STDC_VERSION__` predefine breaks C99 feature-detection

- **Type:** bug (C frontend / preprocessor) — **Track C** (predefined macros live in
  `compiler/cpreproc.inc`).
- **Status:** done
  (first blocker wall). Filed under recon "analyze + ticket, don't inline-fix".
- **Blocks:** [[feature-c-corpus-duktape]] (parked at this wall).

## Symptom
Compiling Duktape 2.7.0 (`src/duktape.c`, prebuilt amalgamation) with pxx fails:

```
Expected: ), but got:  (Kind: 74, Line: 15110)
  near:     duk_uintptr_t  >>>   duk__const_tval_unused
pascal26:15110: error: unexpected token ()
```

(The `>>>` is pxx's error caret, not source text.)

## Root cause (pinned, high confidence)
pxx does **not predefine `__STDC_VERSION__`**. Probed pxx's predefined macros:

| macro | pxx | note |
|-------|-----|------|
| `__STDC__` | 1 | ok |
| `__STDC_VERSION__` | **undefined** | **the bug** |
| `__STDC_HOSTED__` | undefined | minor |
| `__GNUC__` | undefined | expected (we're not gcc) |
| `__x86_64__` / `__LP64__` / `__linux__` | 1 / 1 / 1 | arch/OS detection fine |

Duktape's `duk_config.h` gates its integer-types block on C99:

```c
/* duk_config.h:1638 */
#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L) && \
    !(defined(DUK_F_AMIGAOS) && defined(DUK_F_VBCC))
#define DUK_F_HAVE_INTTYPES
#elif defined(__cplusplus) && (__cplusplus >= 201103L)
#define DUK_F_HAVE_INTTYPES
#endif
...
#if defined(DUK_F_HAVE_INTTYPES)        /* :1650 */
#include <inttypes.h>
...
typedef uintptr_t duk_uintptr_t;        /* :1680 — plus duk_uint8_t..duk_int64_t */
#endif
```

Since `__STDC_VERSION__` is undefined and `__cplusplus` is undefined, `DUK_F_HAVE_INTTYPES`
is never set → the `<inttypes.h>` block is skipped → **`duk_uintptr_t` (and the whole
`duk_*` integer typedef family) is never declared**. The compiler-specific fallback paths
(`DUK_F_GCC`, …) are also skipped (`__GNUC__` undefined). First use of the undeclared type
is the `DUK_LOSE_CONST` macro:

```c
#define DUK_LOSE_CONST(src) ((void *) (duk_uintptr_t) (src))   /* duk_config.h:2696 */
```

With `duk_uintptr_t` not a typedef name, pxx parses `(duk_uintptr_t) (&x)` as a
call-expression `(expr)(args)` instead of a cast → `Expected ), got (`.

`__STDC_VERSION__` also gates `DUK_USE_VARIADIC_MACROS` and other feature blocks
(`duk_config.h:329`), so more of duktape's config is mis-detected downstream.

## Minimal repro
The double-cast itself is fine (pxx compiles `(void*)(unsigned long)(&x)`); the bug is
purely the missing predefine. Demonstrate with the exact gate:

```c
#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L)
typedef unsigned long uptr;
#endif
int main(void){ int x=5; void *p = (void*)(uptr)(&x); return p!=0; }   /* uptr undeclared under pxx */
```

gcc: compiles. pxx: `uptr` never typedef'd, cast parses as a call → error.

## Secondary gap: `-D` not honored
`-D__STDC_VERSION__=199901L` on the pxx command line does **not** take effect (probe still
reports it undefined), so users can't even work around the missing predefine from the CLI.
Worth confirming whether pxx supports `-D<name>=<value>` at all — if not, that's a separate
small cfront ticket (command-line macro defines).

## Fix direction (Track C — do NOT apply during recon)
crtl is C99-capable (ships `<stdint.h>` / `<inttypes.h>`), so pxx should predefine
`__STDC_VERSION__` to `199901L` (C99) — arguably `201112L` (C11) — in `cpreproc.inc`
alongside the existing `__STDC__` / `__x86_64__` / `__LP64__` / `__linux__` predefines.
Consider also `__STDC_HOSTED__ 1`. Then re-probe duktape (expect a cascade of further
cfront/crtl walls behind this first one — this only unblocks config detection).

Landmine reminder (from tcc/00216 arc): no literal `{`/`}` in `{ }` Pascal comments in
compiler sources; no ErrOutput/writeln left in the byte-identical build; `make stabilize`
runs test-core (background it) then `make pin` + verify VERSION advanced.

[[feature-c-corpus-duktape]] · [[feature-c-corpus-expansion]]

## Log
- 2026-07-09 — resolved, commit c50065e8.
