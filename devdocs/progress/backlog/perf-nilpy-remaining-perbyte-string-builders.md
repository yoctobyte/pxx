---
track: N
prio: 40
type: perf
---

# NilPy: remaining pylib string builders still append per-byte (O(n²))

The dominant per-byte-concat sites (`pyfile_slurp`, `pystr_upper`,
`pystr_lower`) were fixed (a50491d6) — amortised-doubling / preallocate instead
of `Result := Result + c` every byte. The same O(n²) pattern remains in the
smaller builders, confirmed as PXXStrConcat callers by callgrind:

- `pystr_join` (`Result := Result + sep` / `+ item`) — total length is
  computable up front (sum of item lengths + sep*(n-1)); preallocate.
- `PyReprQuote` (repr with escapes) — grows a quoted string char by char.
- `PyFmtBase` / f-string formatting helpers.
- the strip family (`pystr_strip`/`lstrip`/`rstrip[_chars]`) — result length
  <= input; preallocate to input length and trim, or compute the span and Copy.

Each is O(n²) in the built string's length. None is on uforth's hot path (that
was the file slurp), so impact is smaller — but the pattern is a latent cliff
for any string-heavy NilPy program. Fix by preallocation where the final length
is known, amortised-doubling where it is not (the pyfile_slurp shape).

Root option worth weighing: give managed AnsiString append a spare-capacity
builder so `s := s + c` is amortised O(1) at the RTL, fixing every site at once
— but that touches shared managed-string RTL (self-host gate), so per-site
preallocation is the safer incremental path.

## Partially fixed (this session) — `pystr_join` only

Rewrote `pystr_join` to preallocate the exact final length (sum of item
lengths + `sep` repeated `n-1` times) up front, then write in place —
mirroring `pystr_upper`/`pystr_lower`'s existing preallocate-and-index
pattern. Each item is materialised into a local `items` array ONCE
(`VariantToStr` isn't free to call twice per item) before the length sum,
avoiding a second per-item conversion. Verified against CPython (including
the empty-list and single-item edge cases) and the existing
`TypeError`-on-a-non-str-item path, unchanged. Regression:
`test/test_nilpy_str_join_perf_fix.npy`.

Still open, not attempted this pass: `PyReprQuote`, `PyFmtBase`/f-string
helpers, and the strip family (`pystr_strip`/`lstrip`/`rstrip[_chars]`) —
each its own, smaller preallocation fix in the same shape, left for a
follow-up rather than done all at once under one ticket.
