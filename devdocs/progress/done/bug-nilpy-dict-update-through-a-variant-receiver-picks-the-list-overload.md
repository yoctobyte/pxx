---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`xs[0].update(...)` on a DICT element SEGFAULTS (pinned too): a variant receiver resolves an overloaded method by ARITY alone, so `update` always picks the first arity-1 arm — `update(l: TPyList)` — and a TPyDict is then walked as a list. The statically-typed receiver is fine, because the class path does real overload resolution and the `update(const v: Variant)` arm added by bug-nilpy-dict-update-with-a-variant-argument-segfaults wins there."
status: done
owner: claude-A-N
---

# `dict.update()` through a VARIANT receiver picks the TPyList overload and segfaults

- **Type:** bug (NilPy, **crash**) — **Track N**
- **Found:** 2026-08-13, writing the dict CONTROLS for
  [[bug-nilpy-set-update-method-is-not-mapped]]. Independent of that fix —
  identical on `stable_linux_amd64/default/pinned`.

## Repro

```python
dv = {"a": 1}
dvs = [dv]
dvs[0].update({"c": 3})     # SIGSEGV
print(len(dv))
```

Measured, all four on the same binary:

| shape | result |
| --- | --- |
| `dvs[0].update({"c": 3})` (subscript receiver, literal arg) | **SEGFAULT** |
| `dvs[0].update(o)` (subscript receiver, dict variable) | **SEGFAULT** |
| `dv.update({"c": 3})` (bare name) | correct |
| `mk().update({"c": 3})` where `mk()` returns a dict | correct |

So it is the RECEIVER's shape that decides, not the argument — which is what
tells this apart from [[bug-nilpy-dict-update-with-a-variant-argument-segfaults]]
(the argument-side twin, fixed 2026-08-09 by adding
`TPyDict.update(const v: Variant)`).

## Cause, as far as it was measured

A subscript of a list yields a VARIANT, so the call goes to
`PyParseVariantMethod` rather than to the class-typed path. That routine picks
the method with `FindUMethArity(hitCi, mname, i)` — **arity only**. `update` has
three arity-1 overloads (`TPyList`, `TPyDict`, `Variant`) and the TPyList one is
declared first, so a `TPyDict` receiver's argument is bound to a `TPyList`
parameter and walked as a list.

The Variant arm added by the 2026-08-09 fix is exactly the right target here —
it dispatches on the runtime tag — so the fix is likely "on the variant path,
prefer the `const v: Variant` overload when the argument is not statically
typed" rather than any new runtime code. Note `PyPickOverloadByArgTypes` (v255)
already exists for method overloads picked by argument type; check whether this
site simply does not consult it.

## Grep the siblings before closing

Arity alone decides every overloaded pylib method reached through a variant
receiver, so `update` is unlikely to be the only one. `TPyList.pop`,
`TPyList.count` and `TPyDict.get` are the obvious ones to sweep — a wrong
overload that happens not to crash is worse than this one.

## Gate

`make test-nilpy` + self-host fixedpoint; a `.npy` diffed against CPython
covering a dict and a list through a subscript receiver, with the bare-name
spellings as controls.

## DONE 2026-08-13 — the cause was the SCORER, not the arity re-resolve

Filed the same day it was found, while writing the dict controls for
[[bug-nilpy-set-update-method-is-not-mapped]]; taken straight away because the
diagnosis was still in hand. The filed diagnosis named the arity re-resolve and
pointed at `PyPickOverloadByArgTypes` as the likely answer. Half right, and the
half that was wrong is the part worth recording:

**`PyPickOverloadByArgTypes` was already reachable and already useless here.**
Wiring it into the variant path changed nothing — measured, twice, before
looking further. Its scorer, `PyOverloadArgTypeScore`, compares type KINDS, and
`update(TPyList)` and `update(TPyDict)` are both `tyClass`: every candidate
scored identically, the incumbent won every tie, and the incumbent is whichever
overload was declared first. That is also why the statically-typed path — which
has always consulted the scorer — needed the `update(const v: Variant)` arm
added by [[bug-nilpy-dict-update-with-a-variant-argument-segfaults]] to get its
own answer right: the scorer could never have told those two apart either.

So the fix is one line of ranking: an argument whose rec id EXACTLY matches the
parameter's scores strictly above a kind-only match, and a kind-only match still
scores, so a call moves only where a better-typed sibling exists.

Three sites, because a variant-receiver call resolves in three places and each
had the same hole:

- the STATIC arm's arity re-resolve, now followed by the type pick;
- the RUNTIME dual-dispatch arm — the one a dict actually reached. Dispatch
  found the TPyDict candidate correctly and then called its wrong overload,
  which is why this read as a dispatch bug and is not one;
- `PyOverloadArgTypeScore` itself, shared by both and by the class-typed path.

### Measured

| shape | before | after |
| --- | --- | --- |
| `xs[0].update({"c": 3})` (dict element, mapping) | SEGFAULT | correct |
| `xs[0].update(src)` (dict element, dict variable) | SEGFAULT | correct |
| `d = xs[0]; d.update(...)` (variant local) | SEGFAULT | correct |
| `xs[0].update([["c", 3]])` (iterable of pairs) | correct | correct |
| `m.update(sec)` through a parameter | correct | correct |
| `xs[0].update({8})` on a SET element | correct | correct |

### Siblings, swept

The ticket says arity alone decides every overloaded pylib method on this path,
so `update` is unlikely to be alone. `TPyList.pop`, `TPyList.count` and
`TPyDict.get` are all overloaded and all reached through a variant receiver in
the test — they are distinguished by ARITY, not by class, so the arity resolve
already answered them and they are unmoved. `update` is the case where two
overloads share an arity AND a type kind, which is what made it the crashing
one.

### Verified

`test/test_nilpy_overload_by_class_through_a_variant.{npy,expected}`
(`.expected` from CPython), wired into `test-nilpy`: the receiver shapes above,
each argument kind (mapping / pairs / variant, so a fix that funnelled them
into one arm would fail), mutation-through-the-element, the statically typed
controls, a set and a list element, and the arity-distinguished overloads that
must not move.

Gate: `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN. Track
T sweeps the matrix against the pushed sha — a hand-run suite is NOT part of
this repo's dev loop, however shared the code being touched
(user, 2026-08-13: "we never want to waste time again on full regression
tests").

## Log
- 2026-08-13 — resolved, commit 12f9b3b6c.
