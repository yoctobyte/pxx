---
track: L
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankd-23 (2026-09-29, via frankuser)
tags: [nilpy, stdlib, tempfile]
summary: "tempfile.NamedTemporaryFile was a name with no file behind it: no write(), read() or seek(), the common use. It is now an open file in the requested mode (w+b by default, as CPython), with write, writelines, read, read(n), readline, readlines, seek, tell, flush and close. The parameter order is CPython's, so a positional `NamedTemporaryFile(\"w\")` is the mode; it used to bind to suffix. An unclosed delete=True file still survives the program's exit (LOGBOOK)."
owner: ""
---

# NamedTemporaryFile has no write()

```python
f = tempfile.NamedTemporaryFile("w+")
f.write("x")        # v451: TPyFile-less object, no method write
```

## Fix (lib/rtl/tempfile.pas)

- The constructor still creates the file empty. It then opens it with
  `pyfile_open(name, mode)`, the file object `open()` yields, so a read
  answers str or bytes by mode as `open()` does.
- The methods forward to that object. close() closes it, frees it (NilPy
  does not run this object's destructor) and then applies delete=True
  once.
- The constructor is `(mode='w+b', buffering=-1, encoding='', newline='',
  suffix, prefix, dir, delete)`, in CPython's order. buffering, encoding
  and newline are accepted and ignored. Every existing caller in test/,
  examples/ and docs/ passes keywords.

## Not done

- The at-exit removal of an unclosed delete=True file. pylib has no atexit
  hook; see the LOGBOOK entry of 2026-09-29.
- A binary-mode write of a str is accepted, where CPython raises TypeError.
- wasm32: no tempfile fixture runs there (Runtime error 2 at the first
  file creation, a WASI filesystem-access question).

## Rows

test/test_nilpy_named_temporary_file_writes_and_reads.npy, with .expected
from CPython. It covers binary and text modes, a positional mode, flush
seen through a second open(), seek with whence, `with` and delete=False.
Rows: x64 (tfrw26), i386 and riscv32, all red before the fix. The existing
tempfile rows (deletes_on_close, gettempdir, mkdtemp, html_tempfile) all
pass. Census: 2000 create/write/read/close cycles leave 15 live.
