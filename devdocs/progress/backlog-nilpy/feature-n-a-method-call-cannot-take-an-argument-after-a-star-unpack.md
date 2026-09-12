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
summary: "PARTLY FIXED 2026-09-12. A KEYWORD argument after the star now works at all three METHOD sites (`obj.m`, `Cls().m`, and the dynamic receiver) -- a keyword NAMES its slot, so the fix was to stop the compile-time expander claiming every remaining slot: PyStarTrailingKwMinSlot looks the tail up and PyStarExpandCallArgs caps `total` at the lowest slot a trailing `name=` claims. This cleared the lekkerzeilen closure, which moved 438 lines further into app.py. STILL OPEN, and it is the hard half: a trailing POSITIONAL (`obj.m(*xs, 5)`), whose slot is `firstSlot + len(starred)` and therefore a RUN-TIME fact a compile-time expansion does not have. That needs the method sites routed through PyStarForwardCall, where `k` doubles as the LIST POSITION and the PARAMETER INDEX -- they differ by one for a method, ~12 sites in a ~200-line generator. A trailing `**mapping` is the same shape. The CONSTRUCTOR arm of even the keyword half is its own ticket."
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

## 2026-09-12: the KEYWORD half landed; the POSITIONAL half is what is left

The diagnosis in this ticket was right about the mechanism and wrong about the
cheapest fix, and the correction is worth more than the fix.

**The ticket said** the route was to send the method sites through
`PyStarForwardCall` with `self` as slot 0, blocked on `k` meaning two things.
That is still true for a trailing POSITIONAL.

**It is not true for a trailing KEYWORD, and that is what the wall actually
was.** A keyword argument names its slot, so it does not depend on how many
slots the star consumed. The refusal existed because
`PyStarExpandCallArgs` is GREEDY by construction:

```pascal
total := Procs[procIdx].ParamCount;
wanted := total - firstSlot;        { every remaining slot, always }
```

The star claimed `forced`'s slot, so nothing could follow it. Capping `total` at
the lowest slot a trailing `name=` claims is the entire change — `required`,
`wanted` and both arity bounds all derive from `total`, and with no cap the
arithmetic is byte-for-byte what it was. No index-meaning split, no change to
the run-time dispatch generator at all.

**Measured, against CPython, before and after** — and the three refused shapes
reach three different sites, which is why the fixture has a row for each:

| shape | site | before | after |
| --- | --- | --- | --- |
| `f(*xs, forced=9)` | `PyStarMixedForwardCall` | worked | worked |
| `obj.m(*xs, forced=9)` | `PyStarUnpackMethodArgs` | `an argument after *unpacking` | **matches CPython** |
| `Cls().m(*xs, forced=9)` | `PyParseClassMethodCall` | `expected ')' before ','` | **matches CPython** |
| `pick().n(*xs, forced=9)` | `PyParseVariantMethod` | `expected ')' before ','` | **matches CPython** |
| `Cls(*xs, forced=9)` | `PyClassCreate` | refused | **still refused**, own ticket |

Two of the three reported `expected ')' before ','` — a message about
punctuation, for an argument list that is plain Python, naming neither the star
nor the callee. That is why this read as two unrelated bugs. All five sites now
say the same true thing, and an undeclared keyword name after a star now reports
`C.m has no parameter named 'nosuch'` instead of a syntax error: the lookahead
returns a distinct `-2` for that case so the ordinary loop can name it. A typo
was being reported as a missing feature.

**The diagnostic note for whoever takes the positional half:** the `**`
expansion (`PyStarExpandKwArgs`) deliberately does NOT take the cap, so
`m(**d, forced=9)` is still refused and is a third shape, not a fourth site.

## What the positive controls were

- HEAD before the change refused all three method shapes, each with the message
  in the table above. That is the control, taken on the pre-change binary.
- The pin refuses the fixture too, but **for an earlier reason** — it predates
  the 2026-09-10 defaults fix and stops at `it has parameters with defaults`. So
  it is not a clean control for this refusal; cite HEAD-before, not the pin.
- Four shapes that MUST still refuse were checked and do, with the right message
  now: trailing positional, trailing `**mapping`, the ctor, and an undeclared
  keyword name.
- The fixture's `plainfn`/`starfn` rows already worked; they are reach-checks, so
  a harness that is not reaching the file cannot look like a pass.
- The order-log row is the only one a value comparison cannot produce.

## A THIRD refused shape, found by measurement after the fix was written

`C().m(*[1], nosuch=9)` where the callee is `def m(self, a, **kw)` — a keyword the
callee accepts only through its `**kwargs` COLLECTOR.

**The cap declines this deliberately.** `PyStarTrailingKwMinSlot` returns -1, not
-2, when `ProcPyKwIdx[mpi] >= 0`, so the old refusal stands. The reason is that
`PyKwArgIndex` does **not** error for a collector callee — it returns the
`-(node+1)` key encoding and the loop carries on — so with the star having
already claimed every slot, the call COMPILED and raised
`forwarded call got 1 arguments, expected 2 to 2` at run time.

**What the baseline actually was, stated precisely because the first reading of
this was wrong:** pxx refused that shape before the cap existed too, with
`expected ')' before ','`. So the cap did not break a working shape — it turned a
compile-time refusal into a run-time failure, which is strictly worse, and
declining the collector restores the refusal while keeping the honest message.
Not a regression from a working state; a regression in the KIND of failure.

**And the variable receiver is different, measured:** `c = C(); c.m(*[1],
nosuch=9)` WORKS and matches CPython, because a collector callee sets
`mai := ParamCount` before `PyStarUnpackMethodArgs`'s guard is tested, so that
site is never reached and the kwargs packing path handles it. It is pinned in the
fixture for exactly that reason — the working and refused halves of one shape
differ only in how the receiver was written.

**How this was found, which is the part worth keeping.** Four negative controls
were written and all four passed, and none of them used a callee with a
collector — a control set drawn from the wrong population, the failure
`CLAUDE.md` describes under "A GUARD THAT CANNOT FAIL". The shape only surfaced
because a separate question ("is the -2 path reachable where PyKwArgIndex does
not error?") was asked of the CODE rather than of the controls. A guard asserting
the four shapes I had thought of would have certified this one.
