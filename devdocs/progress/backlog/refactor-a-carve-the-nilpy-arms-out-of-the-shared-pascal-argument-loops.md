---
slug: refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops
track: A
prio: 45
type: refactor
status: new
owner: ""
blocked-by: []
summary: "The last 279 NilPy references in the shared Pascal parser, over 134 distinct Py* symbols, and they are NOT where the previous carve looked. ParseFactorCore already hands NilPy expressions to PyParseFactorCore and Exits at pasparser_expr.inc:521; every one of the 279 sits BELOW that line, guarded by `isNilPy` rather than `PyExprMode` -- NilPy arms threaded through the shared ARGUMENT loops (keyword binding, *args unpacking, overload promotion by keyword), which the expression hook never sees. Five routines carry 191 of them. Progress is measurable in one command and the target is zero: `fpc -dPXX_NO_NILPY` currently reports 279 unresolved sites."
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

## Gate

`make compiler/pascal26` (byte-identical is the bar — the default build must not
move, and the previous carve steps met it), plus the NilPy suite via Track T. A
step that changes the default binary is a behaviour change and is not this
ticket.

## Related

- [[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]] — the parent, parked behind this
- `devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` — share the AST and the IR, duplicate the parser
- `devdocs/dev/root-cause-over-microfix.md` — the argument for carving instead of stubbing, made in the parent
