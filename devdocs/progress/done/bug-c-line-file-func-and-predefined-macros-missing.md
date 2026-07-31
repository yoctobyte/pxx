---
summary: "C: __LINE__ is 0, __FILE__ is empty and __func__ is empty; __unix__, __BYTE_ORDER__, __SIZEOF_* and __CHAR_BIT__ are absent"
type: bug
track: C
prio: 55
---

# `__LINE__` / `__FILE__` / `__func__` carry nothing, and several predefines are missing

- **Type:** bug (C frontend — preprocessor predefines — **Track C**)
- **Opened:** 2026-07-31 by Track B, sweeping the last assumption class named in
  [[feature-crtl-implement-libc-assumptions]]: "feature-test macros & config
  that gate which code path a project compiles". Filed, not fixed — these are
  compiler predefines, not a library surface.

## Measured against gcc, same file

```c
printf("direct line=%d\n",   __LINE__);
printf("direct file=[%s]\n", __FILE__ ? __FILE__ : "(NULL)");
printf("direct func=[%s]\n", __func__ ? __func__ : "(NULL)");
where(__FILE__, __LINE__, __func__);
```

| | gcc | pxx |
| --- | --- | --- |
| `__LINE__` | `6` | **`0`** |
| `__FILE__` | the path | **empty string** |
| `__func__` | `main` | **empty string** |
| the same three passed as ARGUMENTS | path / 9 / main | **NULL / 0 / NULL** |

They expand to *something* — nothing fails to compile — so this is the quiet
kind of wrong. Note the argument case is worse than the direct case: what
reaches the callee is a NULL pointer, so any logger that does
`strlen(file)` or `printf("%s", file)` without a guard has a null dereference
waiting in it.

## Why this one matters more than its size suggests

`__LINE__` and `__FILE__` are not decoration — they are the entire content of
every `assert`, every logging macro, and most error-reporting in real C:

```c
#define LOG(msg) fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, msg)
#define CHECK(c) do { if (!(c)) die(__FILE__, __LINE__); } while (0)
```

Compiled here, every one of those reports `:0` from an unnamed file, or passes
NULL. A corpus that builds and runs will still produce diagnostics that point
nowhere, which is exactly the sort of thing that is not noticed until someone
is trying to debug something else.

## Also absent

Sweeping the same file for the macros projects branch on:

| macro | gcc | pxx |
| --- | --- | --- |
| `__STDC__`, `__STDC_VERSION__` | present | **present** |
| `__linux__`, `__x86_64__` | yes | **yes** |
| `__unix__` | yes | **absent** |
| `__SIZEOF_POINTER__` | 8 | **absent** |
| `__SIZEOF_LONG__` | 8 | **absent** |
| `__BYTE_ORDER__` / `__ORDER_LITTLE_ENDIAN__` | little | **absent** |
| `__CHAR_BIT__` | 8 | **absent** |

`__BYTE_ORDER__` is the dangerous one of these. Endianness is decided at
compile time by hash libraries, compression, and every wire-format parser; with
the macro absent a project silently takes its fallback branch, which is
sometimes a slower path and sometimes the WRONG one. `__unix__` is the most
commonly tested of the rest.

## Shape

Two independent pieces, and the first is worth doing on its own:

1. `__LINE__`, `__FILE__` and `__func__` should carry their real values. The
   first two are preprocessor-level; `__func__` is C99 and is a function-scope
   identifier rather than a macro, so it belongs to the parser.
2. Add the missing predefines. They are constants for a given target and can be
   emitted next to `__linux__` / `__x86_64__`, which already work. Deriving
   `__SIZEOF_*` and `__BYTE_ORDER__` from the target rather than hard-coding
   x86-64 keeps the cross targets honest.

## Gate

C tests green + self-host byte-identical, plus a regression compiling the probe
above and asserting `__LINE__` is the real line, `__FILE__` is non-empty both
directly and when passed as an argument, and `__BYTE_ORDER__` matches the
target.

## Log
- 2026-07-31 — resolved, commit 68ebab2fc.
