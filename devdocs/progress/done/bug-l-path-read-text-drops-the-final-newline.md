---
track: L
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankd-23 (library audit, 2026-09-29); routed by frankuser
tags: [nilpy, pathlib, library, text-io]
summary: "`Path(\"f\").read_text()` dropped the file's final newline: 17 chars where CPython reads 18. It rebuilt the text from ReadLn lines joined by #10. It now reads the file's bytes and applies CPython's text-mode newline translation (\\r\\n and a lone \\r read as \\n), so a file with or without a trailing newline, an empty file, and CRLF all read as CPython reads them."
owner: ""
---

# `Path.read_text()` drops the final newline

```python
Path("f").write_text("0123456789abcdef\n")
len(Path("f").read_text())   # CPython 17; v451 16
```

## Cause and fix

lib/rtl/pathlib.pas read the file with `ReadLn` and joined the lines with
`#10`, so the newline after the last line was lost, and so was every newline
of a file that is only blank lines (`"\n\n\n"` read as `"\n\n"`).

It now opens the file with pylib's `pyfile_open`, reads it whole
(`TPyFile.readall`), closes and frees the file object, and applies the
translation CPython's text mode applies on read: `\r\n` and a lone `\r`
become `\n`, and every other byte stays as it is.

`write_text` already wrote the string as given, which matches CPython on
Linux. This unit has no `read_bytes` or `write_bytes`, so there is no bytes
round trip to check.

## Measured (2026-09-29)

- `test/test_nilpy_path_read_text_keeps_the_file_as_written.npy`: files
  with and without a trailing newline, empty, blank lines only, CRLF, a lone
  CR, mixed endings, and a `write_text(read_text())` round trip. It equals
  CPython on x86-64, i386 and riscv32. The previous library fails on all
  three. The rows are those three. wasm32 has no row: its runner has no
  writable directory (Runtime error 2).
- Leak check (`-dPXX_ALLOC_CENSUS`, `tools/assert_no_leak.sh`): 1000 calls
  leave 4 blocks live. Without the `Free` the file object leaked one per call
  (953 live).
- Not changed here: `open(p).read()` in text mode does NOT translate `\r\n`
  (`"a\r\nb\r\n"` reads as 6 chars, CPython 4). That is in LOGBOOK.
