---
track: B
prio: 55
type: bug
blocked-by: []
summary: "`codecs.decode(b'\\xff\\xfe', 'utf-8')` returns U+FFFD replacements instead of raising UnicodeDecodeError. `strict` is the DEFAULT, so invalid UTF-8 is silently repaired everywhere rather than reported, and `errors='ignore'` is ignored too — all three policies behave as `replace`."
status: backlog
owner: unassigned
---

# `codecs` strict decode does not raise on invalid UTF-8, and `ignore` is ignored

- **Type:** bug (library) — **Track B** (`lib/rtl/mimic_codecs.pas`).
- **Filed:** 2026-08-30 by frankB during the `mimic_` shim differential sweep
  (`feature-b-sweep-mimic-shims-against-cpython`).
- Measured against **pin v395** (`aa78a7faf63a`).

## This is the silent-wrong-behaviour class

`strict` is CPython's **default** error policy. A caller that writes
`codecs.decode(data, 'utf-8')` and expects to hear about malformed input hears
nothing and receives a plausible string. Detecting invalid encoding is the
entire reason that default exists, so this is not a diagnostics difference — the
program takes a different branch.

## Measured, `def`-based probe (not `lambda` — see the note below)

| call | pxx v395 | CPython 3.12 |
| --- | --- | --- |
| `decode(b'\xff\xfe', 'utf-8')` (strict, default) | `'��'` | **UnicodeDecodeError** |
| `decode(b'\xff\xfe', 'utf-8', 'replace')` | `'��'` | `'��'` ✓ |
| `decode(b'\xff\xfe', 'utf-8', 'ignore')` | `'��'` | `''` |
| `decode(b'\xc3', 'utf-8')` (truncated lead) | `'�'` | **UnicodeDecodeError** |

So **all three policies behave as `replace`** on the utf-8 path: `strict` does
not raise and `ignore` does not drop.

The ascii path, by contrast, is correct — `decode(b'\xff', 'ascii')` raises,
`'replace'` gives U+FFFD, `'ignore'` gives `''`, all matching CPython. So the
policy plumbing exists and works; the utf-8 decoder does not consult it.

## Likely cause, from the shim's own header

`mimic_codecs.pas:180` documents the UTF-8 walker as deliberately lenient:

> *"A malformed lead byte is answered as itself and consumes one byte, which
> keeps the walk total: this unit's job is to be a codec, not to police the
> RTL's own strings."*

That is a reasonable rule for an internal walker and the wrong rule for
`codecs.decode`, which is precisely the place whose job **is** to police bytes.
The fix is probably not to change the walker but to have the decode entry point
detect malformation and apply the requested policy — so the internal callers
keep their lenient total walk and the public codec gets CPython's semantics.
Worth checking whether both arms can share one scanner that reports *where* it
failed, rather than growing a second walker
(`normalise-dont-special-case.md`).

## Note on instrument reliability

The first probe here used `lambda` thunks and produced wrong readings for the
bytes-valued rows; `lambda` returning a captured heap value yields `None` in
this dialect ([[bug-n-a-lambda-returning-a-captured-heap-value-yields-none]]).
The table above was re-measured with `def`. **Use `def` in NilPy probes until
that closes.**

## Gate

The same differential named in
[[bug-b-codecs-encode-segfaults-for-every-encoding-except-utf-8]] — this shim
has none today. Both tickets should probably be taken together, since one
differential covers them and the encode crash blocks writing the encode half.
