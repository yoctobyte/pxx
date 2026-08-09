---
track: N
prio: 40
type: bug
status: done
owner: agent-AN
---

# `obj[k] = v` does not compile when the class has `__setitem__` but no `__getitem__`

```python
class S:
    def __setitem__(self, k, v):
        self.last = k

s = S()
s["k"] = 1        # error: expected expression
```

CPython runs this: `__setitem__` alone is enough to make a class assignable-into,
and plenty of write-only sinks (recorders, config writers, proxies) declare
exactly that. A compile error, so nothing computes a wrong answer.

Confirmed pre-existing (`stable_linux_amd64/default/pinned` fails identically).

## Same root as the READ half, which is now fixed

`parser.inc`'s subscript arm is gated on `FindUMeth(mci, '__getitem__') >= 0`,
and the `__setitem__` WRITE is handled *inside* that arm. So a class with only
`__setitem__` never reaches its own write path — the gate asks about the getter.

The READ half of this (`bug-nilpy-subscript-read-without-getitem-yields-garbage`)
was fixed 2026-08-09 by giving a getter-less class a run-time TypeError. That
fix deliberately takes over **only a READ**, using the same closing-bracket peek,
and leaves the assignment case exactly as it was — which is why this ticket
exists rather than being silently swept in.

## Fix shape

The arm's condition should be "declares `__getitem__` **or** `__setitem__`", with
the read and write halves inside it each checking for the member they actually
need — the read raising the not-subscriptable TypeError when `__getitem__` is
absent (already implemented), the write raising the same shape when
`__setitem__` is absent. That collapses the gate and the two members into one
place instead of the getter standing in for both.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over a class with
only `__setitem__` (write then observe the effect), only `__getitem__` (read;
write must raise TypeError), both, and neither — the 2x2, since the current gate
conflates two of those cells.

## FIXED 2026-08-09 — the gate was an else-if CHAIN, which is why the comment lied

The refusal arm's own comment said `obj[k] = v` on a `__setitem__`-only class
"already worked through the write path below". It did not, and the reason is
structural rather than logical: **"below" is the next arm of an `else if`
chain**, so matching the refusal arm SKIPPED it. The fall-through the comment
describes cannot happen in that shape, and the write landed on the generic
`AN_INDEX` fallback and reported "expected expression".

Collapsed as the ticket asked — one gate naming both members, each half checking
the member it actually needs:

- refusal arm: now requires **neither** `__getitem__` **nor** `__setitem__`;
- dunder arm: now entered on **either**;
- inside it, a READ with no `__getitem__` raises the same run-time
  `TypeError: '<C>' object is not subscriptable` the refusal arm raises, and a
  WRITE with no `__setitem__` already raised `PyNoSetitemError`.

Also closed the fourth cell while the gate was open: `obj[k] = v` on a class with
**neither** member used to fall through to the generic `AN_INDEX` — pointer
arithmetic on the instance handle, a silent wrong value. It now raises the same
run-time error, with the key AND the value still evaluated first, matching
Python's left-to-right order.

### Gate — the 2x2, all four cells, against CPython

Added to `test_nilpy_not_subscriptable.npy` (the sibling read ticket's own test)
rather than a new file, and its "NOT asserted: the write half … filed
separately" note was replaced by the assertions — leaving that note in place
would have been a stale claim in a live test.

| class declares | read | write |
| --- | --- | --- |
| `__setitem__` only | TypeError, names the class | **works** (was: "expected expression") |
| `__getitem__` only | works | TypeError |
| both | works | works |
| neither | TypeError, names the class | TypeError (**was: silent pointer arithmetic**) |

Matches CPython byte for byte, except that the two WRITE refusals assert the
LABEL only: `PyNoSetitemError` does not name the class where CPython does. That
asymmetry — the read half names it, the write half does not — is filed as
[[bug-nilpy-nosetitem-error-does-not-name-the-class]]; fixing it edits pylib and
so wants batching with the other queued re-pin work rather than a re-pin for a
message.

Self-host fixedpoint byte-identical; `tools/gate.sh quick` GREEN.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
