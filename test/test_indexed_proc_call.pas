program test_indexed_proc_call;
{ Indexed / element proc-value indirect call: arr[i](args).
  Covers a plain proc-type element (int arg) and a const-record arg through it. }
type
  TRec = record a, b: Integer; end;
  TFn  = function(x: Integer): Integer;
  TRecFn = function(const r: TRec): Integer;

function Dbl(x: Integer): Integer; begin Dbl := x * 2; end;
function Inc1(x: Integer): Integer; begin Inc1 := x + 1; end;
function Sum(const r: TRec): Integer; begin Sum := r.a + r.b; end;

var
  fns:  array[0..1] of TFn;
  rfns: array[0..0] of TRecFn;
  v:    TRec;
  i:    Integer;
begin
  fns[0] := @Dbl;
  fns[1] := @Inc1;
  writeln(fns[0](21));        { 42 }
  writeln(fns[1](41));        { 42 }
  for i := 0 to 1 do
    writeln(fns[i](10));      { 20 then 11 }

  rfns[0] := @Sum;
  v.a := 20; v.b := 22;
  writeln(rfns[0](v));        { 42 }
end.
