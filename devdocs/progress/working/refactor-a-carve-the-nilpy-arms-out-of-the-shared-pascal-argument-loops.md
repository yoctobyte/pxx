---
slug: refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops
track: A
prio: 45
type: refactor
status: working
owner: frankA
blocked-by: []
summary: "The last NilPy references in the shared Pascal parser, and they are NOT where the previous carve looked. ParseFactorCore already hands NilPy expressions to PyParseFactorCore and Exits at pasparser_expr.inc:521; every remaining site is BELOW that line, guarded by `isNilPy` rather than `PyExprMode` -- NilPy arms threaded through the shared ARGUMENT loops (keyword binding, *args unpacking, keyword-driven overload promotion), which the expression hook never sees. THREE SPECIES, only one of which is a move: a shared helper wearing a Py prefix, a semantic predicate needing a neutral hook, and the argument loops needing one NilPy argument-list parser. Treating all three as species 1 is how the 176 stubs the parent rejected get written by accident. Progress is one command and the target is zero: `fpc -dPXX_NO_NILPY` reported 279 sites at filing and 266 now, after two steps: StoredName moved to util.inc (closing the compiler's only frontend-to-frontend dependency, cparser.inc -> pyparser.inc) and the first REGION carve, which closed six references with a six-line hook. Report that ratio per region -- near 1:1 means you have hit a species-2 site and should design the concept-level hook instead."
---

# Carve the NilPy arms out of the shared Pascal *argument* loops

- **Filed:** 2026-08-31 by frankA, from
  [[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]],
  which is parked behind this and carries the history.
- **Continues** the campaign of `task-a-carve-nilpy-selectors-out-of-parser-inc`
  and `task-a-carve-nilpy-lvalue-parsing-out-of-parser-inc` (both `done/`). Those
  landed; the coupling went 176 symbols / 426 sites → **134 / 279**, not to zero.

## The finding that redirects the work

`ParseFactorCore` **already has the hook**:

```pascal
  if PyExprMode then
  begin
    PyParseFactorCore;
    Exit;
  end;                       { pasparser_expr.inc:521 }
```

So the obvious model — *NilPy expressions still parse through the Pascal
expression chain* — is **wrong**, and reading the symbol list confirms it the
wrong way round: those 98 `ParseFactorCore` sites are all **after line 521**,
which `PyExprMode` can never reach. They are guarded by **`isNilPy`**, a
different predicate, and they live in the **argument loops** — `PyBindKwArgs`,
`PyPackStarArgs`, `PyStarUnpackMethodArgs`, `PyPromoteOverloadByKwAt`,
`PyKwDictArgsHere`. Python's *call syntax* (keywords, `*args`, `**kwargs`,
keyword-driven overload selection) has no Pascal counterpart, so it was threaded
into the shared loops instead of being parsed alongside the rest of the language.

**That is the thing to move, and it is not an expression problem.** Anyone who
plans this as "finish carving the expression parser" will spend the session in
the wrong half of the file.

## Where they are

| file | sites | routines |
| --- | --- | --- |
| `pasparser_expr.inc` | 191 | `ParseFactorCore` 98, `ParseFactor` 56, `ParseSimpleExpr` 17, `ParseTerm` 11, `ParseExpr` 9 |
| `pasparser_lval.inc` | 68 | |
| `pasparser_stmt.inc` | 13 | mostly one call loop at ~6119-6200, plus `PyHoistPark`/`PyHoistRestore`/`PyParseSuite` at ~320-387 |
| `pasparser_call.inc` | 5 | |
| `pasparser_name.inc` | 1 | `PyIsClassTypeExact` |
| `cparser.inc` | 1 | `PyStoredName` — **the C frontend depending on the NilPy one** |

The `cparser.inc` row is one line and is worth doing first: it is the only
frontend-to-frontend edge in the set, and
`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` says a shared parser
helper couples two specs and is wrong in both. Two frontends is worse.

