---
track: B
prio: 45
type: bug
---

# Building pdfgen: `strings.h` comes from the host, and `time`/`bcmp` bind at the wrong arity

- **Type:** bug (crtl, silent wrong behaviour) — **Track B** (`lib/crtl`)
- **Found:** 2026-08-02, while re-measuring
  [[feature-lib-pxxpdf-reportlab-compat]]. Sibling of
  [[bug-b-crtl-math-constants-missing-silently-zero]], which was the third
  warning in the same build and turned out to be a real silent-value bug — so
  these two deserve the same treatment rather than being read as noise.

## Measured

Compiling a nilpy program that pulls in vendored pdfgen emits three warnings.
One (`M_SQRT2`) is fixed. The other two:

```
pascal26:53: warning: #include <strings.h> resolved from the host system
  (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list,
  M_SQRT2) may silently misbehave
pascal26:2772: warning: C call to 'time' binds to the Pascal routine 'Time'
  which takes 0 parameter(s), not 1 — the argument list will not arrive as
  written
pascal26:5483: warning: C call to 'bcmp' binds to the Pascal routine 'BCmp'
  which takes 2 parameter(s), not 3 — the argument list will not arrive as
  written
```

## Why each is a real defect, not noise

**`strings.h` missing from `lib/crtl/include/`.** The build silently falls back
to the host's `/usr/include/strings.h`. That is a self-hosting hole (the output
depends on the build box's libc headers) and the compiler's own warning text
says what it can cost — and it names `M_SQRT2` as the example, which is exactly
the bug that was just confirmed real in this same build. `strings.h` is small:
`bcmp`, `bcopy`, `bzero`, `index`, `rindex`, `ffs`, `strcasecmp`, `strncasecmp`.

**`time` bound at arity 0 vs 1.** C's `time(time_t *t)` takes a pointer and
*also* returns the value; Pascal's `Time` takes none. "The argument list will
not arrive as written" means a caller passing a pointer gets it dropped — so
`time(&now)` leaves `now` unwritten, and the caller reads uninitialised memory
while the return value looks fine. Silent, and in date/timestamp code the wrong
value is rarely obviously wrong. (pdfgen calls it for the PDF creation date.)

**`bcmp` bound at arity 2 vs 3.** `bcmp(a, b, n)` drops its length. A
comparison that ignores how many bytes to compare is a correctness bug of the
worst kind — it can return "equal" for unequal buffers.

Both bindings are cases where the C name resolves to a Pascal routine of the
same name but a different signature; the warning is correct that the call
cannot arrive as written.

## Not yet measured

Whether pdfgen's *behaviour* is actually wrong today, or whether these paths
happen not to be reached with the arguments that matter. That is the first
thing to do — a probe per call, against a gcc-built oracle, rather than
reasoning from the warning text. The `M_SQRT2` one looked equally survivable
and was not.

## Fix shape

- Add `lib/crtl/include/strings.h` with the BSD string surface, so the host
  header is never reached.
- Give `time` and `bcmp` C-side declarations with the right signatures so they
  bind to something that takes the arguments C passes, rather than to a
  same-named Pascal routine with a different arity.

## Gate

The pdfgen build emits **zero** warnings, plus a differential probe per fixed
call against gcc. `lib/crtl` builds for every target while `gate.sh lib` is
x86-64 only, so cross-check i386/aarch64/arm32 as well —
see [[frank2-crtl-changes-need-cross-check]].
