---
track: A
prio: 58
type: bug
blocked-by: []
summary: "After a057789bc, `f(**d)` works but every MIXED form still fails: `f(3, **d)` (expected expression), `f(**d, b=7)` and `f(**d, **e)` (unexpected token). `f(3, **d)` never reaches the star-forwarding branch at all — that branch is guarded on tkStar at the START of the argument list — so this is the ordinary argument loop's gap, not an extension of the previous fix."
---

# `**` anywhere but first in an argument list

- **Type:** bug (parser) — **Track A** (`compiler/parser.inc`, shared A/P).
- **Filed by:** frank2 on Track N, 2026-08-17, verifying the handoff
  [[bug-a-nilpy-leading-double-star-in-a-call-is-not-detected]] (fixed,
  `a057789bc`). Track N may not edit `parser.inc`; filed and handed off.

## Measured at HEAD (a057789bc, self-host converged)

```python
def f(a=1, b=2): return a + b * 10
d = {"a": 5}
e = {"b": 7}
```

| shape | pxx | CPython |
| --- | --- | --- |
| `f(**d)` | **65** ✅ | 65 |
| `f(3, **d)` | `error: expected expression` | 63 |
| `f(**d, b=7)` | `error: unexpected token` | 75 |
| `f(**d, **e)` | `error: unexpected token` | 75 |

Not regressions — none of these worked before either. They are what the
scoped-to-five-lines fix deliberately did not reach.

## Why this is not "finish the previous fix"

`f(3, **d)` **never enters the star-forwarding branch.** That branch
(`parser.inc:15874`) is guarded on `CurTok.Kind = tkStar` at the **start** of
the argument list; with a leading `3` the parser takes the ordinary argument
loop, which has no `**` element handling at all. So the work is in that loop —
recognising a `**` element mid-list and routing the call to the forwarding
lowering — not in extending the branch's look-ahead.

`f(**d, b=7)` and `f(**d, **e)` do enter the branch, but its trailing handling
accepts exactly one `*`/`**` follower and nothing else.

Worth stating because the originating ticket
[[bug-nilpy-a-dict-cannot-be-unpacked-into-a-call]] predicted the opposite —
*"Mixed `f(x, **d)` and `f(**d, y=1)` fall out of the same lowering"*. Measured,
they do not.

## Shape of the fix (a suggestion, not a design)

The runtime is still not the problem: `PyStarForwardCall` binds a dict onto
named slots correctly, and explicit arguments winning their slots is a
compile-time matter. The likely shape is to collect the argument list
generically — positional items, `*` items, `**` items, keyword items — and hand
the whole thing to the existing forwarding lowering when any star element is
present, rather than having two separate paths that each know about only some
element kinds. That is the `normalise-dont-special-case.md` move; bolting a
`**` case onto the ordinary loop while the branch keeps its own parser is how
this stays broken in a fourth shape.

Sizing honestly: this is bigger than five lines and touches the main argument
loop, so it wants its own gate run rather than riding along with something else.

## Gate

`make compiler/pascal26` + a `.npy` diffed against CPython covering the four
rows above plus `f(x, y, **d)`, `C(**d)` on an ordinary `__init__`, and the
existing `f(**d)` / `f(*lst)` / `dict(**d)` staying green, then
`tools/gate.sh quick`.

**Do not skip the FPC seed canary.** `a057789bc` added a cross-include call and
PXX tolerated a duplicate forward that FPC — single-pass — rejects; the canary
was the only thing that caught it. Any change here that calls a `pyparser.inc`
helper from `parser.inc` has the same exposure.
