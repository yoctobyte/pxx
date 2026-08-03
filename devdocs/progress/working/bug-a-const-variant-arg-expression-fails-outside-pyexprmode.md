---
track: A
prio: 30
type: bug
blocked-by: []
status: working
owner: claude-AC
---

# `obj.method(a + b)` to a `const Variant` param fails to parse OUTSIDE NilPy

`bug-nilpy-expression-arg-to-a-const-param` (already fixed, see the comment on
`ByRefArgStartsExpression` in `compiler/parser.inc:3552`) fixed `xs.append(a +
b)` for NilPy source — a `const Variant` parameter is by-ref internally (boxed
at `IRLowerCallArg`), so the by-ref argument parser tried to bind the argument
as a bare lvalue and choked on the operator after the first identifier. The fix
is gated `if PyExprMode then ... end;` inside `ByRefArgStartsExpression`.

That gate means the identical shape still fails in **plain Pascal source**
(`PyExprMode = False`), including a Pascal RTL unit's OWN body — found writing
`pylib.pas` itself:

```pascal
function pyenumerate2(a: TPyList; start: Integer): TPyList;
var r, pair: TPyList; i: Integer; pv: Variant;
begin
  ...
  pair.append(start + i);   { TPyList.append(const v: Variant) }
  ...
```

fails with:
```
pascal26:NNNN: error: unexpected token
  near:  pair  append  start >>>  i
```
(`Expected: ), but got: tkPlus` — the same shape as the original NilPy bug, one
level down: worked around locally by assigning `start + i` to a local variable
first before the `.append()` call, but the underlying parser gap is general.

## Root cause

`ByRefArgStartsExpression` (`compiler/parser.inc:3552`) only runs its
lvalue-chain-skip-then-check-what-follows logic (the actual fix) when
`PyExprMode` is true. Outside that mode it falls through to the old rule:
`Result := (FindSym(CurTok.SVal) < 0) and ... tkLParen` — true only for an
unresolved-identifier-followed-by-`(` (a cast-lvalue like `PChar(s)^`), false
for a plain declared variable, so `start` (a real local) reads as "starts a
bare lvalue" and the by-ref arg parser stops after consuming just `start`.

## Fix direction

The PyExprMode gate exists to protect genuine Pascal `var`/`out` parameter
binding (which really does need a true lvalue, in both Pascal and NilPy). But
a `const Variant` parameter is NEVER a genuine var-binding target — the
existing by-ref-argument-validator two call sites up
(`(Params[i].TypeKind = tyVariant) and ProcParamIsConst[...]`) already treats
it as accepting a non-lvalue temporary. So `ByRefArgStartsExpression` should
run its lvalue-chain-skip-and-check logic unconditionally whenever the current
parameter is `const Variant`, regardless of `PyExprMode` — only genuine
var/out/array by-ref params should still require the gate.

This needs threading the callee's "is this a const Variant param" fact into
`ByRefArgStartsExpression` (it currently takes no arguments) at each of its ~8
call sites in `compiler/parser.inc` (plain calls, method calls, interface
calls — grep `ByRefArgStartsExpression`), each of which already has `mpi`/
`mslot` or `procIdx`/`i` in scope to compute
`(Procs[..].Params[..].TypeKind = tyVariant) and ProcParamIsConst[...]`.
Scoped as its own ticket since it touches the shared Pascal/NilPy binop/call
parsing in `parser.inc` at several sites and needs the self-host gate;
deliberately not attempted inline while sweeping for the set/dict-operator fix
(bug-nilpy-set-and-dict-operators-do-raw-pointer-arithmetic).

## 2026-08-01 — attempted, REVERTED: broke promotable-int/bignum output

Picked up as claude-A. Both halves of the fix direction above were
implemented and landed (commit `b93577cd3`): the `isConstVariantParam`
threading through all 8 `ByRefArgStartsExpression` call sites, AND a
second, deeper bug found by tracing (not guessing) why `ProcParamIsConst`
still read False for `TPyList.append`'s own `const v: Variant` even
after the threading fix — a parameter-array SHIFT in `ParseSubroutine`
(making room for the implicit `Self` at index 0 in a method
IMPLEMENTATION header) was missing `pconst` from its shift list
entirely, in BOTH of the two shift blocks that exist there. Every other
per-param array (`ptypes`, `parr`, `pbyref`, `pNDims`, `pDynDepth`, the
default-value arrays, ...) shifted correctly; `pconst` did not, so a
method's real `const` parameter ended up written into Self's
(meaningless) slot while the parameter's own slot read stale/default
data. This is a GENERAL bug, not Variant-specific — any method
implementation with a `const` parameter had `ProcParamIsConst`
misregistered.

**The ticket's own ~8-call-site repro was verified working** (both the
Pascal `pair.append(start + i)` shape and the original NilPy shape),
self-host fixedpoint reached (generation 2, expected for a change this
broad), and a spot-check across const/overload/keyword-arg-heavy tests
passed. **But `make stabilize`'s full `test-core` run caught what the
spot-check missed**: `test/test_promoint.pas` (promotable-int / arbitrary-
precision bignum arithmetic) started printing garbage — huge strings of
leading zeros padded in front of otherwise-correct bignum values, and
one comparison result flipped from `1` to `0`. Confirmed the fix was the
cause (not a pre-existing issue) by running the SAME test against the
previously-pinned binary (v238, predates this fix): correct output,
`1`. The fix's own binary: wrong.

