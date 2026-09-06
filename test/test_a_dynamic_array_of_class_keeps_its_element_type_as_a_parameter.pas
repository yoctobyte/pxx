program test_a_dynamic_array_of_class_keeps_its_element_type_as_a_parameter;
{ A dynamic array whose ELEMENT is a class must keep that element type when it
  arrives as a PARAMETER. It did not: `array of SomeRecord` matched the
  `parr and tyRecord` arm in AllocParam's caller and got ElemRecName; `array of
  SomeClass` matched no array arm at all, fell through to the scalar
  class/record arm, and had its element's class id written to RecName -- which
  is not where ResolveNodeRec looks. A[i] then resolved REC_NONE.

  THE ROWS ARE THREE DIFFERENT SYMPTOMS OF THE ONE CAUSE, and only the first is
  silent:
    - a FIELD read resolved by offset and printed a plausible wrong integer
      (4265192 where fpc prints 'cc') with NO diagnostic;
    - `var` and open-array reached a different addressing path and dumped ~45KB
      of heap;
    - `A[0].ClassName` reported `"ClassName": no such member on this
      record/class`, pointing at the member rather than at the array.

  The RECORD and INTEGER element rows are the CONTROLS: they were correct
  before the fix and must stay correct, because they are what proves the
  boundary is `element is a class` and not `element is an aggregate`. A global
  array of class was also always correct, so that row is here to keep the
  boundary at PARAMETER.

  Both fields of the class element are read on purpose. Before the fix both
  printed the SAME wrong value, which is what showed the element POINTER was
  wrong rather than one field's offset -- a one-field probe cannot tell those
  apart.

  HOW THIS FAILS, measured against the compiler one commit earlier rather than
  assumed: it does NOT print a FAIL line. It does not COMPILE. The ClassName
  row hard-errors first --

      candidates: Chk(AnsiString, AnsiString, AnsiString)
      near: ] . ClassName , 'TEl' ) >>>

  -- so no binary is produced and the Makefile step fails on the compile, not
  on an assertion. That is a real failure and the ClassName row asserting
  itself, but the message names an overload rather than an array, so read it as
  "the element type is gone" and not as a Chk() signature problem. The value
  rows below cannot report anything in that state, which is why they are not
  the only rows here.

  bug-a-a-dynamic-array-of-class-loses-its-element-type-when-it-is-a-parameter }
{$mode objfpc}
type
  TEl  = class Ext: string; Num: Integer; end;
  TRec = record Ext: string; end;
  TArrC = array of TEl;
  TArrR = array of TRec;
  TArrI = array of Integer;

var ok, total: Integer;

procedure Chk(const what, got, want: AnsiString);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else WriteLn('FAIL ', what, ': got "', got, '" want "', want, '"');
end;

procedure ChkI(const what: AnsiString; got, want: Integer);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else WriteLn('FAIL ', what, ': got ', got, ' want ', want);
end;

procedure ByValue(A: TArrC);          begin Chk('by-value field', A[0].Ext, 'cc'); ChkI('by-value 2nd field', A[0].Num, 42); end;
procedure ByVar(var A: TArrC);        begin Chk('var field', A[0].Ext, 'cc'); end;
procedure ByConst(const A: TArrC);    begin Chk('const field', A[0].Ext, 'cc'); end;
procedure ByOpen(const A: array of TEl); begin Chk('open array field', A[0].Ext, 'cc'); end;
procedure ClsName(A: TArrC);          begin Chk('ClassName', A[0].ClassName, 'TEl'); end;
{ controls — correct before the fix, and they are what pins the boundary }
procedure RecElem(A: TArrR);          begin Chk('record element', A[0].Ext, 'rr'); end;
procedure IntElem(A: TArrI);          begin ChkI('integer element', A[0], 7); end;

var ac: TArrC; ar: TArrR; ai: TArrI; e: TEl;
begin
  ok := 0; total := 0;
  SetLength(ac, 1); e := TEl.Create; e.Ext := 'cc'; e.Num := 42; ac[0] := e;
  SetLength(ar, 1); ar[0].Ext := 'rr';
  SetLength(ai, 1); ai[0] := 7;

  Chk('global class', ac[0].Ext, 'cc');   { control: the PARAMETER is the boundary }
  ByValue(ac);
  ByVar(ac);
  ByConst(ac);
  ByOpen(ac);
  ClsName(ac);
  RecElem(ar);
  IntElem(ai);

  WriteLn('total ok ', ok, ' / ', total);
end.
