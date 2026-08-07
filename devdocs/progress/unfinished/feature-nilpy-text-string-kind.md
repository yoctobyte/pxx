---
track: N
prio: 55
type: feature
blocked-by: feature-a-managed-block-kind-word
summary: "Phase 2 of multi-type strings: stamp TextString/ByteString kinds and make NilPy str count CHARACTERS — len, indexing, slicing, find and reverse — over the shared byte substrate, with the ASCII flag keeping the common case O(1)"
---

# NilPy `str` counts characters, not bytes (phase 2)

- **Type:** feature (semantics) — **Track N**
- **Design:** `devdocs/dev/managed-block-header.md`.
- **Blocked by** [[feature-a-managed-block-kind-word]] — do not start before that
  is **pinned**. The pin is what guarantees this never meets an old-offset
  binary.
- Supersedes the fork in `decide-nilpy-str-is-bytes-or-codepoints`, which is
  decided: a NilPy `str` is a sequence of code points; a Pascal `AnsiString`
  stays bytes; they are two kinds of one representation, not one type.

## The defect this closes

Measured at `8f1852f27`, `s = "héllo"`, `t = "日本語"`:

| expression | CPython | pxx |
| --- | --- | --- |
| `len(s)` | 5 | 6 |
| `s[1]` | `é` | `\xc3` — **invalid UTF-8 on stdout** |
| `s.find("l")` | 2 | 3 |
| `s[::-1]` | `olléh` | **byte-reversed, invalid UTF-8** |
| `len(t)` / `t[0]` | 3 / `日` | 9 / `\xe6` |
| `ord("€")` | 8364 | `TypeError: … string of length 3 found` |

The two rows that emit **malformed UTF-8** are the urgent part; they are worse
than any end state and worth fixing first.

## Why this is a defect and tuple-mutability is not

`devdocs/dev/nilpy-semantics-divergences.md` accepts a mutable tuple because no
working CPython program can observe it. Ordinary working code that slices or
measures non-ASCII text observes every row above. Different side of that line.

## What must NOT change

**Pascal is already correct and must stay "wrong."** FPC counts code units —
`Length` on an `AnsiString` is bytes, and on a `UnicodeString` it is UTF-16 code
units, so a non-BMP character counts 2 and `s[1]` can be half a surrogate pair.
Being *more* correct than FPC would be a compat bug. This is why the substrate
could not simply be changed: the two frontends have genuinely different correct
answers, which is what the kind word exists to express.

## Layout constraint you must obey

Every meaningful field lives in the **low 32 bits** of the meta word:
`BlockKind(8) | Flags(8) | KindData0(8) | KindData1(8)`, bits 32–63 reserved.
Spending the upper half would permanently foreclose
[[feature-a-shrink-managed-header-on-32-bit]], because a packed ILP32 header
makes the meta word 32 bits wide. Consequently `KindData0` holds a small
**encoding enum** (0 = bytes, 1 = UTF-8, 2 = UCS-2, 3 = UCS-4), not a raw
codepage — `CP_UTF8` = 65001 does not fit in 8 bits, and the enum is the better
field regardless.

Also rename the phase-1 offset constant `PXX_HDR_KIND` → `PXX_HDR_META` in this
ticket's first commit. Nothing reads it yet, and this ticket re-pins anyway.

## The work

1. **Stamp kinds at every materialisation site** — the literal→managed
   conversion, concat, `SetLength`, and the pylib constructors. The static type
   is known at each: Pascal context → `ByteString`, NilPy context → `TextString`.
2. **Propagate through pylib.** The ~79 `pystr_*` functions *construct* new
   blocks; every `Result := …` must carry the kind forward or the result
   silently degrades to the default. This is the bulk of the work and it is the
   part that is easy to under-estimate.
3. **Character-aware public positions** for `TextString`: `len`, indexing,
   slicing, `find`/`index`/`rfind`, reverse, `charlist`, padding widths,
   `ord`/`chr`. Internal offsets stay bytes.
