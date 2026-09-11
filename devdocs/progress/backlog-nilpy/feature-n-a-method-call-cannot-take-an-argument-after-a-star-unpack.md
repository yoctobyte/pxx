---
slug: feature-n-a-method-call-cannot-take-an-argument-after-a-star-unpack
track: N
prio: 75
type: feature
blocked-by: []
status: backlog
found: 2026-09-11
found-by: frankuser
owner: unassigned
summary: "`self.m(*xs, kw=v)` and `obj.m(*xs, kw=v)` are refused; the SAME shapes on a free function all work. Plain calls route to PyStarMixedForwardCall -> PyStarForwardCall (a run-time arity dispatch that handles positional, *iterable, name=value and **mapping in any order); the three METHOD sites use the older compile-time PyStarExpandCallArgs, which claims every remaining slot and so cannot leave one for a trailing argument. Two different error messages, so it reads as two bugs. This is the current wall on the lekkerzeilen closure (`self._level_here(*self.start[:2], forced=self.level_forced)`) and it is the LAST one a first-failure instrument can see. FULLY DIAGNOSED, NOT STARTED: the fix is to route the method sites through the same forwarder with `self` as slot 0, and the concrete blocker is that `k` inside PyStarForwardCall doubles as the LIST POSITION and the PARAMETER INDEX, which differ by one for a method -- about 12 sites in a ~200-line generator."
---

# A method call cannot take an argument after a `*` unpack

## The matrix, measured against CPython

| shape | result |
| --- | --- |
| `f(*xs, forced=7)` free function | **works**, 10, matches CPython |
| `f(1, *xs, forced=7)` free function, star LATER | **works**, 13, matches |
| `f(*xs, 3)` free function, trailing POSITIONAL | **works**, 6, matches |
| `K().m(*xs, forced=7)` | FAILS — `expected ')' before ','` |
| `self.m(*xs, forced=7)` inside a method | FAILS — `an argument after *unpacking is not supported yet` |

The two failures are the same gap at two sites, and they report differently,
which is why this looks like two problems.

## Why the free function works and the method does not

A plain call with a star in its argument list is detected *before* the argument
loop (`pyparser.inc:52341`) and routed to **`PyStarMixedForwardCall`**, described
in its own header as *"ONE loop for every spelling of a call that forwards
`*`/`**` into a callee with ORDINARY parameters — positional, `*iterable`,
`name=value`, `**mapping`, in any order and any number."* It builds a positional
list and a keyword dict and hands both to `PyStarForwardCall`, which dispatches on
`len(args)` at run time.

The three method sites never got that and still use the compile-time expansion:

- `pyparser.inc:17058` — `PyStarUnpackMethodArgs`, the `self.m(...)` path. Errors
  explicitly on a trailing comma.
- `pyparser.inc:17426` — the statically-bound `obj.m(...)` path. `Break`s after
  expanding, so the trailing comma reaches `Expect(tkRParen)` and reports
  `expected ')' before ','`.
- `pyparser.inc:18558` — the dynamically-dispatched receiver. Same `Break`.

`PyStarExpandCallArgs` fills `wanted := total - firstSlot` slots — every
remaining declared parameter — so by construction there is no slot left for an
argument written after the star. That is not a missing check; it is the
expansion's whole design.

## The fix, and the one thing that makes it awkward

Route the method sites through `PyStarMixedForwardCall` with `self` as slot 0.
This is the `devdocs/dev/normalise-dont-special-case.md` move, and the code
already says so in two places: 17095 calls the asymmetry *"the
one-concept-two-sites shape"*, and 52347 records that the mixed collector
replaced exactly this class of hand-rolled refusal for plain calls.

**The blocker is an index that means two things.** Inside `PyStarForwardCall` the
loop variable `k` is used as BOTH:

- the **list position** handed to `pystar_arg` / `pystar_arg_kw`, and
- the **parameter index** for `Procs[procIdx].Params[k].Name`,
  `ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + k]`,
  `DefaultArgValueNode(procIdx, k)` and `PyStarParamTakesVariant(procIdx, k)`.