## The measurement, which is the whole progress metric

```
fpc -O2 -Tlinux -Px86_64 -Se1000 -dPXX_NO_NILPY -FU<tmp> -o<tmp>/pc compiler/compiler.pas
```

~10 seconds, and it prints every remaining site with its file and line. **Zero is
done**, and done means `PXX_NO_NILPY` joins the documented defines.

**Do not read a small number as progress without checking what it is counting.**
The first run of that command answered **7**, because only the `{$include}`s were
guarded and `pyforwards.inc` was still declaring ~190 forwards — FPC resolves a
name against a forward and defers the complaint to the end of the module, which
it never reached. 7 was the count of symbols with **no declaration**, not with no
**body**. The guards are in place now and the number is honest, but the shape of
that error recurs: [[the-name-is-not-the-thing]].

## Suggested order, smallest blast radius first

1. `cparser.inc` (1) and `pasparser_name.inc` (1) — one edge each.
2. `pasparser_stmt.inc` (13) — two clustered regions.
3. `pasparser_call.inc` (5).
4. The argument loops in `pasparser_expr.inc` / `_lval.inc` (259), which is the
   real job: one NilPy argument-list parser called from the shared loops, rather
   than N `isNilPy` arms inside them.

Land each step green; the metric goes down monotonically and never needs a
judgement call about whether the step "counted".

## Gate — and the bar this ticket first stated was WRONG

`make compiler/pascal26` plus the NilPy suite via Track T.

**Do NOT gate on the compiler binary being byte-identical to the previous one.**
This ticket said that in its first draft and it is not achievable for a MOVE:
relocating a function between `.inc` files changes the order procedures are
emitted in, so the binary differs while nothing about its behaviour does. That is
also why `make compiler/pascal26`'s "byte-identical self-host fixedpoint" is not
the same claim — it says the compiler reproduces *itself*, not that it equals
yesterday's build.

**The bar that IS right for a move, and it is stronger:** build the compiler from
the sources before the move and from the sources after, then compile a batch of
programs with both and compare the EMITTED binaries. Measured for the
`StoredName` step: nine programs identical, zero differing, including
`compiler/compiler.pas` itself and the C and NilPy sites the moved function is
called from. And the sharpest form of it falls out for free — the *before*
compiler, run over the *after* sources, produces exactly the after compiler
(`d6ab8200480a`), while the two compilers themselves differ. Semantic content
unchanged; only the source moved.

A step that changes an emitted program is a behaviour change and is not this
ticket.

## Related

- [[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]] — the parent, parked behind this
- `devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` — share the AST and the IR, duplicate the parser
- `devdocs/dev/root-cause-over-microfix.md` — the argument for carving instead of stubbing, made in the parent


## Step 1a DONE 2026-08-31 — `PyStoredName` → `util.inc`'s `StoredName`

The C→NilPy edge and six Pascal→NilPy sites, closed by a move rather than a
guard, because the function was never NilPy's: it appends a string to the shared
`TokChars` pool and returns its offset, which every frontend that mints a
synthetic token needs. `cparser.inc`'s own comment had already worked this out —
*"a generic ... helper (despite its name/home in pyparser.inc)"* — and left it
where it was. **A note is not a fix**, and this is the exact shape of
[[the-name-is-not-the-thing]]: the `Py` prefix answered "whose is this?"
correctly for 70 of its 78 callers.

Named `StoredName` deliberately, not something new:
`refactor-a-seven-frontends-borrow-rust-parser-helpers` (p22) already owns the
identical `RStoredName` and already prescribes *"move and reword, drop the R"* —
so this lands on the name that ticket's plan implies, and its fold now has one
target instead of two. **Three copies of this exact body remain**, differing only
in an overflow message: `TokCharsAppend` (`pasparser_class.inc`), `RStoredName`
(`rparser.inc` — which tells an Erlang or Zig program that IT is Rust) and
`BStoreChars` (`bparser.inc`). Deliberately NOT folded here: that is the other
ticket's work, and folding them changes three error strings, which would have
cost the output-equivalence proof above for no gain to this ticket.

