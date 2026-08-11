---
track: A
prio: 45
type: bug
blocked-by: []
status: done
owner: claude-A
---

# A fixed-array call result is refused as a `const`/by-ref argument

- **Type:** bug (spurious refusal) — **Track A**
- **Found:** 2026-08-11, while verifying
  [[bug-a-fixed-array-function-result-faults-on-i386-and-arm32]]. The array arm
  is the only aggregate that refuses; the record and string arms already
  materialise a temp.

```pascal
{$mode objfpc}
type TArr = array[0..2] of Integer;
     TR   = record x, y: Integer; end;
function MkArr: TArr;  begin MkArr[0]:=1; MkArr[1]:=2; MkArr[2]:=3; end;
function MkR:   TR;    begin MkR.x:=4; MkR.y:=5; end;
function MkS:   string; begin MkS := 'abcd'; end;
function SumA(const a: TArr): Integer;  begin SumA := a[0]+a[1]+a[2]; end;
function SumR(const r: TR): Integer;    begin SumR := r.x+r.y; end;
function Twice(const s: string): Integer; begin Twice := Length(s)*2; end;
begin
  WriteLn(SumR(MkR));    { pxx 9  = FPC 9  }
  WriteLn(Twice(MkS));   { pxx 8  = FPC 8  }
  WriteLn(SumA(MkArr));  { FPC 6; pxx REFUSES }
end.
```

```
pascal26: error: by-reference argument must be a variable
```

FPC prints `9 8 6`.

## Where to start (not yet diagnosed)

`bug-const-byref-record-param-temp` (done) is the record half of exactly this:
a call result passed to a `const` record parameter materialises into a caller
temp whose address is passed. The array arm of the by-ref argument check never
learned the same trick, so it still demands an lvalue.

`ProcRetFixedArrBytes` + `ABIRetViaHiddenDestProc` already give the caller a
right-sized scratch for `a := MkArr` on all five targets (verified 2026-08-11),
so the temp this needs is the one the assignment path already allocates — the
missing piece is likely only the argument-side lvalue check and routing the
hidden destination at a call ARGUMENT rather than an assignment RHS.

Sibling worth checking in the same pass: a `var` (not `const`) parameter must
keep refusing a call result — FPC refuses that too, so the fix must not widen
the check for both.

## Gate

The program above matching `fpc -O1` on x86-64 and all four cross targets;
a `var`-parameter call-result argument still refused; self-host byte-identical.

## Resolution (2026-08-11)

The by-ref argument check learned the array arm the record arm already had: an
`AN_CALL` whose proc has `ProcRetFixedArrBytes > 0` is a valid non-lvalue for a
`const` (or plain by-value) parameter, because the callee returns into a
caller-owned scratch and there is nothing to write back. A genuine `var`/`out`
array parameter still demands an lvalue — FPC refuses a call result there too,
and `Bump(MkArr)` with `var a: TArr` is still an error here.

**TWO sites, both needed it** — the plain call path and the OVERLOADED call
path carry independent copies of the same allow-list (the overloaded one also
still lacks the promo-int arm the other has). Fixing only the first left
`Sum(MkArr)` refused whenever `Sum` was overloaded.

Diffed against `fpc -O1`, matching on x86-64 / i386 / arm32 / aarch64 /
riscv32: `const` and by-value array parameters, a 3-byte `array of Byte`, two
such calls in one expression, and the extended
`test/test_aggregate_function_results.pas` (`arr as arg` row).

Found while verifying, filed separately: `Sum(7)` binds the fixed-ARRAY
overload rather than the Integer one, because a fixed-array parameter's
`Params[].TypeKind` is its ELEMENT kind — `bug-a-an-integer-argument-binds-a-fixed-array-overload`
(pre-existing on `pinned`).

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