4. **Set the `ASCII` flag** at construction when no byte is ≥ 0x80. Then `len`
   and indexing stay **O(1) and byte-identical to today** for the overwhelmingly
   common string; only genuinely non-ASCII text pays.

## Keep the coordinate system coherent

Byte and character answers agree for `in`, `count`, `split`, `==`, `+`, and —
measured — offsets round-trip today: `s[s.find("w"):]` is correct across
multi-byte characters, because UTF-8 is self-synchronising. That is *why* `find`
must move to character offsets in the same change as indexing. Moving one and not
the other breaks programs that currently work.

## Static context wins

Kinds live on shared refcounted blocks, so a kind cannot be flipped at a boundary
without copying. Where a static type exists it decides; the kind answers only
where the static type is lost (variant, container element, generic/untyped
parameter). A `TextString` reaching Pascal code is read as bytes, no copy; a
`ByteString` reaching NilPy from a variant is treated as UTF-8 text.

## Gate

Per-fix loop per item. `.npy` tests diffed against CPython with `tools/pydiff.py`
covering every row of the table above, plus: an all-ASCII string (must stay
byte-identical and O(1)), a `find`→slice round-trip across a multi-byte
character, a Pascal `AnsiString` round-tripping through a variant into NilPy, and
`in`/`count`/`split`/`==`/`+` (which must not move). Watch for the O(n²) shape —
`while i < len(s): s[i]` — on a non-ASCII string.

## PARKED in unfinished/ — the foundation is LANDED and green, the semantics are not

Not blocked and not half-applied: the compiler change is complete, gated and
pinned (v248), so nothing here is in a broken intermediate state. What remains
is the semantic conversion, which is scoped below and must be done as one
commit. Re-claim it; do not re-derive the survey.

## 2026-08-07 — the FOUNDATION landed; the semantic conversion did not

Split deliberately. What is in is complete and useful on its own; what is out
would have been half a coordinate system, which is worse than none.

### Landed

- **The meta word is defined** with the low-32 budget the 32-bit shrink needs:
  `BlockKind(8) | Flags(8) | KindData0(8) | KindData1(8)`, bits 32–63 reserved.
  Kinds `LEGACY/BYTESTR/TEXTSTR/DYNARRAY/OBJECT`; flags `STATIC/INTERNED/ASCII/
  EXTENDED`; `KindData0` is the encoding enum (`BYTES/UTF8/UCS2/UCS4`), not a
  codepage.
- `PXX_HDR_KIND` → **`PXX_HDR_META`**, as this ticket required.
- **`PXX_FLAG_ASCII` is computed and stamped** for every string built by
  `PXXStrFromLit` and `PXXStrConcat` — and it is **free**: both already copy
  byte by byte, so it is one `or` per byte in a loop that exists anyway. No
  extra pass, no cached side table.
- `PXXHdrMeta(p)` is exported for consumers. Its absence of a flag means
  **"unknown"**, never "non-ASCII" — a consumer must scan.
- The phase-1 debug magic retired: the meta word now carries real data, so the
  `-dPXX_HEAP_DEBUG` check became "is the kind byte a kind we know". Weaker
  against a wild pointer into live data, but use-after-free is still caught
  ($DD poison = 221 > `PXX_KIND_MAX`).

Verified: `lit → ASCII`, a UTF-8 `é` string → not-ascii, `ascii + ascii →
ASCII`. Self-host fixedpoint in one round via the **fast path** — no layout
changed, so `make compiler/pascal26` is correct here, which is the narrow rule
from `devdocs/dev/fpc-optional-workflow.md` working as documented.

### The obstacle the next session needs to know about

