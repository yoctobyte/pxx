---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_bytes_decode.npy red at 74a925112afc (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-01T21:05:27Z
- **Test source:** test/test_nilpy_bytes_decode.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_bytes_decode.npy'` at 74a925112afc049f24fe9ef3ec588f6425ef8d86

## Range
bad `74a925112afc`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:23: error: no overload of bytes matches these arguments
  argument types: (class)
  candidates:
    bytes(class)
    bytes(AnsiString)
  near:       >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Track T triage (face 2) — `bytes(list)` was never implemented; a correct fix exposed it

**Not a regression in the code that broke it.** The failing construct is one line
of the test:

```python
c = bytes([104, 105])
print(c.decode())          # CPython: hi
```

```
pascal26:23: error: no overload of bytes matches these arguments
  argument types: (class)
  candidates:
    bytes(class)
    bytes(AnsiString)
```

`compiler/builtin/pylib.pas` declares exactly two:

```pascal
function bytes(b: TPyBytes): TPyBytes;
function bytes(const s: AnsiString): TPyBytes; overload;
```

**There has never been a `bytes(iterable)` overload** — `git log -S "function
bytes"` shows only the original `bytearray core` and `bytes literals` commits.
CPython's `bytes(iterable_of_ints)` is simply unimplemented.

### Why it passed until now

The test was added by `b78988fe8` and was **GREEN at that sha**. In the window
`b78988fe8..74a925112` sits `b9b1ac4d5` *"find(A): overload resolution ignores
class identity — a silent wrong-dispatch bug"*, which also touched `pylib.pas`.

Before it, a list argument matched `bytes(b: TPyBytes)` because resolution
compared "is a class" rather than *which* class, and the call happened to
produce the right answer through layout compatibility. That is precisely the
silent wrong-dispatch `b9b1ac4d5` was written to close.

So the sequence is: **a correct fix removed an accidental path, and the missing
overload underneath it became visible.** The right response is to implement what
was always missing, not to loosen resolution again.

### Fix

Add a `bytes(list of int)` overload to `pylib.pas` implementing CPython's
`bytes(iterable_of_ints)` — each element must be an int in `0..255`, and a
non-int or out-of-range element is a `TypeError`/`ValueError` respectively.

Track: **N** (the NilPy builtin surface). Track T files, does not fix.

### Diagnostic nit worth fixing while in there

The error message is self-contradictory as printed:

```
  argument types: (class)
  candidates:
    bytes(class)          <- looks like an exact match, and is not
```

Both the argument and the candidate render as bare `class`, so the message says
"no overload matches" while displaying one that appears to. Now that resolution
*does* distinguish class identity, the diagnostic should print the class name on
both sides or it will mislead every future reader the same way.
