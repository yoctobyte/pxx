---
track: A
prio: 45
type: bug
summary: "A Pascal function RETURNING PromoInt crashes — `function mk: PromoInt; begin Result := 12 end` segfaults on writeln(mk). Confirmed on `pinned` too, so pre-existing; split out of the parameter ticket, which conflated the two"
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
