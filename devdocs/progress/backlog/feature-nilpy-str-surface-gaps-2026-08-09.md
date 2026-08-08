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
| `b.hex()` on bytes | `TPyBytes has no method hex` |
| `str.maketrans(a, b)` | `unsupported str method .maketrans()` |
| `s.translate(table)` | `unsupported str method .translate()` |
| `s.isascii()` | `unsupported str method .isascii()` |

## Already working — do not re-file

Verified in the same sweep: `partition`, `rpartition`, `center`, `zfill`,
`expandtabs` (both arities), `casefold`, `swapcase`, `title`, `strip` family
with and without a chars set, `removeprefix`, `removesuffix`, `split`/`rsplit`
with maxsplit, `splitlines`, `find`/`rfind`/`index`/`rindex` with windows,
`count` with a window, `ljust`/`rjust`, `join`, `replace` with a count,
`isdigit`/`isalpha`/`isspace`, `%` formatting, and f-string format specs
(`:.2f`, `:05d`, `:>4`).

## Notes for whoever picks this up

- `isascii()` is trivial: NilPy strings are byte strings, so it is a scan for
  any byte >= 128.
- `hex()` on bytes is equally small and pairs with `bytes.fromhex`.
- `maketrans`/`translate` go together and want a decision about what the
  translation table IS (CPython's is a dict keyed by ordinal). The 1:1
  byte-mapping form covers essentially all real use; the deleting and
  multi-character forms are the long tail.
- Anything here touching a codepoint model should wait for
  [[bug-nilpy-encode-ignores-the-codec]], which parks the same question.

## Gate
`.npy` per method diffed against CPython's own output, plus the "already
working" list above staying green (`test_nilpy_str_methods` covers most of it).
