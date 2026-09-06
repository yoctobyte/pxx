program test_a_named_dynamic_array_parameter_still_takes_nil_as_a_default;
{ bug-p-a-default-value-is-accepted-on-an-open-array-parameter -- THE POSITIVE
  CONTROL FOR THE REFUSAL, and it is drawn from the population the refusal is
  about rather than from ordinary code.

  A NAMED DYNAMIC ARRAY IS NOT AN OPEN ARRAY: it is a handle, `nil` is a
  meaningful value for it, and fpc 3.2.2 compiles `a: TArr = nil` and prints
  Length 0. The first version of the free-routine guard tested `isArr` alone and
  rejected exactly this -- isArr is true for an open array, a named FIXED array
  and a named DYNAMIC one alike, so it is the wrong half of the type to ask
  about. That is why the caller computes the flag and the shared parser only
  obeys it.

  Every one of the four parameter parsers is represented, because the refusal
  now lives in the one function all four call and a flag passed wrongly at one
  call site would reject only there.

  THE DEFAULT IS WRITTEN ON BOTH THE DECLARATION AND THE IMPLEMENTATION for the
  methods, and that is not stylistic: writing it on the declaration alone is
  lost for a named dynamic array specifically (the call then answers `wrong
  number of parameters`, while the same omission for an Integer or a string
  default is honoured). Measured 2026-09-06 and filed separately -- it is a
  different mechanism from this refusal and must not be smuggled into this
  file's expectation.

  THE INTERFACE METHOD IS DECLARED AND DISPATCHED THROUGH THE CLASS, NOT THROUGH
  THE INTERFACE, and the reason is a second live defect rather than tidiness:
  an interface-dispatched call segfaults both when it omits a defaulted argument
  and when it passes a named dynamic array, with fpc printing the right answer
  for both -- measured 2026-09-06, and both filed. What
  this file is entitled to assert is that the four PARAMETER PARSERS accept the
  declaration -- the interface one included, which is the parser with no
  implementation header to fall back on -- and the declaration compiling is that
  assertion. Dispatching through the interface here would make this row fail for
  a reason that has nothing to do with the refusal it exists to control. }
type
  TArr = array of Integer;

  TC = class
    procedure M(const a: TArr = nil);
    procedure F(d: Double = 2.5);
  end;

  TR = record
    procedure R(const a: TArr = nil);
  end;

  IFoo = interface
    ['{5E1B0A11-1111-4222-8333-444455556666}']
    procedure I1(const a: TArr = nil);
  end;

  TFoo = class(TInterfacedObject, IFoo)
    procedure I1(const a: TArr = nil);
  end;

var
  fails: Integer;

procedure Free1(const a: TArr = nil);
begin
  if Length(a) <> 0 then
  begin
    WriteLn('FAIL free routine: got ', Length(a), ' want 0');
    fails := fails + 1;
  end;
end;

procedure TC.M(const a: TArr = nil);
begin
  if Length(a) <> 0 then
  begin
    WriteLn('FAIL class method: got ', Length(a), ' want 0');
    fails := fails + 1;
  end;
end;

procedure TC.F(d: Double = 2.5);
begin
  if (d < 2.4999) or (d > 2.5001) then
  begin
    WriteLn('FAIL class method float default: got ', d:0:4, ' want 2.5000');
    fails := fails + 1;
  end;
end;

procedure TR.R(const a: TArr = nil);
begin
  if Length(a) <> 0 then
  begin
    WriteLn('FAIL record method: got ', Length(a), ' want 0');
    fails := fails + 1;
  end;
end;

procedure TFoo.I1(const a: TArr = nil);
begin
  if Length(a) <> 0 then
  begin
    WriteLn('FAIL interface method: got ', Length(a), ' want 0');
    fails := fails + 1;
  end;
end;

var
  o: TC;
  r: TR;
  i: IFoo;
  ff: TFoo;
begin
  fails := 0;
  Free1;
  o := TC.Create;
  o.M;
  o.F;
  o.Free;
  r.R;
  ff := TFoo.Create;
  ff.I1;
  i := ff;   { the interface reference is TAKEN -- only the dispatch is avoided }
  if i = nil then
  begin
    WriteLn('FAIL interface reference is nil');
    fails := fails + 1;
  end;
  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('DYNARRAYDEFAULT OK');
end.
