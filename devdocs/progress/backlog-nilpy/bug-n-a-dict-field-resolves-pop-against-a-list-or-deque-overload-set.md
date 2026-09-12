---
slug: bug-n-a-dict-field-resolves-pop-against-a-list-or-deque-overload-set
track: N
prio: 80
type: bug
blocked-by: []
status: backlog
found: 2026-09-12
found-by: frankuser
owner: unassigned
summary: "lekkerzeilen/app.py:1678 `tile.grids.pop(name, None)` is refused with `pop() takes exactly 0 argument(s), got 2`. `grids` is a dict (`self.grids = {}`, three classes in world.py) and TPyDict DOES declare `pop(k)` and `pop(k, d)` -- so the receiver was resolved against a list's or a deque's overload set instead: `takes exactly 0` can only come from TPyList.pop's zero-arg overload or TPyDeque.pop, the only two 0-argument pops in pylib. THIS IS THE CURRENT WALL ON THE lekkerzeilen CLOSURE (goal 4), newly visible after the star-follower fix moved the wall 438 lines further into app.py. FOUR REDUCTIONS FAILED to reproduce it -- see the list below, do not repeat them. The cheap next step is an INSTRUMENT, not another reduction: the arity error does not name the receiver's class, which is exactly why all four missed."
---

# `tile.grids.pop(name, None)` resolves against the wrong container's `pop`

## What is measured

```
pascal26:1678: error: Nil Python: pop() takes exactly 0 argument(s), got 2
  in: lekkerzeilen/app.py
  near: pop ( name , None ) >>>   self
```

The emitter is `compiler/pyparser.inc:17648`, in `PyParseClassMethodCall` — the
STATICALLY-bound receiver path. So the receiver's class was decided, and decided
wrong: `grids` is assigned `{}` at `world.py:182`, `:782` and `:868`, and
`TPyDict` declares both `pop(const k: Variant)` and
`pop(const k: Variant; const d: Variant)` (`compiler/builtin/pylib.pas:367-368`).

`takes exactly 0 argument(s)` narrows the culprit to two candidates, because they
are the only zero-argument `pop`s in pylib:

| class | declaration | line |
| --- | --- | --- |
| `TPyList` | `function pop: Variant; overload;` | 268 |
| `TPyDeque` | `function pop: Variant;` | 949 |

`TPyList` is the likelier of the two — `TPyDeque` would need an `import
collections` path — but that is a guess and is not measured.

## FOUR REDUCTIONS THAT DO NOT REPRODUCE IT — do not repeat these

Each compiles and runs, matching CPython (`1` then `None`):

1. `d = {"a": 1}; d.pop("a", None)` — the plain static dict.
2. A field `g` declared in TWO unrelated classes, receiver from a
   `pick(flag)`-style ternary, so the member read is dynamic.
3. The app's own shape: receiver obtained by TUPLE UNPACK out of a Variant field
   (`key, tile, prepared, steps = self._pending`).
4. An EMPTY dict literal field (`self.grids = {}`) populated afterwards — the
   empty-aggregate case, which is the one the other three had accidentally
   avoided by writing `{"a": 1}`.

So it is none of: static dict pop, a multi-class dynamic member, a tuple-unpacked
receiver, or an empty dict literal. Something in the app narrows the type
differently, and whatever it is, it is not in the four shapes above.

## THE NEXT STEP IS AN INSTRUMENT, NOT A FIFTH REDUCTION

**The error does not name the receiver's class.** That is why four reductions
missed: the message is consistent with a dozen different wrong answers and
distinguishes none of them. Two cheap moves, in this order:

1. Make the arity error at `pyparser.inc:17648` (and its sibling at `:18872`)
   print the receiver's CLASS alongside the method name. One expression,
   diagnostics-only, and it turns this ticket into a one-line answer. This is the
   same move that cracked the p80 widening wall on 2026-09-11 — that one was
   unreachable until `TypeKindName` made `11` read as `tyInt32`.
2. Then `PXXDBG=a.ast:<proc>` on the enclosing `app.py` method to see what
   `tile.grids` was bound to.

## Provenance — why this is not a regression from the star fix

It is pre-existing and was merely invisible, for two independent reasons:

- `Error()` ends in `Halt(1)` (`compiler/lexer.inc:81`), so the previous wall at
  `app.py:1240` meant nothing after line 1240 was ever parsed. Line 1678 was
  structurally unreachable.
- Every edit in the star-follower fix sits inside an `if CurTok.Kind = tkStar`
  branch, and `pop(name, None)` has no star, so none of them can execute for this
  call.

This is the first-failure blindness `CLAUDE.md` describes: one wall hides every
wall behind it, so clearing one reveals rather than causes the next.
