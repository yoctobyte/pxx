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
summary: "FIXED 2026-09-12, and the cause was NOT the scan order this ticket previously blamed. Measured with three read-only probes: the failure is in PyParseVariantMethod (the dynamic path), smArgN=2 is read correctly, nDual=2, and `arFits` -- the guard deciding whether to DEFER the call to run-time dispatch -- was set by the dual-candidate arm. THE DEFECT IS THAT TWO TESTS ASKING THE SAME QUESTION DISAGREED: `arFits` accepts a dual candidate either because its primary mmi fits OR because FindUMethArityStrict finds a fitting OVERLOAD of that class, while the arity PROMOTION beside it (pyparser.inc:18389, which already existed) tested only the primary mmi. So an overload-only match satisfied \"some candidate can accept this arity\", suppressed the deferral, promoted nothing, and left the call bound to a pick that cannot accept it -- then the arity check raised a hard error naming a class the program never mentions. TPyDict was passed over purely because pylib declares pop(k) at :367 before pop(k, d) at :368. Fix: give the promotion the same two-armed test. It is gated on the current pick NOT accepting the written arity, so it can only affect calls that are hard compile errors today. NO REGRESSION FIXTURE EXISTS and that is deliberate -- SEVEN reductions now fail, the closest passes on the PRE-FIX binary too, and committing it would be a guard that cannot fail. Verified on the app: the lekkerzeilen closure moved app.py:1678 -> 2360."
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

## 2026-09-12, resolved: the mechanism, measured rather than guessed

Three probes, each read-only (the first attempt reused a live local and was
redesigned — see the logbook):

| probe | reading |
| --- | --- |
| which of the two arity-error sites fires | `[S2-variant]` — `PyParseVariantMethod`, the DYNAMIC path |
| the argument count the guard sees | `smArgN = 2`, correct |
| which `arFits` disjunct, and `nDual` | `p=4202` → `nDual=2`, set by the DUAL-CANDIDATE arm |

**The defect is two tests asking one question and disagreeing.** In
`PyParseVariantMethod`:

- `arFits` (the guard that decides whether to DEFER the whole call to run-time
  dispatch) accepts a dual candidate **two** ways: `ProcArityMatches` on its
  primary mmi, *or* `FindUMethArityStrict` finding a fitting **overload** of that
  class.
- The arity **promotion** at `pyparser.inc:18389` — which already existed, with a
  comment stating the exact principle — tested only the **first**.

So an overload-only match says "someone can take this call", the deferral is
suppressed, nothing is promoted, and the committed pick still cannot accept the
call. The hard arity error then fires against it. `TPyDict` lost purely to
declaration order: `pop(k)` at `compiler/builtin/pylib.pas:367`, `pop(k, d)` at
`:368`.

The fix gives the promotion the same two-armed test. **Gated on the current pick
NOT accepting the written arity**, so it can only change calls that are hard
compile errors today — it cannot silently alter a working program.

## WHAT THIS TICKET GOT WRONG, because the correction is the reusable part

It said the next step was to read the scan order and not write a seventh
reduction. Half right:

- **Right** that a reduction was the wrong instrument.
- **Wrong** about the target. It framed this as a missing mechanism / first-wins
  scan-order bug. The scan order is real but there are already **three**
  promotions layered on it (keyword-across-classes, arity-across-classes,
  keyword-across-overloads-of-one-class), so the defect was a **gap between two
  existing tests**, not an absent mechanism. Reading `18389` first turned what
  would have been a duplicated mechanism into a two-line change.

Three mechanisms serving one concept is the count `root-cause-over-midfix` calls
a design flaw, and this bug is what that costs: they do not agree with each other.
A future pass should consider collapsing them into one "best candidate for this
call site" question asked once.

## AND THERE IS NO REGRESSION FIXTURE — deliberately

A seventh reduction was attempted, now targeting the measured mechanism (a
doubly-dynamic receiver — Variant `tile` AND a `grids` declared by three classes —
plus `collections.deque` imported so a deque is registered). It **compiles and
prints CPython's exact output on the PRE-FIX binary too**, so as a regression test
it is a guard that cannot fail, and it is not committed.

The reason is the whole-program property this ticket identified correctly:
first-wins candidate order depends on class registration across the entire
program, and no hand-written fixture is large enough to put `TPyDeque` ahead of
`TPyDict`. What would actually pin this is a fixture that controls registration
order directly, or a unit test on the promotion function rather than on a compiled
program. Neither exists today.

**Verification is therefore the app itself**: the closure moved `app.py:1678` →
`app.py:2360`, 682 lines, with the next wall an unrelated and clearly-diagnosed
unimplemented feature (extended-slice assignment).

One live bug was found while reducing and is separately filed:
`bug-n-a-collections-deque-segfaults-at-run-time` — `collections.deque()` compiles
and crashes, identically on both sides of this fix.
