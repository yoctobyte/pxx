---
track: N
prio: 45
type: bug
---

# NilPy: a USER class method `-> bytes` result loses its TPyBytes identity

## Repro (pre-existing at 6a5f0fb6, unaffected by the member-hoist fix)

```python
class F:
    def readline(self) -> bytes:
        return b"abc\n"
f = F()
raw: bytes = f.readline()   # annotated escape hatch — still broken
print(raw)                  # prints a POINTER, not b'abc\n'
print(raw[:3])              # pointer / garbage
```

CPython prints `b'abc\n'` / `b'abc'`. The PYLIB TPyFile.readline path works
(uforth READ-LINE passes) — only user-class methods annotated `-> bytes` are
affected: the return marshals as a bare pointer whose class identity is not
carried, so print/slice dispatch never sees TPyBytes.

Also seen: `raw = entry["file"].readline()` through a dict-variant receiver
prints the pointer for `print(raw)` even on the pylib path — the dual-dispatch
result boxing may share the root cause.

## Where to look
Method return registration maps `-> bytes` via PyAnnTypeAt ('bytes' →
FindUClass('TPyBytes')); check whether PyMethodRetType propagates that class
(mRetRec) for user classes, and whether the call-site result node gets
ProcRetRecId tagged (compare the pylib readline path, pyparser.inc ~3312).

## Gate
Repro matches CPython; test-nilpy green + self-host byte-identical.
