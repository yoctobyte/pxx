# Next session: finish the int-promotion default

Written 2026-08-04 while the context was warm, by the session that got it
90% of the way and stopped. Read this before touching anything.

## The goal, and it is already decided

Land **option 1**: every NilPy `int` binding is promotable, native only where the
range is provable. Rene decided the cost question — *"python wasn't meant for
performant tight loops in the first place"* — so the measured **10.1x** on
integer loops (0.868s -> 8.739s over 20M iterations) is ACCEPTED. Do not
re-litigate it; `decide-nilpy-int-promotion-costs-10x-on-ordinary-loops` is in
`decided/`. Expect every benchmark row in `tstate/` to step when this lands;
that is not a regression.

Tickets: `unfinished/bug-nilpy-int-promotion-decided-statically-so-computed-overflow-wraps`
(the work) and `backlog/task-n-enumerate-the-promo-surface-by-output-diff` (the
blocker, p60).

## The one mistake to not repeat

The earlier survey concluded "only hex/bin/oct break". **It checked whether
programs COMPILED.** Re-run diffing OUTPUT and four more shapes were silently
wrong. In a frontend whose entire risk model is silent wrong values, compile
success is the wrong thing to measure. **Diff stdout against CPython over a
corpus. Exit status proves nothing.**

## Applying the patches

- `patches/int-promotion-option1-arith-typing.patch` — applies clean
  (`PyIntGrowsOp` + `PyIsMachineIntTk` in symtab.inc, one arm at each of the two
  binop typing sites in parser.inc).
- `patches/int-promotion-option1-module-scope.patch` — **does NOT apply**. Its
  `tkInteger -> tyInt64` hunk already landed as `ae4057989`. Hand-apply the other
  three pieces into pyparser.inc: `PyBlkIntName` + `PyBlkIntArith` before
  `PyCollectModuleLocalsAST`, the `blkTk := tyPromoInt64` arm in the module
  pre-pass's block-assignment shapes, and the `for i in range(...)` ->
  `forElemTk := tyInt64` arm. All three are quoted verbatim in the patch.

Module scope needs its own arms because its pre-pass may not trial-parse a RHS
inside a control-flow block (an unseen name calls Error and Halts), so the
accumulator shape is recognised from TOKENS.

## Known state of the surface

Fixed and landed already:

| site | commit |
| --- | --- |
| `hex`/`bin`/`oct` -> `PXXPromoToBase` | `762c7addf` |
| `str()` -> `PXXPromoToStr` | `fca6c8a87` |
| `pystr_repeat` count narrowing | `fca6c8a87` |

Still broken with the patches applied:

- **`round(i + 1)`** printed `5553112` — the slot address. Same shape as `str`:
  its intrinsic hand-builds the call. Should be the same fix.
- **`[0] * (i + 1)`** raised `TypeError: unsupported operand type(s)`. This is
  the one that BLOCKS landing — `[0] * n` is how Python allocates a fixed-size
  list and it is already in the corpus. **`IRPyOperandKind` was tried** (adding
  `TypeIsPromoInt` to the numeric kind so the pair stops being "provably
  undefined") **and it made things WORSE** — the TypeError became a garbage
  number, and `promo * list` regressed too. So `IRPyStaticPairUndefined` is not
  the only thing in the way; find the list-repeat lowering itself before
  changing that predicate again.

Assume there are more. The suite plus a generated probe over every builtin and
operator against every operand shape is the way to find them.

## Why this whole class exists — three facts

1. **`FindProc` returns ONE proc and never consults overloads**
   (`project_findproc_by_name_ignores_overloads`). Every hand-built call site
   therefore lands a promo on a parameter that neither narrows nor boxes it.
2. **Promo is deliberately NOT reported by `TypeIsOrdinal` / `TypeIsPyNumeric`**,
   so a promo operand classifies as "unknown" and predicates pick the
   not-a-number path.
3. **An rvalue IS the slot address** (`decide-promoint-rvalue-representation`).
   So (1) and (2) both surface as a pointer used as a value.

## The lever you have — use it

`IRLowerCallArg` now has a **promo -> POINTER parameter** arm that passes
`IRPromoAddrOf`. It **must stay before the promo -> ordinal narrowing arm**,
because `TypeIsOrdinal` INCLUDES `tyPointer` (17 sits with tyNativeInt/
tyNativeUInt) — placed after, it silently does nothing and looks like a failed
fix. This means **a frontend lowering can now reach any promocore entry point
with an ordinary `AN_CALL`**, instead of hand-building IR the way `writeln` and
the operators do. That is what made hex/bin/oct and str cheap; use it for
`round` and anything else.

## promocore facts worth having

- The unit is **`promocore`**, renamed from `promoint` (`c4f6ef4b9`) because the
  unit name collided case-insensitively with the `PromoInt` TYPE. Pinned as v242.
- `PXXPromoToBase(a: Pointer; base: Integer)` renders bases 2/8/16 off the limbs.
- **Its interface spells declarations `function␣␣Name`** — TWO spaces. A
  `grep "function PXXPromoToStr"` returns one hit and looks like it is
  implementation-only. It is not. An implementation-only routine has no parameter
  types for the parser to match, which cost an hour.
- `PromoInt` in Pascal is a first-class type but has three gaps —
  `bug-a-promoint-shr-yields-nothing-and-a-machine-int-cast-yields-the-slot-address`:
  `shr` yields nothing, `Integer(n)` yields the slot address, and a PromoInt
  PARAMETER cannot reach the runtime at all. None is on the critical path if you
  lower in the frontend, but do not plan around writing a helper that takes one.

## Method

1. Apply the patches (above).
2. `make compiler/pascal26`, then run the `.npy` suite diffing **stdout** vs
   `python3`, plus a generated builtin/operator probe.
3. Per divergence: narrow at the call boundary, box to a variant, or teach the
   predicate. Prefer the `AN_CALL` + promo->Pointer route.
4. Repeat until the corpus is clean. THEN land.
5. Gate is the ordinary per-fix loop (`tools/gate.sh quick`); T sweeps the rest.
   Note `test-nilpy` is a full-tier job, so quick will NOT catch a promo
   regression — expect T to be the one that tells you, within the hour.

## Housekeeping traps this session hit

- **Never `cat >>` a ticket path you have not claimed** — it creates a phantom in
  `working/` beside the real one. `git stash` can also silently undo a claim.
  `ls devdocs/progress/working/` before every commit; it should be empty.
- **`ls test/ | grep <topic>` before creating a test file.** A new test was
  written over an existing one with a name that read alike; it passed its own new
  recipe and broke the original's.
- Backticks inside a double-quoted `git commit -m` get command-substituted. Use a
  heredoc with a quoted delimiter.
