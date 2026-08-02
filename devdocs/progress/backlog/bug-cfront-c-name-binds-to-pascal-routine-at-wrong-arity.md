---
track: C
prio: 55
type: bug
---

# In a mixed Pascal+C build, a C call binds to a same-named Pascal routine at the wrong arity

- **Type:** bug (C frontend, name resolution) — **Track C** (cfront)
- **Found:** 2026-08-02. Split out of
  [[bug-b-crtl-host-header-and-arity-mismatches-building-pdfgen]] once it was
  measured: the C-library half of that ticket was Track B's and is fixed, this
  half is not fixable in `lib/crtl` at all.

## Measured

Compiling a nilpy program that pulls in vendored pdfgen:

```
warning: C call to 'time' binds to the Pascal routine 'Time' which takes
  0 parameter(s), not 1 — the argument list will not arrive as written
warning: C call to 'bcmp' binds to the Pascal routine 'BCmp' which takes
  2 parameter(s), not 3 — the argument list will not arrive as written
```

The same C code compiled as a **pure C** translation unit produces **no such
warning and behaves correctly** — `time(&now)` writes its out-parameter and
matches gcc exactly. So this is specific to a build where Pascal units are in
scope: the C name resolves to a Pascal routine that merely shares its name.

## Why `lib/crtl` cannot fix it

The obvious fix was to give C its own definition so there is no external symbol
to mis-bind. That was tried: `lib/crtl/include/strings.h` now defines `bcmp` as
a **static C function** (a local definition, not an `extern` declaration). The
warning persists unchanged. So the binding is decided in the frontend ahead of,
or in preference to, a C definition that is right there in the translation unit
— which is the actual defect, and it lives in `compiler/`, not in a header.

That precedence is also the part that looks wrong on its own terms: a C
translation unit that defines a function should call *that* function, whatever
Pascal names happen to be in scope.

## Severity — not yet demonstrated to misbehave

Being straight about this, because the sibling ticket's headline bug turned out
to be something else entirely: **no wrong behaviour has been reproduced from
this yet.** pdfgen never calls `bcmp` (it uses `strcasecmp`), and the truncated
`/CreationDate` that started the whole investigation was proven to be
[[bug-cfront-sizeof-array-member-through-pointer-gives-pointer-size]] instead —
a pure-C build with no Pascal binding at all truncates identically, and
substituting one `sizeof` fixes it.

What makes it worth a ticket anyway is the shape the warning describes. If a
call really does lose arguments:

- `time(time_t *t)` dropping its pointer leaves the caller's variable
  unwritten, so it reads uninitialised memory while the return value looks fine.
- `bcmp(a, b, n)` dropping its length is a comparison that ignores how many
  bytes to compare — it can report unequal buffers as equal.

Both are silent. The compiler is asserting the call cannot arrive as written, so
either it is right (and these are latent memory/correctness bugs waiting for a
caller) or the warning is over-firing (and it is crying wolf on every mixed
build). Worth resolving either way.

## First step

Determine which. A mixed Pascal+C probe that actually calls `time(&now)` and
`bcmp(a, b, n)` and checks the results against a gcc oracle, rather than
reasoning from the warning text.

## Gate

Either a demonstrated fix (C definitions and C declarations win over an
unrelated same-named Pascal routine, with the probe matching gcc), or a
demonstration that the binding is harmless plus a narrowed warning that stops
firing on it.
