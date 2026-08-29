---
summary: "FPC seed canary RED: rparser.inc calls RExprRecId at :1416, defined at :1754, no forward. pxx self-hosts fine (it does not require the forward); FPC does, so the cold-start bootstrap is broken. One-line fix, Track R's file."
type: regression
track: R
prio: 60
status: backlog
owner: unassigned
blocked-by: []
---

# FPC seed drift: `RExprRecId` called before its definition in `rparser.inc`

- **Type:** regression, cold-start bootstrap path — **Track R**
- **Filed:** 2026-08-29 by `frankB` (Track P) from a `tools/gate.sh quick` run
  taken for an unrelated Pascal-frontend fix. **Handed over, not fixed** — R
  owns `rparser.inc`.
- Same family as `bug-a-fpc-seed-drift-emitasmx64-forward`,
  `bug-n-fpc-seed-drift-pybytesci-used-before-forward`,
  `bug-n-fpc-seed-drift-pywiden-needs-a-forward-in-parser-inc`,
  `bug-a-fpc-seed-drift-pymaketruthy-forward-wrong-file`.

## The failure

```
rparser.inc(1416,12) Error: Identifier not found "RExprRecId"
compiler.pas(2111) Fatal: There were 1 errors compiling module, stopping
```

```
compiler/rparser.inc:1416:  recId := RExprRecId(scrutNode);   <-- use
compiler/rparser.inc:1754:function RExprRecId(node: Integer): Integer;   <-- definition
compiler/rparser.inc:2314:    optCi := RExprRecId(valNode);
compiler/rparser.inc:2924:      symIdx := RExprRecId(Result);
```

The other two call sites are after the definition; only `:1416` is ahead of it.

## Why it escaped the lane that introduced it

**pxx does not need the forward and FPC does**, so the whole per-fix loop is
green on it: `make compiler/pascal26` self-hosts and reaches its byte-identical
fixedpoint, the Rust tests pass, and nothing in the mandatory loop compiles the
compiler with FPC. Only the seed canary — which is in `gate.sh`, not in the
per-fix loop — sees it. That is the *fourth* time this exact asymmetry has
produced a seed drift, which is what
`decide-should-the-fpc-seed-canary-be-in-the-mandatory-loop` is about.

Consequence while it stands: **the compiler cannot be bootstrapped from source
with FPC.** Nothing an existing checkout does is affected, so it is invisible
until someone cold-starts.

## Provenance — measured, not inferred

Bisected only as far as "not mine": my working tree had exactly two modified
files (`compiler/pasparser_expr.inc`, `compiler/pasparser_lval.inc`) and neither
is `rparser.inc`. I did not stop at that reasoning — I stashed the diff and ran
the seed build the gate runs, verbatim, at clean HEAD:

```
git stash push compiler/pasparser_expr.inc compiler/pasparser_lval.inc
fpc -Mobjfpc -O2 -Tlinux -Px86_64 -FU<tmp> -o<tmp>/seedbin compiler/compiler.pas
  -> rparser.inc(1416,12) Error: Identifier not found "RExprRecId"
```

Reproduces at HEAD without my changes. Last commits touching the file:
`fa22da207` ("feat(rust): `if` as an expression, statement and tail forms",
2026-08-29), `2d99f0ab1`, `fcfe1cba1` — `RExprRecId`'s use at :1416 is inside
the `if`-as-expression scrutinee handling, so `fa22da207` is the likely author.
Not bisected further; R will know in one look.

## Fix

Add `function RExprRecId(node: Integer): Integer; forward;` above the first use
(or move the definition ahead of :1416). Then confirm with the seed build above
— **not** with `make compiler/pascal26`, which is green either way and is
precisely why this class of break keeps landing.
