---
track: L
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankd-23 (library audit, the tempfile entry, 2026-09-29); routed by frankuser
tags: [nilpy, tempfile, library]
summary: "`tempfile.gettempdir()` returned a fixed /tmp and ignored $TMPDIR. `NamedTemporaryFile()` with CPython's default delete=True raised at the call and stopped the program. gettempdir now follows CPython's order ($TMPDIR, $TEMP, $TMP, /tmp, /var/tmp, /usr/tmp, then the current directory, skipping a directory it cannot create in) and returns an absolute path with no trailing separator, cached after the first call. delete=True removes the file at close() and at the end of a `with` block; NamedTemporaryFile now supports `with`. It is not removed if the object is dropped without close(), because a Pascal object has no finaliser here."
owner: ""
---

# tempfile ignores $TMPDIR and refuses delete=True

```python
tempfile.gettempdir()             # TMPDIR=/x: CPython '/x'; v451 '/tmp'
tempfile.NamedTemporaryFile()     # v451: runtime error, delete=True not supported
```

## Fix (lib/rtl/tempfile.pas)

- `gettempdir`: CPython's candidate list, taking the first directory that
  exists and has write and search access (`PalAccess`, where CPython creates
  a probe file). Made absolute (`os.path.abspath`), with no trailing
  separator, and fixed by the first call, as CPython's `tempfile.tempdir` is.
  `NamedTemporaryFile` without `dir=` now creates in it, rather than in the
  RTL's fixed `/tmp/`.
- `NamedTemporaryFile(delete=True)`: `close()` removes the file; a second
  `close()` does nothing. `__enter__`/`__exit__` make `with` call `close()`.
  The object is still a name rather than an open handle (unit header, point
  1), so the pattern of opening `.name` elsewhere works while it lives.
- Remaining difference, stated in the unit header: CPython also deletes when
  the object is collected. A Pascal object's destructor does not run when
  NilPy releases it, so a delete=True file that is never closed stays.

## Measured (2026-09-29)

- `test/test_nilpy_tempfile_gettempdir_follows_tmpdir.npy`, run under five
  environments: TMPDIR with a trailing slash; TMPDIR missing so TEMP wins;
  TMP only, as `dir/./`; none set; and TMPDIR=/proc (unwritable), so TEMP
  wins. Each run equals CPython's. The previous library is wrong in four,
  and right only when nothing is set.
- `test/test_nilpy_named_temporary_file_deletes_on_close.npy`: default
  delete, close twice, `dir` equal to gettempdir, delete=False with
  suffix/prefix, `with` for both, and writing and reading `.name` inside the
  `with`. It equals CPython on x86-64 and i386. The previous library stops
  at the first call.