**`pystr_at` returns a `Char`.** A NilPy `s[i]` lowers to it
(`pyparser.inc` ~5180) and the result is typed `tyChar`, promoted to a str via
`pystr_ofchar` where a string is needed. A `Char` is one byte, so it **cannot
carry a multi-byte character**. Character indexing therefore needs a new
string-returning entry point (`pystr_at_s`) *and* the lowering re-typed from
`tyChar` to `tyAnsiString` — which ripples into NilPy's type inference. That is
the structural work, not the UTF-8 arithmetic.

### How CPython solves the "char" problem — and why that removes the objection

Python has **no char type**. `s[i]` returns a `str` of length 1, always.
Measured against CPython 3.12:

| | result |
| --- | --- |
| `type(s[0]).__name__`, `len(s[0])` | `str`, `1` |
| `t[1] is t[1]` for `é` (U+00E9) | **True** — cached |
| `u[0] is u[0]` for `日` (U+65E5) | **False** — freshly allocated |
| `sys.getsizeof("a")` | 42 bytes |

So CPython keeps a cache of the **256 latin-1 single-character strings** and
allocates only above U+00FF. Given a 42-byte str object, that cache is what
makes `for c in s` and `s[i]` affordable at all.

**This is the answer to the `pystr_at` obstacle above.** The objection to
returning a string instead of a `Char` is allocation cost per subscript — and
CPython shows the standard fix: intern the single-character strings. For pxx
that means the ~128 ASCII ones (our substrate is UTF-8, so latin-1 above $7F is
already two bytes and less worth caching), which is exactly the population the
`PXX_FLAG_ASCII` fast path is already about. On that path `s[i]` becomes a
pointer to a shared block — **cheaper than today's `Char` → `pystr_ofchar`
promotion**, which allocates.

Pleasingly, both reserved flags from the phase-2 foundation find their purpose
here: `PXX_FLAG_INTERNED` marks a cached singleton, and `PXX_FLAG_STATIC` is
what stops its refcount ever reaching zero. Neither was invented for this; they
were reserved on general principle and the use arrived.

So the shape of the fix is: `pystr_at_s(s, i): AnsiString` returning an interned
singleton for an ASCII character and a fresh 1-character string otherwise, with
the lowering re-typed from `tyChar` to `tyAnsiString`. The type ripple is real
work; the performance worry is not.

### Why it must be all-or-nothing

Converting `len()` alone makes things **worse**: `while i < len(s): s[i]` would
then mix a character count with a byte index, breaking code that works today.
The byte model is at least internally consistent (measured: `s[s.find("w"):]` is
correct across multi-byte characters, because UTF-8 is self-synchronising). So
one commit must move the whole public coordinate system:

`pystr_len`, `pystr_at`(→ new str form), `pystr_slice`, `pystr_slice_step`,
`pystr_reverse`, `pystr_charlist`, `pystr_find`/`_from`/`_range`,
`pystr_index`*, `pystr_rfind`*, and the padding widths
(`ljust`/`rjust`/`center`/`zfill`).

Not affected, because byte and character answers coincide — and this was
**measured against CPython with non-ASCII input**, not assumed: `in`, `count`,
`split`, `partition`, `join`, `replace`, `==`, `+`, `startswith`/`endswith`
without offsets all already agree on `"héllo wörld"`. That is what bounds the
conversion to the position-exposing functions above; do not re-verify it, and do
not widen the list without a measurement.

### The property that makes it safe when it happens

Gate every converted function on `PXX_FLAG_ASCII`: when set, byte position ==
character position and the function takes **exactly today's code path**. Every
existing test uses ASCII, so the entire suite stays on the unchanged path and
the new behaviour appears only where the old behaviour was wrong. That is the
whole regression argument — build it that way from the start.

### Access route, verified

pylib does **not** `uses builtinheap` today. Adding it was tried and **works**
(a NilPy program built and ran with it). The exploratory edit was reverted to
keep this commit purposeful, but the route is known-good — do not re-litigate
it, and do not duplicate the header offsets into pylib instead.
