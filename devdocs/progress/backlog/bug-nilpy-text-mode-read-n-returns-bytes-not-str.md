---
track: N
prio: 50
type: bug
summary: "`f.read(3)` on a TEXT-mode file returns bytes (`b'one'`) where CPython returns a str (`one`). TPyFile.read(n)'s return type is statically TPyBytes, so it cannot branch on the mode at run time — the fix needs either a mode-carrying text path or a distinct binary class, not a runtime test"
---

# text-mode `read(n)` returns bytes, not str

- **Type:** bug (NilPy — CPython upward-compat divergence) — **Track N**
- **Opened:** 2026-08-10
- **Found by:** Track A+C+P+N while writing the regression test for
  [[bug-nilpy-open-returns-two-different-classes-by-mode]]. Every other row of
  that test matched CPython byte for byte; this is the one that did not.

## Repro

```python
p = "/tmp/x.txt"
f = open(p, "w"); f.write("one\n"); f.close()
f = open(p, "r"); print(f.read(3)); f.close()
```

```
CPython: one
pxx    : b'one'
```

This is a genuine upward-compat break by Track N's own rule: a program CPython
accepts and runs observes the difference — `print` renders it differently, and
`f.read(3) + "x"` is a str concat in CPython and a type error here.

For contrast, the zero-argument `f.read()` **is** correct — it was added as
`AnsiString` by the one-class fix above. It is only the counted form that
differs, so the two arities of one method disagree about their own type.

## Why it is not a one-line fix

`TPyFile.read(u: Int64): TPyBytes` has a **static** return type. CPython picks
str or bytes from the MODE the file was opened in, which is a run-time value —
so no branch inside `read` can express it. The shapes that could:

1. **Carry the mode on TPyFile and add a separate text accessor**, with the
   frontend lowering `read(n)` to one or the other. It only works when the mode
   is a literal at the call site, which it usually is — `open(p, "rb")` — but
   not always, and the fallback would have to pick one.
2. **A distinct binary class** (`TPyBinFile`) chosen by the mode literal, the
   way the mode used to choose between TPyList and TPyFile. **Reject this** —
   it re-creates exactly the two-classes-for-one-type split that the parent
   ticket was opened to remove, and it would break the same way the moment one
   name held both.
3. **Return a variant** and let the runtime carry the tag. Honest about the
   dynamism and consistent with how NilPy already handles values whose type is
   not known until run time, at the cost of a boxed result on a hot path.

(1) or (3). This is a **Track U-shaped call** if it is not obvious to whoever
picks it up — the trade is static-typing sharpness against CPython fidelity —
so file `decide-` rather than guessing.

## Note

Deliberately left unasserted in
`test/test_nilpy_open_one_class_every_mode.npy`, with a comment pointing here,
rather than pinning the current wrong answer into a test.

## Gate

The repro printing `one`; the parent ticket's test extended with the row that
was left out; `make test-nilpy` green; self-host fixedpoint. Note
`compiler/builtin/pylib.pas` is involved, so a change there needs
`make stabilize-fast && make pin` for the gate's fixedpoint.
