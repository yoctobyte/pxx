---
track: N
prio: 50
type: bug
summary: "`open(p).read().strip()` fails with a bare 'unexpected token'. ONE method off open()'s result parses fine and so does a two-deep chain off any ordinary value — it is specifically the SECOND link of a chain rooted at the open() intrinsic that the parser drops"
status: done
owner: claude-A
---

# a two-deep method chain on `open()`'s result does not parse

- **Type:** bug (NilPy — parsing; valid CPython refused) — **Track N**
- **Opened:** 2026-08-10
- **Found by:** Track A+C+P+N, writing a repro for
  [[bug-nilpy-file-write-picks-the-bytes-overload-for-a-non-str-argument]] —
  `print(open(p).read().strip())` is the natural way to write it.

## Repro

```python
print(open("/tmp/x.txt").read().strip())
```

```
pascal26: error: unexpected token
```

## The boundary — measured, one variable at a time

| shape | result |
| --- | --- |
| `f = open(p)` then `f.read().strip()` | ok |
| `open(p).read()` | ok |
| `open(p).read().strip()` | **error: unexpected token** |
| `s.strip().upper()` on an ordinary str | ok |

So it is neither "chaining off `open()`" (one link works) nor "two-deep
chaining" (fine on any ordinary value). It is specifically the **second** link
of a chain **rooted at the `open()` intrinsic**.

## Lead (unverified — measure before writing this into a fix)

`open` is a frontend intrinsic in `compiler/parser.inc` (the `isNilPy and (name
= 'open')` arm). Every path through it ends with

```pascal
CurASTNode := atRecv;
LastExprTk := tyClass;
Exit;
```

— it returns from the primary-expression parser directly rather than falling
through to whatever normally continues a postfix/selector chain. One trailing
`.read()` still binds (some outer loop picks it up), and the next `.` is what
finds no handler. **Confirm this by reading the postfix loop before changing
it**; the `Exit` is the obvious suspect and obvious suspects in this file have
been wrong before.

If that is the cause, the same shape is worth checking on **every** NilPy
frontend intrinsic that ends in a bare `Exit` — `input`, `int`, `str`, and the
rest — since they were written to the same pattern. A one-site fix here would
leave the siblings broken, which is the recurring shape in this frontend
(see `normalise-dont-special-case`).

## Diagnostic quality

"unexpected token" names nothing — not the construct, not `open`, not the
member. Whatever the fix, the error should say what it could not continue.

## Gate

The repro printing the file's stripped contents; the sibling intrinsics checked
for the same shape and covered if they share it; `make test-nilpy` green +
self-host fixedpoint.

## Resolution (2026-08-11) — already fixed on master; verified and pinned down by a test

Measured before touching anything: the repro WORKS at HEAD and matches CPython.
The fix was not the intrinsic's `Exit` the lead suspected — it was
**3757dddd0** ("a Python suffix chain composes in any order"), which landed
earlier the same day and is an ancestor of this session's first commit. That
commit made the suffix cluster re-run until a pass consumes nothing, so a
suffix is no longer reachable only in the order the loops happen to appear;
`.read()` then `.strip()` needed them backwards, which is exactly what the
ticket's boundary table described.

`pinned` predates it, which is why the bug still reproduces there — and that
makes a good control: the same file fails on `pinned` at exactly the second
link and passes at HEAD.

The ticket's real remaining ask was the sibling check, and the siblings are fine
**because the fix was made at the cluster rather than per-intrinsic**:
`str(12).zfill(4).upper()`, `str(3.5).split(".")[1].strip()`,
`open(p).readlines()[0].strip()` (a chain through a subscript) and a four-link
`open(p).read().strip().replace(...).lower()` all match CPython.

Closed with `test/test_nilpy_intrinsic_result_chain.npy` so it cannot come back
silently — the ticket was filed against a shape nothing covered.

One genuine gap surfaced while checking siblings: `int("42").bit_length()` is
refused because the METHOD does not exist (the chain parses; the diagnostic
names it). Filed as `bug-n-int-bit-length-is-not-implemented`.

## Log
- 2026-08-11 — resolved, commit 5a7d29e21.
