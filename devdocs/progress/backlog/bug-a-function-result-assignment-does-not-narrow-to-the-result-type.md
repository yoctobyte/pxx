---
slug: bug-a-function-result-assignment-does-not-narrow-to-the-result-type
title: "Assigning a wider value to a function RESULT does not narrow it — the variable arm of the same assignment does"
track: A
prio: 40
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-08-28
summary: "`function F(a: Int64): Integer; begin F := a; end` returns the full 64-bit value: F(4294967299) prints 4294967299 where FPC prints 3. The same assignment to a variable, to a var parameter, or through a cast all narrow correctly. One arm of a double case, and the broken arm is the one with no diagnostic — the caller reads a value the declared result type cannot hold."
---

# Repro

```pascal
program NarrowShapes;
function ByName(a: Int64): Integer;   begin ByName := a;          end;
function ByResult(a: Int64): Integer; begin Result := a;          end;
function ViaLocal(a: Int64): Integer; var t: Integer;
                                      begin t := a; ViaLocal := t; end;
function ByCast(a: Int64): Integer;   begin ByCast := Integer(a);  end;
function SmallRes(a: Int64): SmallInt; begin SmallRes := a;        end;
procedure ToVarParam(a: Int64; var o: Integer); begin o := a;      end;
var v: Integer;
begin
  writeln(ByName(4294967299));
  writeln(ByResult(4294967299));
  writeln(ViaLocal(4294967299));
  writeln(ByCast(4294967299));
  writeln(SmallRes(4294967299));
  ToVarParam(4294967299, v); writeln(v);
end.
```

| shape | fpc 3.2.2 | pxx x86-64 |
| --- | --- | --- |
| `ByName := a` (result by name) | 3 | **4294967299** |
| `Result := a` | 3 | **4294967299** |
| via an Integer local | 3 | 3 |
| `Integer(a)` cast | 3 | 3 |
| `SmallRes := a` (SmallInt result) | 3 | **4294967299** |
| `o := a` (var parameter) | 3 | 3 |

Both compilers on the same file; FPC run with `-Mobjfpc`. Three of six wrong,
and the three are exactly the assignments whose target is the function result.

# Why this is a bug and not dialect laxness

CLAUDE.md's compat table: *"real Pascal source compiles but runs wrong"* → bug,
via the silent-wrong-behaviour escape. The caller of `ByName` has been handed a
value its declared `Integer` type cannot represent; every subsequent use of it
is operating on something the type system says is impossible. Nothing warns.

# Shape

This is the double case `devdocs/dev/normalise-dont-special-case.md` describes:
one concept — "store a value into a typed destination" — reachable through two
paths, and the second path is the one that stays broken. The four working
shapes narrow; the result shape does not.

A hypothesis worth one measurement before designing the fix, NOT a claim: the
four working shapes all end in a store to a slot allocated at the destination's
own `TypeSize`, and on x86-64 a 4-byte store *is* the truncation — nothing has
to insert it. If the result slot is allocated pointer-width and the return
reads it whole, the narrowing that the other arms get for free never happens.
That would make it a slot-width question rather than a missing conversion node,
and would also predict `SmallRes` failing, which it does. Confirm before
fixing; `PXXDBG=n.locals` prints what was inferred.

# Found

By the wasm32 backend (branch `wasm`), 2026-08-28. It is the second finding of
its kind from that lane and for the same structural reason: wasm distinguishes a
value's type from its memory width at the instruction level, so the backend must
emit an explicit `i32.wrap_i64` where x86-64 picks a sub-register, and getting
that right made it disagree with the native build. The wasm side and FPC agree;
the native build is the odd one out.

Blast radius beyond the lane: the wasm Phase 2 differential
(`test/wasm/phase2_slice.pas`) has to keep its `Narrow` case inside Integer
range to avoid going red for this, so a real conversion path is currently
covered only for values where the bug is invisible. That constraint lifts when
this closes.
