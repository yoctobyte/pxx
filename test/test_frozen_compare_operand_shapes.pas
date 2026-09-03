{ EVERY SPELLING OF A FROZEN STRING ON EITHER SIDE OF A COMPARISON, plus the
  pointer comparisons that must NOT become one.

  WHY THIS FILE EXISTS. wasm32 decided "is this binop a string operation?" from
  the type of the VALUE each operand produces, and a frozen string's value IS an
  address -- so two `string[8]` variables looked like two pointers and `a = b`
  compiled to an i32.eq of two ADDRESSES. Every other backend was correct, and
  the bug survived a ticket, a diagnosis and a sweep because of what it does to
  the rows a probe naturally writes:

    a = b        FALSE for two equal strings          <- the defect
    a = a        TRUE, because the addresses ARE equal
    a < b        TRUE for two EQUAL strings, because one address is lower
    p^ = a       TRUE when p happens to point AT a    <- the repro trap
    a = 'lit'    TRUE, because a literal operand is tagged tyString and the
                 predicate's OR fired on the other side

  So THE FAILURE VALUE IS NOT CONSTANT: a suite of must-be-TRUE rows catches
  some of it, a suite of must-be-FALSE rows catches the rest, and a repro that
  points p at the variable it compares against catches none of it. Every row
  below is paired with its opposite for that reason.

  NO ROW MAY COMPARE AGAINST A LITERAL ONLY. A literal is correct through every
  route on every backend, so a literal-based file passes with the bug present.
  `var_lit` is here as the control that stayed green, not as coverage.

  THE POINTER ROWS ARE THE OTHER HALF OF THE GUARD. `@a = @b`, `@a = @a` and
  `p = q` are ADDRESS comparisons in Pascal and must stay that way -- the fix
  reads the IR's tag on the operand node (`a` is tagged tyString, `@a` tyPointer
  over the same symbol) precisely so widening the string predicate cannot turn
  `@a = @b` into a comparison of characters. A fix that reads the SYMBOL instead
  passes every string row above and breaks these three.

  SetLength is at the end because it is the writer in the same family: it was a
  hard `unreachable` on wasm32 and a compile error on riscv32 and xtensa, three
  backends missing the same builtin arm.

  Rows are RELATIONS and carry no per-target constant, so the expected text is
  one file for every target and both prefix widths.
  bug-a-wasm32-shortstring-comparison-is-wrong-at-every-length
  bug-a-wasm32-setlength-on-a-shortstring-traps }
program test_frozen_compare_operand_shapes;

type
  TS = string[8];
  TRec = record f: TS; end;

var
  a, b, c: TS;
  r, r2: TRec;
  arr: array[0..1] of TS;
  p, q: ^TS;
  m: AnsiString;
  l: TS;

procedure ByVal(v: TS);
begin
  SetLength(v, 2);
  WriteLn('sl byval  ', Length(v), ' [', v, ']');
end;

procedure ByRef(var v: TS);
begin
  SetLength(v, 2);
  WriteLn('sl byref  ', Length(v), ' [', v, ']');
end;

begin
  a := 'abcde';
  b := 'abcde';          { equal to a, and a DIFFERENT buffer }
  c := 'zz';             { unequal to a, and shorter }
  r.f := 'abcde'; r2.f := 'abcde';
  arr[0] := 'abcde'; arr[1] := 'abcde';
  p := @a; q := @b;      { two pointers at two DIFFERENT buffers }
  m := 'abcde';

  { ---- the same characters through every spelling, each with its negative ---- }
  WriteLn('var_var   ', a = b,       ' ', a = c);
  WriteLn('fld_fld   ', r.f = r2.f,  ' ', r.f = c);
  WriteLn('fld_var   ', r.f = a,     ' ', r.f = c);
  WriteLn('elm_elm   ', arr[0] = arr[1], ' ', arr[0] = c);
  WriteLn('elm_var   ', arr[0] = a,  ' ', arr[0] = c);
  WriteLn('drf_drf   ', p^ = q^,     ' ', p^ = c);
  WriteLn('drf_var   ', p^ = b,      ' ', p^ = c);
  WriteLn('var_ans   ', a = m,       ' ', c = m);
  WriteLn('var_lit   ', a = 'abcde', ' ', a = 'zz');
  WriteLn('self      ', a = a,       ' ', a = c);

  { ---- ORDERING, which equality cannot stand in for: both operands are read
    at the same width, so `=` survives a wrong prefix width and `<` does not.
    a and b are EQUAL, so `a < b` is FALSE and an address compare says TRUE. ---- }
  WriteLn('ord       ', a < b, ' ', c < a, ' ', a < c);

  { ---- POINTER comparisons, which must NOT be string comparisons ---- }
  WriteLn('addr      ', @a = @b, ' ', @a = @a);
  WriteLn('ptr       ', p = q,   ' ', p = p);

  { ---- the writer in the same family ---- }
  l := 'hello';
  SetLength(l, 3);
  WriteLn('sl local  ', Length(l), ' [', l, ']');
  l := 'hello';
  ByVal(l);
  WriteLn('sl after  ', Length(l), ' [', l, ']');
  ByRef(l);
  WriteLn('sl afterr ', Length(l), ' [', l, ']');
  SetLength(l, 0);
  WriteLn('sl zero   ', Length(l), ' [', l, ']');
end.
