---
track: A
prio: 45
type: bug
summary: "A Pascal function RETURNING PromoInt crashes — `function mk: PromoInt; begin Result := 12 end` segfaults on writeln(mk). Confirmed on `pinned` too, so pre-existing; split out of the parameter ticket, which conflated the two"
status: done
owner: claude-A
---

# A function returning `PromoInt` crashes

```pascal
program t;
function mk: PromoInt;
begin Result := 12; end;
begin
  writeln(mk);     { SEGFAULT }
end.
```

Confirmed on `stable_linux_amd64/default/pinned` as well as at HEAD, so it is
**pre-existing** and not a consequence of
[[bug-a-promoint-parameter-cannot-be-used-at-all]] (now fixed).

## Why it is filed separately

That ticket's third repro was

```pascal
function viaOp(n: PromoInt): PromoInt; begin Result := n + 0; end;
```

which mixes a promo PARAMETER with a promo RESULT. The parameter half is fixed
and verified; this one still crashes, and the repro above shows it needs no
parameter at all. Two bugs in one line is how the parameter ticket ended up
describing the symptom as "even `n + 0` segfaults" when the addition was fine.

## Likely shape — NOT verified, do not trust this paragraph

A promo rvalue is the slot ADDRESS ([[decide-promoint-rvalue-representation]]),
and `Result` is a slot in the callee's frame, which dies at return — so the
caller would receive an address into a dead frame. That is exactly the hazard
the NilPy side documents and side-steps by boxing a promo return to a VARIANT
(`if TypeIsPromoInt(cur) then cur := tyVariant` in the return-type inference),
and Pascal has no such boxing.

Measure before acting: dump the callee's epilogue and the caller's use with
`PXXDBG=a.ir:<proc>`, exactly as the parameter bug was settled.

## Fix shape

The parameter fix is the precedent worth copying: a `PromoInt` is an AGGREGATE
(TypeSize 16), and this compiler already has ONE convention for returning one —
whatever large records do. Check that first (a record result almost certainly
travels through a caller-provided hidden destination, the NRVO-style slot), and
join `PromoInt` to it rather than inventing a promo-specific return path. If it
is the hidden-destination shape, the callee writes the result into the caller's
slot and the dead-frame problem disappears.

Note [[project_frozen_string_result_nrvo_blocker]] and
[[project_variant_fn_return_forward_nrvo_corruption]] before designing: result
slots have bitten this compiler twice before, both times as corruption rather
than a crash.

## Gate

`make test` + self-host byte-identical, plus a Pascal test returning a promo at
BOTH tiers (inline and heap — only the heap tier has a managed payload, so only
it can double-free), a result used directly as an argument, and a result
assigned to a caller variable that is then mutated.

## Resolution (2026-08-05)

`RetViaHiddenDest` lists the return types whose ABI is a caller-owned
destination — aggregates, frozen strings, `tyVariant`. **The promotable-int
family was never added**, though a promo value is a `{tag, payload}` struct
whose rvalue IS the slot address. So a promo-returning function handed back the
address of its own dying `Result` local and the caller read freed stack.

One term: `or TypeIsPromoInt(tk)`. `AggRetCopySize` already falls through to
`TypeSize`, which is the right byte count for both widths, so nothing else
needed changing.

### What made it obvious

    function mk: PromoInt; begin end;   { EMPTY body }
    writeln(mk);                        { still segfaults }
    mk;                                 { result discarded — fine }

An empty body still crashing rules out `Result := 12` entirely, and discarding
the result being fine rules out the call. That leaves the result TRANSFER, which
is one predicate. The ticket's own guess was flagged "NOT verified, do not trust
this paragraph" — right instinct: it reasoned about the rvalue representation,
and the gap was in the ABI predicate.

### Verified

Inline tier (12), **heap tier** (10^40, byte-identical to Python's `10**40` —
the tier boundary is where a naive fix would break), promo parameter + promo
result together, the result used as an operand (`p + 1` = 13), and 500 doubling
iterations to surface a use-after-free. All six existing `test_promoint*` suites
still run. 200 000 calls stay flat at 264 KB, so no leak.
`testmgr --tier native` **1162/1162 pass**. Locked in as
`test/test_promoint_function_result.pas`.

### Adjacent, NOT fixed here

`viaOp(12)` is rejected — an integer literal does not convert to a promo
parameter — and `viaOp(mk)` is rejected because promo parameters are by-ref and
need a variable. Both are real and both are separate from this bug, so they are
left visible rather than folded into an unrelated commit.

## Log
- 2026-08-05 — resolved, commit b611d51b3.