**Reverted** (commits `f975e3fa7`, `447ad4c4c`) rather than debugged
further in the moment — this was caught close to a `make stabilize` run
that ran unattended for over an hour, and shipping ANY unverified state
to the pinned binary is worse than losing this fix for a night. The
`pconst`-shift fix almost certainly UNMASKS a second, pre-existing bug
elsewhere (a downstream consumer of `ProcParamIsConst` — likely
somewhere in the promotable-int/bignum value-copy or string-conversion
path — that was implicitly relying on `const record`/`const Variant`
parameters reading as non-const, and now that they correctly read as
const, marshals/copies them differently and wrong). That second bug is
real and needs finding before this ticket can land safely; the
`pconst`-shift fix by itself is very likely correct (it matches the
exact pattern the sibling `ProcParamHasDefault` comment two lines below
already documents needing) but its downstream blast radius is larger
than initially scoped and needs the SAME kind of careful measurement
this session used to find it in the first place — starting from
`test_promoint.pas`'s own wrong output, not from theorizing about which
call site is affected.

**Do not re-attempt without gating on a full `make stabilize`/
`testmgr --tier full`-equivalent run before promoting the seed** — the
regression here was invisible to self-host fixedpoint, a handful of
targeted spot-checks, and even a broad-ish sweep of const/overload
tests; it only surfaced in the full test-core suite, on a test file with
no obvious connection to `const` parameter handling at the source level.

## 2026-08-03 — RE-ATTEMPTED, and the 2026-08-01 regression does NOT reproduce

Re-attempted under the discipline the note above demands: apply the two halves
**separately**, diff each against a known-good binary, and gate on a full tier
before claiming anything.

### Half 1 — the `pconst` shift — is clean on its own

Applied alone (both shift blocks in `ParseSubroutine`, plus the `pconst[0] :=
False` that the other per-param arrays already set explicitly for the injected
`Self`/`__genself` slot). Then:

```
stable_linux_amd64/default/pinned  test/test_promoint.pas  -> /tmp/promoint.pin
HEAD + pconst shift only           test/test_promoint.pas  -> /tmp/promoint.new
diff  =>  IDENTICAL
```

So the pconst shift by itself does not touch promotable-int/bignum output. The
2026-08-01 session landed both halves together and could not have seen this
split.

### Half 2 — the `ByRefArgStartsExpression` threading — is also clean

`ByRefArgStartsExpression` now takes `constVariantParam`, computed at each of
the 8 call sites (plus `False` at the `Inc`/`Dec` intrinsic site) through a
small `ParamIsConstVariant(pi, slot)` helper; the lvalue-chain-skip logic runs
when `PyExprMode OR constVariantParam`. With both halves in:

```
diff /tmp/promoint.pin /tmp/promoint.new2  =>  IDENTICAL
```

**The regression the last attempt hit does not reproduce at HEAD.** The honest
reading: that attempt's diagnosis — the pconst fix UNMASKS a second, pre-existing
downstream bug — was probably right, and that second bug has since been fixed by
other work (a great deal has landed since 2026-08-01, including the const-Variant
revert itself, the TypeRef migration and the promo-int follow-ups). It is not
that the earlier session was wrong; it is that the ground moved.

### Repros, both directions

```pascal
b.Take(start + i);        { const v: Variant — the ticket's own shape }
b.Take(start * 2 + 1);
b.Take(start);            { a bare variable must still bind — it does }
```
prints `15 / 21 / 10`, and the original NilPy shape `xs.append(a + b)` still
prints `[7, 3]`. Genuine `var`/`out`/array by-ref parameters keep the
`PyExprMode` gate, so Pascal's real var-binding is untouched.

### Gate

Per this ticket's own standing instruction — *"do not re-attempt without gating
on a full `make stabilize`/`testmgr --tier full`-equivalent run"*, whose reason
is recorded above (the 2026-08-01 regression was invisible to the self-host
fixedpoint, targeted spot-checks and a broad const/overload sweep) — this landed
on `tools/testmgr.py --tier full`, not the usual quick gate.
