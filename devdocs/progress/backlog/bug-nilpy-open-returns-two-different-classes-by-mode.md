---
prio: 60
track: N
type: bug
blocked-by: []
---

# `open()` returns two different classes by mode, so reusing the name breaks

- **Type:** bug (NilPy; valid CPython refused at compile time) — **Track N**
- **Found:** 2026-08-09, realistic-program sweep (a log-rotating writer/reader).

```python
f = open(p, "w"); f.write("one\n"); f.close()
f = open(p, "r"); print(f.read())     # pxx: error: read() takes exactly 1 argument(s), got 0
```

A different name for the reader works. The whole file-API matrix, measured at
`8070feee2`:

| shape | pxx |
| --- | --- |
| write and read through DIFFERENT names | ok |
| write and read through the SAME name | **compile error** |
| append, then read (different names) | ok |
| read inside a def / write inside a def | ok |
| `readlines()`, iteration, `with`, default mode | ok |

## The SILENT half — the same root, and worse (measured 2026-08-09)

The compile error above is the polite symptom. When the reused name's other
binding is an APPEND rather than a read, nothing is reported and the write is
simply **lost**:

```python
f = open(p, "a")
f.write("two\n")
f.close()
print(rd(p))        # CPython 'one\ntwo\n';  pxx 'one\n' — no error, no diagnostic

f = open(p, "r")    # the other binding of `f`, further down
for ln in f: ...
```

The name widened to the read class, so `.write` resolved to `TPyList.write`,
which silently does nothing to the file. A log that stops recording, with a
zero exit status. That is what raises this from "annoying refusal" to a
data-loss bug, and it is why the repair should be the one-class one below
rather than anything that makes the two classes coexist more smoothly.

## Cause

`open(path, "r")` and bare `open(path)` lower to `pyopen` → **TPyList** (the
file is read eagerly into a list of lines), while every other mode lowers to
`pyfile_open` → **TPyFile**. Two Pascal classes for one Python type.

Bind one name to both and the module type widens to a variant; the `.read()`
call site then resolves against `TPyFile.read(u: Int64)` — the arity check fires
and refuses the perfectly ordinary zero-argument `read()`. The diagnostic points
at the user's correct code and names an arity Python does not have.

## Root, and why this is not a one-line fix

Two mechanisms for one concept, which is the smell
`devdocs/dev/normalise-dont-special-case.md` is about. Reading is a `TPyList` of
lines specifically so that `for line in f:` and `f.readlines()` are cheap; a
TPyFile has real fd semantics (seek/tell/truncate). The honest repair is to make
`open()` answer ONE class in every mode — almost certainly `TPyFile`, with the
line-iteration conveniences moved onto it — and that is a Track N change big
enough to want its own session rather than a patch here.

The cheap alternative (make the widened receiver dispatch `read` at runtime
across candidate classes, which `PyParseVariantMethod` can already do) would
hide the wart rather than remove it, and would leave the two classes free to
diverge further. Recorded as the fallback, not the recommendation.

## Repro kept

`/tmp` scratch is not durable — the ten-case matrix is reproduced by the block
at the top plus a rename of the second `f`.
