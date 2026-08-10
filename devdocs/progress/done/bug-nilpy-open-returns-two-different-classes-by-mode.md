---
prio: 60
track: N
type: bug
blocked-by: []
status: done
owner: claude-ACPN
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

## Log
- 2026-08-10 — resolved, commit 4d3716b05.

## Resolution (2026-08-10) — one class, as the ticket recommended

Took the **one-class repair**, not the fallback. `open()` now answers `TPyFile`
in every mode; the read-slurp conveniences moved onto it.

### What changed

- **`TPyFile` gained the read side** (`compiler/builtin/pylib.pas`):
  `read()` with no argument → `AnsiString` to EOF (chunked, leaving the position
  at EOF as CPython does), and `readlines()` → `TPyList` of lines each KEEPING
  its newline, exactly the shape `pyopen` used to hand back so joining still
  reproduces the file byte for byte. The counted `read(u)` → `TPyBytes` is
  untouched and is now an explicit `overload`.
- **`for line in f:` iterates a file by line** (`PyParseForIn`,
  `compiler/pyparser.inc`): a `TPyFile` iterable is converted via `readlines()`
  and then runs the ordinary list loop — the same shape the dict arm beside it
  already used for `keylist`. Before this it fell into the generic `count`/`at`
  protocol, and the error named `count`, a word the user never wrote.
- **`pyopen` is now `pyfile_open(path, 'r')`** and returns `TPyFile`. It had
  exactly ONE call site (the no-mode `open(path)` form), so retargeting it beat
  inventing a name. Python's default mode *is* `"r"`, so the two spellings are
  genuinely the same thing.
- **The frontend's mode sniff is gone** (`compiler/parser.inc`): the
  `'r'`-and-not-`'rb'` literal test that chose between `pyopen`/TPyList and
  `pyfile_open`/TPyFile is deleted. The mode no longer picks a type.

### Measured against the CPython oracle

The ticket's repro — including **the silent half**, an append through a name
that had widened to the read class — is now byte-identical to CPython:

```
[one]  /  after-append:one|two|  /  iter:one  iter:two  /  nomode lines:2
```

All **10** file-touching `test/*.npy` were run three ways (new binary, `pinned`,
CPython): every one **matches CPython** and every one is **unchanged vs
pinned** — so the unification fixed the broken shapes without moving any
already-working one. `FileNotFoundError` still raises from both `open(p)` and
`open(p, "r")`, checked against CPython rather than assumed.

### Regression test

`test/test_nilpy_open_one_class_every_mode.npy`, wired into `make test-nilpy`.
Every read goes through the **same name** as an earlier write — that reuse is
the entire bug, and a different name always worked. Covers the compile-error
half, the silent append-loss half, iteration, `readlines()`, and the no-mode
form.

### Left deliberately

- `TPyList.read` / `close` / `readlines` and `pyfile_read` remain. They are no
  longer reachable from `open()`, and removing them is a separate cleanup with
  its own risk; noted here so the vestige is not mistaken for a live second path.
- The widening rules in `pyparser.inc` that cite "left f dispatching as a
  TPyFile while it now held a TPyList" stay — they are still needed for genuine
  class rebinds, but **the root they were written for is gone**.
- `f.read(n)` in TEXT mode still returns bytes where CPython returns str. Found
  writing the test, NOT asserted there (a test must not pin a wrong answer), and
  filed as [[bug-nilpy-text-mode-read-n-returns-bytes-not-str]] — it needs a
  design call, and the obvious "binary file class" answer would re-create this
  very ticket.

### Gate

`tools/gate.sh quick` GREEN; `make test-nilpy` **exit 0** (run twice — once
before and once after the new test was registered); self-host fixedpoint
byte-identical. `compiler/builtin/pylib.pas` changed, so
`make stabilize-fast && make pin` ran: **pinned v254**
(`fee55aacb5a76c9a2c4f496a8c0dcf80621d8a1d3cd5b871b31281e6f9fef9f6`).
