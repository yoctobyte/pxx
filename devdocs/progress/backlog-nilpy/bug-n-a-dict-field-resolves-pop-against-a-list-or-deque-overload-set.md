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
summary: "ANSWERED 2026-09-12 BY THE INSTRUMENT, NOT BY A REDUCTION: the receiver is typed **TPyDeque**. lekkerzeilen/app.py:1678 `tile.grids.pop(name, None)` -- where `grids` is a dict (`self.grids = {}`, three classes in world.py) -- now reports `TPyDeque.pop() takes exactly 0 argument(s), got 2`, because the arity errors were taught to name the receiver class. The whole program contains ONE deque, `collections.deque()` at chart.py:230, bound to an unrelated local, so the pick has no connection to the value. MECHANISM, and it is already documented in test/test_nilpy_variant_method_pick_by_arity.npy: the dynamic-receiver candidate scan \"keeps one entry per class declaring the name and takes the FIRST FOUND\". So this is a FIRST-WINS SCAN and CLAUDE.md's own rule applies -- it is exposed only by the arrangement that puts the correct entry LAST. SIX REDUCTIONS FAILED and that is now EXPLAINED rather than mysterious: candidate order depends on the whole program's class registration, so a small program puts TPyDict first and compiles, and no small reduction can put TPyDeque there. THE NEXT STEP IS THE SCAN ORDER, NOT A SEVENTH REDUCTION: find what registers TPyDeque ahead of TPyDict for `pop`, and prefer a candidate whose ARITY accepts the call -- which is exactly the fix that fixture records for the zero-argument case, applied to a two-argument one. THIS IS THE CURRENT WALL ON THE lekkerzeilen CLOSURE (goal 4)."
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

## 2026-09-12, later: the instrument answered it in one run

The ticket said to build the instrument rather than write a fifth reduction. Done
— both arity errors now print `Class.method()` via `PyMethDiagName` — and the very
first run named the culprit:

```
pascal26:1678: error: Nil Python: TPyDeque.pop() takes exactly 0 argument(s), got 2
```

**`TPyDeque`.** The program contains exactly one deque —
`collections.deque()` at `chart.py:230`, assigned to a local called `queue` in an
unrelated function — and `grids` is `{}` in all three classes that declare it. So
the candidate had nothing to do with the receiver's value.

## The mechanism was already written down, in a fixture

`test/test_nilpy_variant_method_pick_by_arity.npy`, in its own header:

> *"The candidate scan keeps one entry per class declaring the name and takes the
> first found; a KEYWORD argument could already promote a better one, but a call
> that writes NO arguments names nothing."*

That fixture fixed the **zero-argument** case (`x.fetch()` taking the first class
whose `fetch(key)` requires an argument). This ticket is the **two-argument**
case of the identical scan: `pop(k, d)` took a class whose `pop` accepts none.
The remedy the fixture already established — prefer a candidate whose arity can
accept the call as written — covers both, and was applied in only one direction.

## WHY SIX REDUCTIONS FAILED, which is the useful part

Not bad luck. A first-wins scan's answer depends on **class registration order
across the whole program**, so in any small program `TPyDict` is reached before
`TPyDeque` and the call binds correctly. The six shapes tried — static dict,
two-class dynamic member, tuple-unpacked receiver, empty dict literal, a
three-class receiver, and the same with a `collections.deque()` present elsewhere
— are all too small to move the order, and the last of those tested the deque
hypothesis directly and disproved it.

This is `CLAUDE.md`'s rule arriving exactly as written: **a first-wins table is
exposed only by the arrangement that puts the correct entry LAST**, and the
passing arrangements are the population everyone writes. A reduction is the wrong
instrument for this class of bug; the scan order is the thing to read.

## Next step

Read the candidate scan's ordering (`hitCi`/`hitPi` selection in
`PyParseVariantMethod`, around the `hitCi < 0` first-wins assignments) and make an
arity-compatible candidate win over an arity-incompatible one — the two-argument
direction of the fix that fixture already carries for zero arguments. Do NOT write
a seventh reduction.
