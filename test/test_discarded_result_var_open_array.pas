{ A FUNCTION whose result is DISCARDED, called with a static array bound to a
  `var` open-array parameter. The array argument rides a copy-in/copy-out temp,
  and the copy-OUT would clobber the result register, so the caller spills the
  result to a compiler-minted temp across it -- a temp whose type came from the
  call STATEMENT's AST node, which has none (nothing consumes a discarded
  result). i386 refuses an unresolved temp outright; the other backends default
  it and were harmlessly right, because the spilled value is dead by
  construction. Every result class here, direct and through a proc variable,
  and the copy-OUT itself is checked (the callee's writes must land). }
program test_discarded_result_var_open_array;

type TFn = function(var o: array of Integer): Boolean;

var
  a: array[0..3] of Integer;
  fp: TFn;
  i, checked: Integer;

procedure Reset;
var k: Integer;
begin
  for k := 0 to 3 do a[k] := k;
end;

function FBool(var o: array of Integer): Boolean;
begin o[0] := o[0] + 10; FBool := True; end;

function FDouble(var o: array of Integer): Double;
begin o[1] := o[1] + 20; FDouble := 2.5; end;

function FStr(var o: array of Integer): AnsiString;
begin o[2] := o[2] + 30; FStr := 'sink'; end;

function FInt64(var o: array of Integer): Int64;
begin o[3] := o[3] + 40; FInt64 := 1234567890123; end;

procedure Show(const tag: AnsiString);
begin
  Write(tag, ':');
  for i := 0 to 3 do Write(' ', a[i]);
  WriteLn;
  Inc(checked);
end;

var
  d: Double;
  s: AnsiString;
  q: Int64;
  b: Boolean;

begin
  checked := 0;

  { discarded results — the shape that could not compile for i386 }
  Reset; FBool(a);   Show('bool  ');
  Reset; FDouble(a); Show('double');
  Reset; FStr(a);    Show('str   ');
  Reset; FInt64(a);  Show('int64 ');

  { the same calls with the result CONSUMED: the writeback must still land,
    and the value must survive the copy-out }
  Reset; b := FBool(a);   WriteLn('bool   consumed: ', b, ' ', a[0]); Inc(checked);
  Reset; d := FDouble(a); WriteLn('double consumed: ', d:0:2, ' ', a[1]); Inc(checked);
  Reset; s := FStr(a);    WriteLn('str    consumed: ', s, ' ', a[2]); Inc(checked);
  Reset; q := FInt64(a);  WriteLn('int64  consumed: ', q, ' ', a[3]); Inc(checked);

  { through a proc VARIABLE — the indirect call has its own writeback flush }
  fp := @FBool;
  Reset; fp(a);         Show('ind   ');
  Reset; b := fp(a);    WriteLn('ind    consumed: ', b, ' ', a[0]); Inc(checked);

  WriteLn('DISCARDED-RESULT VAR OPEN ARRAY OK checked=', checked);
end.
