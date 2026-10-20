---
track: N
prio: 10
type: bug
---

# `with open(...)` never closed the file, and neither did dropping it

Reported 2026-10-20 by neo-73. Vloot's collector reads /proc/<pid>/stat and
status for every process each second, about 800 opens per sample. On via
(aarch64) it died with EMFILE at the start of its second sample. Every
`with open(p) as f:` leaked one fd: on return, after the block, in a for-loop,
and on exception. `open(p).read()` and a rebound `f` leaked one too. CPython
leaks none.

**Cause:** the plain `with` path only bound `as`. Its comment still said pyopen
read the file eagerly, so there was nothing to close. That stopped being true
when TPyFile began holding a live fd. pylib's own classes skip the
`__enter__`/`__exit__` path, so TPyFile's close was never called. Separately,
PyObjFinalize had no TPyFile arm, so a file freed by refcount kept its fd.

**Fix:**
- pyparser `PyParseWithTail`: a pylib object with a `close()` is held in a
  hidden temp and closed in a try/finally around the body. That is what
  CPython's `__exit__` does.
- pylib `PyObjFinalize`: a new finaliser kind 5 for TPyFile closes the fd when
  the last reference goes. It never closes 0..2.
- TPyFile gains `closed`, and read/readline/readall/write raise
  `ValueError: I/O operation on closed file.` as CPython does.

**Left:** a file dropped at MODULE level is held by its expression temp until
the program ends. That is one fd per site and doesn't grow with iterations;
inside a def it is 0.

Test: `test_nilpy_with_open_closes_the_file` (fd counts and messages are
python3's).
