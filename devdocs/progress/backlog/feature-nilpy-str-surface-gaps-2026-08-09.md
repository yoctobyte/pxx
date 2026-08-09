---
prio: 25
track: N
type: feature
blocked-by: []
---

# str/bytes surface gaps found by the 2026-08-09 differential sweep

- **Type:** feature (missing stdlib surface) — **Track N**
- **Found:** 2026-08-09, sweeping the str method surface against CPython with
  `tools/pydiff.py`. Every item below is **LOUD** (a compile error naming the
  method), which is why they are one low-prio ticket rather than several.
- **Owner:** —

The same sweep's one SILENT finding was split out and fixed immediately:
[[bug-nilpy-startswith-endswith-ignore-a-tuple-argument]]. That split is the
point — a silent wrong answer and a missing method are not the same kind of
work, and bundling them buries the one that matters.

## Missing, measured

| call | error |
| --- | --- |
| ~~`b.hex()`~~ | **DONE 2026-08-09** — `TPyBytes.hex`, pinned by `test/test_nilpy_bytes_hex.npy` |
| ~~`str.maketrans(a, b)`~~ | **DONE 2026-08-09** — `pystr_maketrans`, pinned by `test/test_nilpy_str_translate.npy` |
| ~~`s.translate(table)`~~ | **DONE 2026-08-09** — `pystr_translate`, same test |
| ~~`s.isascii()`~~ | **DONE 2026-08-09** — `pystr_isascii`, pinned by `test/test_nilpy_str_isascii.npy` |

## Second sweep, 2026-08-09 (formatting / sorting / float repr)

Two more LOUD gaps, same ticket:

| call | error |
| --- | --- |
| `format(0.1, ".17f")` — the BUILTIN, not `str.format` | `undefined variable (format)` |
| `sorted(xs, key=str.lower)` — an UNBOUND method as a value | `unexpected token` at `.lower` |

The second is the more interesting one: `str.lower` as a first-class value is
how `key=` is most often written for case-insensitive sorts, and it is a
different question from calling `"x".lower()` — it needs the TYPE's method to be
reachable as a value, not just through an instance. Worth checking whether the
same holds for `list.append`, `dict.get` etc. before picking a fix.

## Verified working in that sweep — do not re-file

`%` formatting with width/precision/flags (`%5d %-5d %05d %.2f %e %x %X %o %c`,
`%%`), `.format()` positional and INDEXED (`{1} {0}`) with alignment and
precision specs, f-strings including `{n:05}`, `{x!r}`, expressions and
subscripts inside the braces, `sorted` with `key=` and with tuples (STABLE, and
matching CPython's order for equal keys), and float `str()` at the awkward
sizes (`1/3`, `1e-5`, `1e16`, `123456789.123456789`, `round(1.005, 2)`,
`round(2.675, 2)`). 19 lines, all byte-identical to CPython.

## Already working — do not re-file

Verified in the same sweep: `partition`, `rpartition`, `center`, `zfill`,
`expandtabs` (both arities), `casefold`, `swapcase`, `title`, `strip` family
with and without a chars set, `removeprefix`, `removesuffix`, `split`/`rsplit`
with maxsplit, `splitlines`, `find`/`rfind`/`index`/`rindex` with windows,
`count` with a window, `ljust`/`rjust`, `join`, `replace` with a count,
`isdigit`/`isalpha`/`isspace`, `%` formatting, and f-string format specs
(`:.2f`, `:05d`, `:>4`).

## Notes for whoever picks this up

- ~~`isascii()`~~ **done** — a scan for any byte >= 128, no codepoint model
  needed. The one non-obvious part, now pinned: CPython answers **True** for the
  EMPTY string, the opposite of the `isspace`/`isdigit`/`isalpha` siblings, so
  inheriting their shape would have been wrong in exactly one place.
- ~~`hex()` on bytes~~ **done**. `bytes.fromhex` is still missing and is its
  natural pair. The two details a hand-rolled version gets wrong, now pinned:
  it ZERO-PADS to two digits per byte and it is LOWERCASE.
- ~~`maketrans`/`translate`~~ **done**, and the "decision about what the table
  IS" answered by taking CPython's exactly: a dict keyed by the ORDINAL. That
  was the right call rather than an internal representation, because it makes a
  HAND-WRITTEN dict literal a valid table and makes printing one match CPython —
  both asserted. The deleting (`None`) and multi-character forms turned out to
  be three lines, not a long tail, so all three value shapes are supported.
  Still missing from this family: `bytes.maketrans` and `str.translate` with a
  `str`-typed table (the two-argument legacy form).
- Anything here touching a codepoint model should wait for
  [[bug-nilpy-encode-ignores-the-codec]], which parks the same question.

## Gate
`.npy` per method diffed against CPython's own output, plus the "already
working" list above staying green (`test_nilpy_str_methods` covers most of it).
