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
