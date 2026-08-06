---
summary: "cpyext PyErr_Format delegates to vsnprintf, which does not know CPython's %U / %S / %R / %A object specifiers — so an extension's own error message reads \"unexpected keyword argument '%U'\", and any specifier AFTER one of them reads a misaligned argument."
type: bug
track: N
prio: 50
status: done
owner: claude-A-N
---

# `PyErr_Format` prints CPython's `%U` / `%S` / `%R` specifiers literally

- **Type:** bug — Track N (cpyext runtime). Files: `lib/cpyext/src/pyruntime.c`.
- **Found:** 2026-08-06, while wiring M5b keyword arguments — an intentionally
  wrong keyword produced a message with a literal `%U` in it.

## Observed

Calling a Cython-generated `cysub(a, b)` with an unknown keyword `c` reaches
Cython's own keyword parser, which is correct, and it reports:

```
cysub() got an unexpected keyword argument '%U'
```

CPython says `... unexpected keyword argument 'c'`. The name is *in* the
arguments; only the formatting drops it.

## Cause

```c
PyObject *PyErr_Format(PyObject *exc, const char *format, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, format);
    vsnprintf(buf, sizeof(buf), format, ap);   /* <-- */
    ...
```

`vsnprintf` is the C library's formatter. CPython's `PyErr_Format` accepts a
SUPERSET of printf: `%U` (a `PyObject*` str), `%S` (`str()` of any object), `%R`
(`repr()`), `%A` (`ascii()`), plus `%V`. glibc does not know them, prints them
literally, and — the part that is worse than a cosmetic blemish — **consumes no
argument for them**, so every specifier after a `%U` reads the wrong `va_arg`.
A message mixing `%U` with `%d` therefore prints a garbage number, not just a
literal `%U`.

`PyErr_WarnFormat` immediately below has the identical body and the identical
bug.

## Fix

Replace the `vsnprintf` delegation with a small hand-rolled formatter over the
format string, handling what CPython documents for these two functions:

- pass-through: `%s`, `%c`, `%d`, `%i`, `%u`, `%x`, `%%`, the `l` / `ll` / `z`
  length modifiers, `%p`
- object forms: `%U` (the object must be a str — use its bytes directly),
  `%S` / `%R` / `%A` (needs `PyObject_Str` / `PyObject_Repr`; if those are not
  available for a given object kind, fall back to the type name rather than
  emitting nothing, so the message still identifies something)

Keep it one function used by both `PyErr_Format` and `PyErr_WarnFormat` so they
cannot drift.

## Why 50 and not higher

It never produces a wrong ANSWER — only a degraded diagnostic — and no test
asserts on an extension's message text today. It is worth doing because the
messages are exactly what someone debugging a newly-compiled extension reads
first, and the misaligned-`va_arg` half means a message can currently be
actively misleading rather than merely vague.

## Gate
`make test-nilpy` green plus a probe extension calling `PyErr_Format` with each
supported specifier, including `%U` followed by `%d` (the misalignment case),
diffed against the same calls under CPython.

## Log
- 2026-08-06 — resolved, commit fdc714609.
