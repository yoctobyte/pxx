---
track: N
prio: 50
type: bug
summary: "`f.read(3)` on a TEXT-mode file returns bytes (`b'one'`) where CPython returns a str (`one`). TPyFile.read(n)'s return type is statically TPyBytes, so it cannot branch on the mode at run time — the fix needs either a mode-carrying text path or a distinct binary class, not a runtime test"
status: done
owner: claude-A
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

## Resolution (2026-08-11) — FOUR accessors were wrong, not one

Swept the family before choosing a shape, and the ticket had seen a quarter of
it. One concept — which of the two string types this file yields — hard-coded in
four places, wrong in BOTH directions:

| | CPython | pxx before |
| --- | --- | --- |
| text `read(n)` | `'one'` | `b'one'` (the ticket) |
| text `readline()` | `'one\n'` | `b'one\n'` |
| binary `read()` | `b'one\ntwo\n'` | `'one\ntwo\n'` |
| binary `readlines()` | `[b'one\n', ...]` | `['one\n', ...]` |

So a per-accessor fix would have left three, and fixing only the reported
direction would have left the binary half.

**Took option (3), and it did not need a Track U ticket.** The trade the ticket
described — static sharpness vs CPython fidelity — is already settled by two
written rules: Track N's own definition of a bug is "code CPython runs must run
here", and correctness outranks optimization. Option (1) only works when the
mode is a LITERAL at the call site, and its fallback would have to guess; option
(2) the ticket already rejects. `TPyFile` now carries `FBinary` (set from the
mode in `pyfile_open`) and every reader branches on it, returning a Variant.
`readall` is the mode-blind slurp both public readers share.

**The variant route exposed a real gap, now fixed:** `pyadd_v` had arms for
list+list and str+str and NONE for bytes+bytes, so a variant-held bytes fell
through to the numeric path and raised `expected a number, got object`. That was
reachable before this change (any bytes arriving as a variant — a list element,
an unannotated parameter) and this made it common, so it is fixed here rather
than filed.

**And one library caller had to move.** `lib/rtl/json.pas`'s `load` chunked
through `f.read(65536)` bound to a `TPyBytes` — which only worked because the
text accessor answered bytes. It now calls the zero-argument `f.read()`, which
is CPython's own spelling. Deliberately NOT the new `readall`: `lib/rtl` is
compiled by the PINNED compiler, so a library calling a method that exists only
in HEAD's pylib turns `make lib-test` red — measured, that is exactly what the
first attempt did. `json.pas` now builds and passes under BOTH compilers.

Gate: `make test-nilpy` EXIT=0, `gate.sh lib` GREEN, `gate.sh quick` GREEN
(self-host byte-identical). New `test/test_nilpy_file_read_follows_the_mode.npy`
covering all eight mode/accessor rows plus the concatenations — on `pinned` it
does not even COMPILE (`readline().strip()` was "TPyBytes has no method strip").
Needs a pin before other lanes see it (`compiler/builtin`).

## Log
- 2026-08-11 — resolved, commit 898f70544.
