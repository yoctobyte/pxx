program test_parenless_call_of_any_procedural_designator;
{ A parameterless procedural value called with NO argument list, for every
  designator spelling -- not just a bare identifier.

  `m;` worked and `h.nul;`, `h.p;` and `a[0];` all reported
  `expected ':=' before ';'`, because the decision was made BEFORE the lvalue
  was parsed and only for a single identifier. The boundary was neither
  `of object` nor the record field -- removing each showed it was neither -- it
  was the spelling of the designator. FPC accepts every row here, and real
  Pascal writes `OnClick;` far more often than `OnClick()`.

  The parenthesised rows are the positive control in the other direction: they
  worked before and must keep working, so a fix that made the parenless form a
  call by breaking the call form fails here.

  Oracle: fpc 3.2.2 -Mdelphi -O1, byte-identical output.
  bug-p-a-parameterless-procedural-value-is-only-callable-bare-as-an-identifier }
{$mode delphi}
type
  TSel = procedure of object;
  TPl  = procedure;
  TH = record nul: TSel; p: TPl; end;
  TSvc = class procedure Pick; end;
procedure TSvc.Pick; begin writeln('picked'); end;
procedure Plain;     begin writeln('plain');  end;
var
  h: TH;
  a: array[0..0] of TSel;
  b: array[0..0] of TPl;
  m: TSel; s: TSvc;
begin
  s := TSvc.Create;
  m := s.Pick;
  h.nul := m;  h.p := @Plain;
  a[0] := m;   b[0] := @Plain;

  m;          { bare identifier, method pointer -- the row that always worked }
  m();        { …and its parenthesised control }
  h.nul();    { record FIELD, parenthesised control }
  h.nul;      { record FIELD, method pointer }
  h.p;        { record FIELD, plain procedure -- not about `of object` }
  a[0];       { ARRAY element, method pointer -- not about record fields }
  b[0];       { ARRAY element, plain procedure }
end.
