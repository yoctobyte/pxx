---
track: N
prio: 30
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
