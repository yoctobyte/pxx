---
summary: "RESOLVED 2026-11-25: a text file opened with errors=\"replace\" decoded each read(n) / readline(size) piece on its own, so a UTF-8 character cut by the piece boundary became U+FFFD in both pieces: read(1) over 'é' gave two U+FFFD where CPython gives 'é'. A piece that stops inside a valid sequence now reads the rest of it first (PyFileFinishUtf8), so each piece holds whole characters."
type: bug
track: N
prio: 45
status: done
created: 2026-11-25
found-by: a local /code-review of pin v455
owner: claude-dupwt
tags: [nilpy, io, utf-8, cpython-parity]
blocked-by: []
---

## Fix

compiler/builtin/pylib.pas: PyFileFinishUtf8(fd, s) looks back up to three
continuation bytes to find a lead byte (C2-DF, E0-EF, F0-F4). It then reads
single bytes until the sequence is complete or a non-continuation byte arrives.
TPyFile.read(n) calls it, and so does readline(size) when it stopped on the
size limit. It runs only on the replace path. Without errors="replace" the
bytes pass through undecoded, and two halves concatenate back to the character.

## Two differences that remain, both deliberate

- read(n) counts BYTES, not characters, because NilPy strings are byte
  strings. A piece is n bytes rounded up to a whole character.
- When the byte after a cut sequence is not a continuation, it stays in the
  same piece: `"�("` comes back as one piece where CPython gives two. The
  text is the same. Splitting it would need a seek back, which pipes do not
  have.

## Test

test_nilpy_errors_replace_keeps_a_utf8_character_whole_across_reads
(test-nilpy) covers read(1), read(2) and readline(2) over 2-, 3- and 4-byte
characters and two broken sequences. It compares strings, so the expected
output is CPython's. Latest before the fix fails it.
