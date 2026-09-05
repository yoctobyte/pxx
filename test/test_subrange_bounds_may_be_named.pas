program test_subrange_bounds_may_be_named;
{ A subrange's bounds do not have to be LITERALS. Both type-level subrange arms
  keyed on a token kind -- tkInteger, tkMinus, tkString -- so a bound that was a
  NAME fell through to the "is this a type name" arm and was reported as
  `unknown type: sat`. Seven spellings, one rule, every one of them accepted by
  fpc 3.2.2.

  The literal rows are REGRESSION CONTROLS: they worked before and must keep
  their exact storage, because the fix routes them through the shared body. A
  row that only exercised the new shape could not tell "named bounds now work"
  from "named bounds work and 1..10 quietly became four bytes".

  SizeOf is asserted only where it is a function of the VALUE RANGE, which is
  the same on every target -- it is not a pointer or alignment width. }

type
  D = (mon, tue, wed, thu, fri, sat, sun);

const
  Lo = 1;
  Hi = 9;

type
  { literal bounds — the controls }
  TInt   = 1..10;
  TChar  = 'a'..'z';
  { named bounds — the rows under test }
  TEnumR = sat..sun;
  TConstR = Lo..Hi;
  TBoolR = False..True;
  TSetE  = set of sat..sun;
  TSetC  = set of Lo..Hi;
  TRec   = record f: sat..sun; end;

function GiveSun: TEnumR;
begin
  GiveSun := sun;
end;

{ NAMED, not `d: mon..wed`: an INLINE subrange as a parameter type is rejected
  by fpc 3.2.2 (`Type identifier expected`) and accepted here. Us taking what
  fpc refuses is not a defect, but it cannot go in a byte-compared row. }
type TWork = mon..wed;

procedure Classify(d: TWork);
begin
  case d of
    mon: WriteLn('case mon');
    tue: WriteLn('case tue');
  else
    WriteLn('case other');
  end;
end;

var
  i: TInt; c: TChar; e: TEnumR; k: TConstR; b: TBoolR;
  se: TSetE; sc: TSetC; r: TRec; inl: sat..sun;
begin
  i := 5;    WriteLn('int    ', i, ' ', SizeOf(i));
  c := 'q';  WriteLn('char   ', c, ' ', SizeOf(c));
  e := sat;  WriteLn('enum   ', Ord(e));
  k := 5;    WriteLn('const  ', k, ' ', SizeOf(k));
  b := True; WriteLn('bool   ', b, ' ', SizeOf(b));
  se := [sat];  WriteLn('set-e  ', sat in se, ' ', sun in se);
  sc := [5];    WriteLn('set-c  ', 5 in sc, ' ', 9 in sc);
  r.f := sun;   WriteLn('field  ', Ord(r.f));
  inl := sat;   WriteLn('inline ', Ord(inl), ' ', inl);
  WriteLn('result ', Ord(GiveSun));
  Classify(tue);
  Classify(wed);
  { Low/High answer the SUBRANGE, not the base type — the bounds are retained
    rather than folded away. }
  WriteLn('bounds ', Low(TInt), ' ', High(TInt), ' ', Ord(Low(TEnumR)), ' ', Ord(High(TEnumR)));
end.
