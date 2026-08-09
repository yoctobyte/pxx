---
prio: 70
status: done
owner: agent-AN
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_delitem_dunder.npy red at 954727cee668 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-09T10:56:31Z
- **Test source:** test/test_nilpy_delitem_dunder.npy test/test_nilpy_delitem_dunder.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_delitem_dunder.npy'` at 954727cee6680daf514fcd5bb929814a1ca3c522

## Range
bad `954727cee668`, last good `29d980110b58`, 15 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:67: error: Nil Python: del is supported on a dict subscript, a list index, a list slice, or a class with __delitem__ (del d[k], del l[i], del l[a:b], del c[k])
(tail)
pascal26:67: error: Nil Python: del is supported on a dict subscript, a list index, a list slice, or a class with __delitem__ (del d[k], del l[i], del l[a:b], del c[k])
  near:  del o    >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## FIXED 2026-08-09, Track A+N — a refusal claimed a `del` TARGET

### Triage

Not a NilPy `del` bug and not caused by the pylib work in flight beside it.
Verified with the control that removes the variable rather than by reading:
HEAD and `pinned` BOTH fail, at different lines (HEAD 67, pinned 61 — pinned
predates the whole `__delitem__` feature), so it is pre-existing.

`del o[7]` on `class OnlyDel` — a class declaring **only** `__delitem__`.

### Cause

The `del` lowering deliberately does not re-implement the postfix grammar: it
parses `c[k]` as an ordinary expression and REWRITES the node it gets back. So
it depends on WHICH node the subscript arms build, and it handles two shapes —
an `AN_CALL` to `__getitem__` when the class has one, and a plain `AN_INDEX`
when it does not.

The not-subscriptable refusal added for
[[bug-nilpy-subscript-read-without-getitem-yields-garbage]] replaced that second
shape. A getter-less class now yields a run-time TypeError call node instead of
an `AN_INDEX`, so the rewrite found nothing to rewrite and the statement failed
to compile. The refusal is right for a READ; a `del` target is not a read.

That is the same trap as the `__setitem__` arm fixed earlier today
(bug-nilpy-setitem-without-getitem-write-does-not-compile): **the subscript
protocol has three members and the gate keeps being written in terms of one of
them.** `__getitem__` present, `__setitem__` present, `__delitem__` present are
three independent facts, and each non-read use has to say so.

### Fix

`PyInDelTarget`, set around the single `PyParseBoolExpr` in the del parser and
restored after. The refusal arm skips itself while it is set, so the plain
`AN_INDEX` survives for the rewrite. Scoped rather than global state that
lingers, and it is one flag rather than teaching the del lowering a third node
shape — the rewrite's whole point is not to know about grammar.

### Gate

`test/test_nilpy_delitem_dunder.npy` GREEN. Extended it so **both halves of the
flag are pinned**: `del o[7]` must work AND `v = o[7]` on that same class must
still raise TypeError. With only the first, inverting the flag would pass.
Matches CPython. Self-host fixedpoint byte-identical.
- 2026-08-09 — resolved, commit PENDING-COMMIT.
