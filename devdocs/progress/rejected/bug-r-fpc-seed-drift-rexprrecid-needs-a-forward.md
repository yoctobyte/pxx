---
summary: "FPC seed canary RED: rparser.inc calls RExprRecId at :1416, defined at :1754, no forward. pxx self-hosts fine (it does not require the forward); FPC does, so the cold-start bootstrap is broken. One-line fix, Track R's file."
type: regression
track: R
prio: 60
status: rejected
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

---

## ALREADY FIXED — this ticket was filed against a stale checkout. 2026-08-29.

**No action needed. The forward is on master and the canary is green.**

Measured at `e2104bf4d`: `python3 tools/forwardlint.py` → **exit 0, zero FAILs**,
and `compiler/rparser.inc:77` reads

```pascal
function RExprRecId(node: Integer): Integer; forward;
```

The forward landed in **`9d14b759d` at 19:13**, *"fix(rust): forward-declare
RExprRecId — the FPC bootstrap seed compiles again"*, verified two ways by
frank-rust at the time: `forwardlint` clean **and** a direct `fpc -Mobjfpc
compiler.pas` bootstrap linking, 210475 lines, 0 errors.

**The line numbers in this filing are the proof, and they are the general
lesson.** This ticket cites *used at `:1416`, defined at `:1754`* — which is
**exactly** the pre-fix geometry. Current HEAD is *used at `:1642`/`:1746`,
defined at `:2054`, forward at `:77`*. Those numbers cannot both describe the
same file, so the reported "clean HEAD" was a local HEAD behind origin.

The stash-and-rebuild was correct method and reproduced faithfully; **what it
reproduced was the state of the checkout, not the state of master.**

> **"I rebuilt at clean HEAD" answers *is my tree consistent*, not *is my tree
> current*.** A stash removes local edits; it does not fetch. Both readings are
> spelled "clean HEAD", and only one of them is evidence about master.

Sibling of the rule the same session coined hours earlier — *"the fix is in HEAD"
and "the fix is in the binary I just ran" are different claims* — with the
ambiguity moved one step earlier, from **which binary** to **which HEAD**.

**Before filing a bug about master, `git fetch` and name the sha you measured
at.** A sha in the filing makes this self-diagnosing; line numbers alone made it
take three commands.

Closed as already-fixed rather than deleted, so `750ddf4aa` resolves to
something. The genuine filings are
`bug-r-rexprrecid-breaks-the-fpc-bootstrap-seed` and
`bug-r-rparser-calls-rexprrecid-before-declaring-it-so-the-fpc-bootstrap-seed-does-not-compile`,
both in `done/`.

**The family observation in this ticket is correct and worth keeping:** this is
the *fourth* instance of the FPC-seed forward-declaration hazard, and
`done/bug-n-fpc-seed-drift-pywiden-needs-a-forward-in-pars…` is the NilPy one.
Same asymmetry every time — pxx resolves across the unit, FPC in source order, so
the entire mandatory loop including the self-host fixedpoint stays green and only
the canary sees it. That is precisely why `forwardlint` is now wired into
`gate.sh`, and why the canary caught this one before it reached master rather
than after.
