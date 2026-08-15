---
track: B
prio: 40
type: feature
blocked-by: []
summary: "Write lib/pcl/mimic_string.pas — ascii_lowercase, ascii_uppercase, digits, punctuation, whitespace, capwords. The resolver now prefers a mimic_ shim over a same-named C header, so this is the half that makes `import string` in a .npy stop finding /usr/include/string.h."
status: done
owner: track-b-bughunt
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

## 2026-08-15 — mostly ALREADY DONE; the rest landed. Rationale corrected.

Re-opened after the user questioned the ticket:

> *"i see one that makes little sense — feature-lib-mimic-string. why would any
> python application do that."*

Measured, and the challenge was right — for a sharper reason than it assumed.

### It was already ~90% written

`lib/rtl/mimic_string.pas` landed in **`3043a9149`** ("mimic_string so `import
string` resolves"), and `import string` already compiled and matched CPython.
The ticket sat at prio 40 describing work that had mostly shipped.

**Note the path:** the ticket says `lib/pcl/mimic_string.pas` and the file is in
`lib/rtl/`. Anyone checking `lib/pcl` — as the ticket instructs — sees nothing
and concludes it is unwritten. That mismatch is most of why this went stale.

### The stated rationale is wrong; the real one is transitive

Almost no application writes `import string`. What does is the **standard
library** — 10 modules on CPython 3.12, excluding its test tree:

`logging`, `urllib.request`, `http.cookies`, `email._header_value_parser`,
`email.quoprimime`, `email._encoded_words`, `tomllib._parser`, `cmd`, `crypt`,
`nturl2path`

and they use exactly this surface: `ascii_letters`, `digits`, `hexdigits`,
`punctuation` — plus `string.Template` in `logging`. So a program reaches it by
writing `import logging`, never naming `string` at all.

**But that path is not live yet.** `import logging` fails outright today —
`error: import: no unit named logging and no shim mimic_logging` — so the real
justification cannot fire. The ticket's own driver, `html5lib/constants.py`, is
not checked into this repo either (`external/` holds only `synapse`). Both facts
argue the prio was too high, not that the work is wrong.

### What was actually missing, now landed

- **`printable`** — absent; `string.printable` was `undefined variable`.
- **`capwords(s, sep)`** — the two-argument form; only the no-sep one existed.

`capwords(s, sep)` is a **different function, not a variation**, and needed
measuring rather than deriving. CPython is
`(sep or ' ').join(map(str.capitalize, s.split(sep)))`, so with an explicit sep
the split neither collapses runs nor strips:

| call | result |
| --- | --- |
| `capwords('a--b', '-')` | `A--B` (empty field kept) |
| `capwords('-a-', '-')` | `-A-` (leading/trailing kept) |
| `capwords('a b-c d', '-')` | `A b-C d` — `str.capitalize()` lower-cases the REST, and the `b` is not a field start |
| `capwords('a__b', '__')` | `A__B` (multi-character sep) |
| `capwords('', '-')` | `''` |

The no-sep form does the opposite on every one of those, which is why the shared
part is only `CapitalizeField`.

### Split out rather than left buried

**`string.Template` is not in this ticket's surface and should never have been
absent from it** — it is what `logging` uses, and it is a class with
`$`-placeholder substitution (`substitute` / `safe_substitute`), not a
constant. Filed as [[feature-lib-mimic-string-template]], sequenced behind
whatever brings `logging` in, since nothing can reach it before then.

### Gate

All 13 rows of the surface diffed against CPython 3.12 — every constant,
`whitespace`/`printable` by `repr`, and both `capwords` forms including the five
separator edge cases above — identical. `make lib-test` green against v300.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
