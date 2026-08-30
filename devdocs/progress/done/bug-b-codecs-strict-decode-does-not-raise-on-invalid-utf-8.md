---
track: B
prio: 55
type: bug
blocked-by: []
summary: "`codecs.decode(b'\\xff\\xfe', 'utf-8')` returns U+FFFD replacements instead of raising UnicodeDecodeError. `strict` is the DEFAULT, so invalid UTF-8 is silently repaired everywhere rather than reported, and `errors='ignore'` is ignored too — all three policies behave as `replace`."
status: done
owner: frankB
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

## 2026-08-30 (frankB) — FIXED. There was no validity walk at all.

### Root cause

`Utf8Decode_` was a **pure byte copy**:

```pascal
for i := 0 to input.count - 1 do s := s + Chr(input.at(i));
```

It consulted neither the input's validity nor `errors` — the parameter was not
even passed to it. So invalid bytes were copied through and rendered as U+FFFD
downstream, which made all three policies *look* like `replace`, and `strict`
— CPython's **default** — never raised. The unit header described "a copy plus
a validity walk"; the walk did not exist.

### The fix, and why the lenient walker stays lenient

Added `Utf8SeqAt`, a real UTF-8 validator returning the sequence length, or the
negated **maximal subpart** length when invalid, with the range restrictions
that the naive lead-byte rule misses: `C0/C1` and `F5..FF` always invalid,
`E0 A0..BF` and `F0 90..BF` rejecting overlongs, `ED 80..9F` rejecting the
surrogate range, `F4 80..8F` rejecting above U+10FFFF.

`CpAt`, the unit's other walker, is **deliberately left lenient** — its job is
to iterate the RTL's own strings without policing them, and this one's job is
to police bytes. Two callers, two contracts, one scanner each; sharing them
would make one of the two wrong. Stated in the code so the next reader does not
"unify" them.

### Maximal subpart is the part that would have shipped wrong

It is not enough to reject invalid input. CPython emits **one** U+FFFD for a
truncated-but-consistent sequence and **one per byte** for a run of nonsense:

| input | replacements | why |
| --- | --- | --- |
| `b'\xe2\x82'` | 1 | two bytes still on a valid path when input ran out |
| `b'\x80\x80'` | 2 | neither byte can begin anything |
| `b'\xed\xa0\x80'` | 3 | `\xed` cannot take `\xa0`, then two lone continuations |
| `b'\xf4\x90\x80\x80'` | 4 | `\xf4` cannot take `\x90`, then three lone continuations |

A decoder with the right verdict and the wrong count passes a naive "does it
reject?" test and corrupts **every** `replace` decode. These counts were
measured off CPython 3.12, not derived from the spec.

### Verification

**81/81 cases match CPython by code point** — 27 inputs × 3 policies, covering
valid sequences at every length and at both surrogate boundaries, overlongs at
2/3/4 bytes, the surrogate range, above-U+10FFFF, `F5` leads, truncations, lone
continuations, and damage surrounded by valid text.

Compared **by code point, not by `repr()`** — `repr` here escapes only below
U+0080 while CPython escapes by Unicode printability, so a repr-based
comparison reports failures on correct values. That divergence is real and is
filed separately as
[[compat-n-repr-does-not-escape-non-printables-above-u007f]]; separating them
is what let this ticket close on the decoder rather than on the renderer.

### Two more findings fell out of writing the differential

- **BOM constants had the wrong TYPE** — `AnsiString` where CPython has
  `bytes`, so `data.startswith(codecs.BOM_UTF8)` answered **False** for data
  that begins with a BOM, silently defeating the encoding detection the header
  says they exist for. `BOM_UTF8` was doubly wrong: `#$EF#$BB#$BF` is a
  well-formed encoding of U+FEFF, so as a string it held **one** character and
  `len()` said 1 where CPython says 3. Fixed here (they are now `TPyBytes`
  built in the unit's init block); no other consumer in the tree.
- [[bug-n-the-hex-string-escape-emits-a-raw-byte-not-a-code-point]] — filed,
  Track N. It presented as a `codecs.encode` failure and is not one.

### Gate

`test/lib_mimic_codecs.npy`, **83 checks, byte-identical** to CPython, wired
into `lib-test`. Phase 1 of
[[feature-b-sweep-mimic-shims-against-cpython]] is complete.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