For a free function they are the same number. For a method they differ by one,
because `Procs[mpi].ParamCount` counts `self`. So the change is to split `k` into
`listPos` and `prm := listPos + selfSlots`, and to express `total`, `required` and
`fwdTotal` in list-position terms while the arity guard keeps reporting the
callee's own counts. About twelve sites.

It is mechanical but it is inside a code generator, and getting it wrong yields a
**plausible wrong argument value at run time** — no crash, no diagnostic. Whoever
does it should write the CPython differential FIRST, over every row of the matrix
above plus defaults, `**mapping`, and a starred list shorter than the required
arity.

`slotSyms` is `array[0..15]` and there is an explicit 16-parameter ceiling; with
`self` occupying one, a method tops out at 15 forwarded slots. Worth stating in
the message rather than discovering.

## Two corrections to comments in the tree

Both were measured while diagnosing this, and both will mislead the next reader:

1. `pyparser.inc:17087` says *"A star in FIRST position is handled before this, by
   the run-time arity dispatch (PyStarForwardCall) ... From any later position the
   expansion is the compile-time one"*. **`f(1, *xs, forced=7)` works and answers
   13**, so later positions reach the forwarder too. The first/later distinction
   the comment draws is not the live one; plain-vs-method is.
2. The same comment says the compile-time path *"refuses a callee with defaults in
   the starred range rather than filling None"*. That was retired on 2026-09-10 —
   the code immediately below it now fills each optional slot with its declared
   default and overwrites from the list at run time, and its own later comment
   says so.

## What it blocks

`umbrella-lekkerzeilen-compiles-and-runs-under-nilpy`. The closure's wall is
`self._level_here(*self.start[:2], forced=self.level_forced)` in app.py — one call
site, and the last visible one.

**A corpus edit would clear it** (the umbrella's standing rule from the owner
permits editing lekkerzeilen), and it is NOT recommended as the fix: this is
ordinary Python that plain calls already support, so the asymmetry is ours, not
the program's. Noted because it is the owner's call whether to unblock the demo
that way in the meantime, not a seat's.

## 2026-09-11, later: the differential this ticket asks for LARGELY EXISTS

Checked before writing one, because writing a second would have been the
duplication `normalise-dont-special-case.md` is about. There are ~25 star/unpack
fixtures under `test/`, and they already cover the plain-call side that the fix
must not break:

- `test_nilpy_star_element_anywhere`, `test_nilpy_star_not_first_argument` — star
  in any position.
- `test_nilpy_star_unpack_into_defaults`,
  `test_nilpy_star_unpack_into_a_target_with_defaults`,
  `test_nilpy_default_before_star_args` — the defaults interaction, which is the
  part of `PyStarForwardCall` the index split touches most.
- `test_nilpy_star_forward`, `test_nilpy_star_unpack_into_a_collecting_callee`,
  `test_nilpy_leading_double_star_call`, `test_nilpy_ctor_star_and_kwargs` — the
  forwarding and `**` paths.

**And the EVALUATION-ORDER claim is tested**, which is the one a value comparison
cannot see and therefore the one most likely to be missing.
`test_nilpy_star_element_anywhere.npy:74`:

```python
print(g(note(1), *[note(2)], z=note(3)))   # 123
print(order)                               # [1, 2, 3]
```

That is exactly the property `PyStarMixedForwardCall`'s header asserts — source
order across the element kinds — so a refactor that changes hoist order is caught.

**What this means for the cost.** The regression risk on the working half is
already instrumented; what is NOT covered is the method side, which cannot be
tested until the fix exists. So the differential to write is the METHOD matrix
only — the five rows in the table above, plus a method with defaults in the
starred range, a method taking `**mapping`, and a method order-log mirroring the
`note()` pattern above. That is a smaller job than this ticket first implied.

**Still not attempted unattended**, and the reason is unchanged by the above: the
off-by-one lives in a code generator and its failure mode is a plausible wrong
argument at run time with no crash and no diagnostic. Better coverage of the half
that already works does not make the half with no coverage safe.