**279 → 272.**

### And the next site is a different KIND, which is the thing to notice

`pasparser_name.inc:280` is `if isNilPy and NameHasUpper(name) and
PyIsClassTypeExact(name) then Exit;` — one line, and it is NOT a miscategorised
helper. It is a piece of Python's own name-resolution semantics sitting in the
shared resolver. Moving it is meaningless; guarding it is the 191-wrapper answer
the parent ticket rejected. It wants a **neutral hook the frontend answers**, and
the same is true of the argument loops.

So the 272 are at least three species and only one of them is a move:

1. **a shared helper wearing a frontend's prefix** — `StoredName`. Move it. Done.
2. **a semantic predicate** — `PyIsClassTypeExact` and friends. One neutral hook
   per CONCEPT, defaulting to the Pascal answer, overridden by the frontend.
3. **a parsing responsibility** — the argument loops, 259 of the 272. One NilPy
   argument-list parser, called once.

Anyone planning this as one mechanical sweep will get species 1's answer and
apply it to species 2 and 3, which is how the 176 stubs the parent rejected get
written by accident.
## Step 1b DONE 2026-08-31 — the first REGION carve, and the ratio that justifies the campaign

`ApplyCallResultPtrSuffix`'s NilPy arm (`f()[i]` / `f()[a:b]` on a str-returning
call) moved to `pyparser.inc` as `PyStrCallResultSuffix`, behind a neutral
trampoline in `pyforwards.inc`'s unguarded island beside `ParseArgExpr`.

**272 → 266. Six references closed by a six-line hook.**

That ratio is the whole argument. A hook **per symbol** is the 176-stub answer
the parent ticket rejected, wearing a different hat; a hook **per region** is
not, and this measures the difference on a real region rather than asserting it.
Anyone continuing this should report the ratio for their region — if it
approaches 1:1 they have found a species-2 site and should stop and design the
concept-level hook instead.

### The shape, so it does not have to be re-derived

- **The selecting condition stays at the call site**, because it names nothing
  frontend-specific: `PyExprMode` is a plain flag in `defs.inc`, and `tk` and
  `CurTok.Kind` are shared. Only the BODY is NilPy's. Regions where the
  *condition* needs a Py function are species 2 and want a different answer.
- **The trampoline carries the `{$ifdef PXX_NO_NILPY}`**, so exactly one place
  knows `pyparser.inc` may be absent.
- **`var` parameters, not a return**, because the caller walks a suffix CHAIN and
  both the node and its type kind feed the next suffix.
- Trampolines live beside `ParseArgExpr` for now. **When there are more than a
  handful they should move to their own `frontend_hooks.inc`** — noted so the
  next person moves them deliberately rather than discovering a pile.

### Verified, and the population was checked rather than assumed

Output equivalence, before-build vs after-build, on eleven programs including
`compiler/compiler.pas` itself: **11 identical, 0 differing**. Five of them are
the `.npy` subscript tests, and each also matches CPython.

**And a positive control, because six greens over code that is never reached is
not a measurement.** `PyMakeStrIndex(node, CurASTNode)` was changed to
`PyMakeStrIndex(node, GenZeroLit)` — always index 0 — the compiler rebuilt, and
`test_nilpy_subscript_of_a_call_result.npy` diverged from CPython immediately
(`b a e e a` → `a a a a a`). The tests do reach the carved code. Reverted, and
the restored build is byte-identical to the pre-control one (`be40b3454349`).

That test's own header, written by whoever fixed the original bug, says
*"`f()[0]` was 'correct', which is exactly how it survived — any probe must use
a NON-ZERO index"*. The control was designed against that sentence.
