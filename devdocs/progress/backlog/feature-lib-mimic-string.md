---
track: B
prio: 40
type: feature
blocked-by: []
summary: "Write lib/pcl/mimic_string.pas — ascii_lowercase, ascii_uppercase, digits, punctuation, whitespace, capwords. The resolver now prefers a mimic_ shim over a same-named C header, so this is the half that makes `import string` in a .npy stop finding /usr/include/string.h."
---

# `mimic_string` — the Python `string` module

- **Type:** feature (library) — **Track B** (`lib/pcl/**`)
- **Opened:** 2026-08-13 by Track A+N, finishing
  [[bug-nilpy-python-import-resolves-against-c-headers]]. That ticket's resolver
  half is done: for a `.npy` import a `mimic_` shim is now tried BEFORE the host
  C headers, so the moment this unit exists `import string` reaches it instead
  of `/usr/include/string.h`.
- **Filed rather than written** because `lib/**` is Track B's file lane.

## Verified reachable

Measured with a throwaway `lib/pcl/mimic_string.pas` on the reordered compiler:

    note: string -> mimic_string (shim, subset)

where the pinned binary, with the same file present, still pulled `string.h`
and warned about the host `features.h`. So the wiring is proven and only the
CONTENT is missing.

## Surface

What `html5lib/constants.py` (the program that found this) and ordinary code
reach for:

- `ascii_lowercase`, `ascii_uppercase`, `ascii_letters`
- `digits`, `hexdigits`, `octdigits`
- `punctuation`, `whitespace`, `printable`
- `capwords(s[, sep])`

Constants first — they are what the corpus needs and they are literally
constants. `capwords` is one line over `split`/`title`/`join`.

## Gate

A `.npy` diffed against CPython printing each constant and a couple of
`capwords` cases, plus `import string` emitting no host-header warning. Build
with `$(PXX_STABLE)`; do not rebuild the compiler.
