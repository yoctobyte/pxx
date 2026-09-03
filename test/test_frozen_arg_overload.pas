program test_frozen_arg_overload;
{ A FROZEN-STRING ARGUMENT REACHING OVERLOAD RESOLUTION, in the spellings that
  do NOT normalise to tyString on the way. Compiled both ways, same output.

  Under -dPXX_SHORTSTRING, `Show(r.f)` against `Show(const a: AnsiString)` was
  REFUSED -- "no overload of Show matches these arguments / argument types:
  (ShortString)" -- on all seven targets, while `Show(s)` on a plain variable
  of the same type was accepted IN THE SAME PROGRAM. A bare variable read
  normalises to tyString via StrValTk at the AST; a record field, an array
  element and a function result all keep the narrow kind, and every string rule
  in TypesCompatible named tyString.

  This was the only byte-prefix defect that was a COMPILE-TIME REFUSAL on every
  target rather than a wrong value on one or two, so it blocked the phase-4
  flip everywhere.
  bug-a-a-frozen-record-field-is-refused-by-overload-resolution-against-an-ansistring-parameter

  THE ROWS ARE THE SPELLINGS, and they are not interchangeable -- each reaches
  the argument kind by a different route, so a fix at one node type would leave
  the others:

    plain    a bare variable. The row that was ALWAYS correct, and the reason
             the bug reads as "overload resolution is broken" rather than "one
             spelling is": without it the diff has no control.
    field    a record field. The reported shape.
    nested   a field of a field, so the aggregate walk is two deep.
    elem     an array element with a CONSTANT index, which folds differently
             from
    elemvar  an array element with a VARIABLE index.
    ret      a function RESULT typed string[10]. A call node carries
             Procs[].RetType -- the STORAGE kind -- at some 50 sites, so this
             one arrives narrow from a third direction.
    pick     TWO candidates, `ShowI(Integer)` and `ShowI(AnsiString)`, and a
             frozen field argument. It must CHOOSE the string one. This is the
             row that a compatibility-only fix passes while still ranking the
             field below a plain variable: OverloadArgRank gave the variable
             rank 1 (preferred conversion) and the field rank 2 (merely
             compatible), and a ranking asymmetry between two spellings of one
             type is how `P(r.f)` and `P(s)` bind to different overloads.
    int      the same pair called with an actual Integer, so `pick` cannot pass
             by the string arm having swallowed everything. }
type
  Inner = record g: string[10]; end;
  R = record f: string[10]; n: Inner; end;
  TArr = array[0..2] of string[10];

procedure Show(const a: AnsiString);
begin
  WriteLn('A[', a, ']');
end;

procedure ShowI(const a: Integer);
begin
  WriteLn('I[', a, ']');
end;

procedure ShowI(const a: AnsiString);
begin
  WriteLn('AI[', a, ']');
end;

function Mk: string[10];
begin
  Mk := 'ret';
end;

var
  r: R;
  a: TArr;
  s: string[10];
  i: Integer;
begin
  r.f := 'field'; r.n.g := 'nested'; a[1] := 'elem'; s := 'plain'; i := 1;

  Write('plain   '); Show(s);
  Write('field   '); Show(r.f);
  Write('nested  '); Show(r.n.g);
  Write('elem    '); Show(a[1]);
  Write('elemvar '); Show(a[i]);
  Write('ret     '); Show(Mk);
  Write('pick    '); ShowI(r.f);
  Write('int     '); ShowI(7);
end.
