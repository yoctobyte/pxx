{ A FRESH dyn-array call result used as a Copy() or `+` operand must be released.

  `Copy(MkArr(i))` and `MkArr(i) + MkArr(i)` leaked the operand array — one whole
  array per call operand per evaluation, for `array of AnsiString` AND for
  `array of Integer`, so it was the HANDLE that had no owner, not the elements.
  A named variable in the same position was always clean, because the AN_IDENT
  arm beside each spill takes IR_LEA of the symbol's slot rather than the handle.

  Same ownership family as the eight pointer seams: a lowering hands a fresh
  managed value to a consumer that keeps a RAW POINTER. Three spills, all in
  ir.inc: AN_DYN_COPY's source, AN_DYN_INSERT's source, and AN_DYN_INSERT's
  array-SPLICE value (which is the one `a + b` goes through).

  Fixing it needed IRParkManagedDyn to hand back the handle with IR_LEA rather
  than IR_LOAD_SYM. IR_LOAD_SYM routes through EmitLoadVar, which takes its width
  from `Syms[].TypeKind` — and AllocDynArray stamps that with the ELEMENT kind,
  with no IsArray check anywhere on that path. So parking an `array of Integer`
  loaded its 8-byte handle as a 4-byte SIGN-EXTENDED value (measured: data
  pointer 0xffffffffe7e00020) and the release then read [data-8] off it and
  died. `array of AnsiString` survived only because a pointer-sized element kind
  makes the wrong width accidentally right — which is why the first attempt at
  this fix looked like "the park works for strings and segfaults for integers".
  64-bit only for the same reason: on i386/arm32/riscv32 a 4-byte load of a
  4-byte pointer is correct by accident.

  The integer rows below are therefore NOT decoration — they are the only rows
  that can see the truncation, and the named-variable rows are the control that
  says the park is skipped where a value already has an owner.

  Census, x86-64, at the fix: Copy rows 2004 live -> 6, concat rows 5006 -> 11.
  bug-a-a-fresh-array-result-has-no-owner-as-a-copy-or-concat-operand }
program test_dynarray_fresh_result_operand_leaks;
{$mode objfpc}{$H+}

var
  b, nv, nw: array of AnsiString;
  ib, iv: array of Integer;
  i, k: Integer;

function MkArr(kk: Integer): array of AnsiString;
begin
  SetLength(Result, 4);
  Result[0] := 'aa'; Result[1] := 'bb'; Result[2] := 'cc'; Result[3] := 'dd';
end;

function MkIA(kk: Integer): array of Integer;
begin
  SetLength(Result, 4);
  Result[0] := 11 + kk; Result[1] := 22; Result[2] := 33; Result[3] := 44;
end;

begin
  SetLength(nv, 2); nv[0] := 'n0'; nv[1] := 'n1';
  SetLength(nw, 2); nw[0] := 'w0'; nw[1] := 'w1';
  SetLength(iv, 2); iv[0] := 11; iv[1] := 44;

  { Copy over a fresh call result — both element kinds }
  for i := 1 to 500 do b := Copy(MkArr(i));
  for i := 1 to 500 do ib := Copy(MkIA(i));
  for i := 1 to 500 do ib := Copy(MkIA(i), 0, 2);

  { concat with a fresh call result on either side, and on both }
  for i := 1 to 500 do b := MkArr(i) + MkArr(i);
  for i := 1 to 500 do b := nv + MkArr(i);
  for i := 1 to 500 do b := MkArr(i) + nv;
  for i := 1 to 500 do ib := MkIA(i) + MkIA(i);

  { CONTROLS: named operands own themselves already, so the park must skip them
    and these must stay correct (they were never the leak) }
  for i := 1 to 500 do b := Copy(nv);
  for i := 1 to 500 do b := nv + nw;
  for i := 1 to 500 do ib := iv + iv;

  k := 0;
  for i := 0 to Length(ib) - 1 do k := k + ib[i];
  WriteLn('b=', Length(b), ' b0=', b[0], ' ib=', Length(ib), ' ibsum=', k);
  WriteLn('DYNFRESHOPERAND OK');
end.
