{ %FAIL-style negative: the type check must reach every LVALUE SHAPE, not just
  a bare identifier.

  `r := s` (a string into a record) was refused. `rs[1] := s` was not — it
  compiled to a byte move of a string HANDLE over the record's first field and
  segfaulted at scope exit, releasing a handle that was never one. Five of the
  six lvalue shapes were unchecked: fpc 3.2.2 rejects all six, pxx rejected one.

  The cause was not a check that fired and passed. `AssignSideKind` (ir.inc)
  answered only AN_IDENT and literals, so for an element, a field or a deref it
  returned False, the `and` chain short-circuited, and the check NEVER RAN. The
  funnel at AN_ASSIGN was real; the typing of the destination was not.

  Row 1 is here on purpose and must stay: it is the shape that already worked,
  and it is what proves a fix to the other five did not break it.

  ONE program, because the check reports and carries on — the Makefile row
  asserts the COUNT, which is also what proves the recovery works. Its sibling
  test_assign_lvalue_shapes_ok.pas is the other half: everything this check must
  NOT start refusing, because a fix that turns a false accept into a false
  reject is a regression that looks like progress.

  DELIBERATELY ABSENT: `var`/`out` parameters. A by-ref slot holds an ADDRESS,
  which is a separate question gated by AssignSideKind's own IsRef bail — it
  does not fall out of this fix and a gate expecting it would over-claim.
  bug-p-a-string-assigned-to-a-record-ARRAY-ELEMENT-is-not-type-checked }
program test_assign_lvalue_shapes_fail;
{$mode objfpc}{$H+}
type
  TRec  = record S: AnsiString; N: Integer; end;
  PRec  = ^TRec;
  TRecs = array of TRec;
  TFix  = array[0..1] of TRec;
  TOuter= record Inner: TRec; end;
  TCls  = class F: TRec; N: Integer; S: AnsiString; end;
  PInt  = ^Integer;
var rs: TRecs; fx: TFix; r: TRec; o: TOuter; c: TCls; p: PRec; pi: PInt;
    s: AnsiString; i: Integer;
begin
  SetLength(rs, 2);
  c := TCls.Create;
  New(p); New(pi);
  { the six shapes of "a string into a record" — fpc rejects every one }
  r       := s;   { 1  plain identifier — the arm that already worked }
  rs[1]   := s;   { 2  dynamic-array element }
  fx[0]   := s;   { 3  fixed-array element }
  o.Inner := s;   { 4  record field }
  c.F     := s;   { 5  class field }
  p^      := s;   { 6  pointer deref }
  { and the mirror direction, plus the scalar/handle confusions on the same
    shapes: a field or an element is not a special case of anything }
  s       := rs[0];  { 7  record into a string }
  c.N     := s;      { 8  handle into an Integer field }
  s       := c.N;    { 9  Integer field into a string }
  c.S     := i;      { 10 number stored as a string handle }
  pi^     := s;      { 11 handle through a deref }
  rs[0].N := s;      { 12 field OF an element — the nested shape }
  WriteLn(i, s);
end.
