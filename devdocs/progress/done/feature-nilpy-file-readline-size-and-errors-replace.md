---
track: N
prio: 20
type: feature
---

# f.readline(size) and open(..., errors="replace")

Vloot's ssh stream reader bounds each line from a peer it does not trust
(`proc.stdout.readline(MAX_LINE)`) and opens /proc files with
`errors="replace"`. Reported by neo-73 2026-10-20 (`readline(n)` failed to
compile with a ShortString endswith error).

- `TPyFile.readline(size)`: at most `size` bytes, stopping after a newline. A
  negative size means no limit and 0 returns ''. The plain form calls
  readline(-1).
- `open(..., errors="replace")` is honoured, not just accepted. The frontend
  wraps the open in `pyfile_errors_replace`, and text reads (read, read(n),
  readline, readlines, iteration) decode invalid UTF-8 to U+FFFD.
- `bytes.decode("utf-8", "replace"/"ignore"/strict)` follows CPython's
  decoder: lead bytes C2..DF, E0..EF, F0..F4 only; the second-byte ranges that
  refuse overlongs and surrogates (E0 A0.., ED ..9F, F0 90.., F4 ..8F); one
  U+FFFD per maximal valid prefix.

Test: test_nilpy_file_readline_size_and_errors_replace (13 decode edge cases
plus the file forms, python3's output).
