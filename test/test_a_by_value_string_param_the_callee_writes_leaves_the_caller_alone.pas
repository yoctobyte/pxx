{ SPDX-License-Identifier: MPL-2.0 }
program test_a_by_value_string_param_the_callee_writes_leaves_the_caller_alone;
{ A by-value AnsiString or dynamic-array parameter is OWNED by the callee:
  referenced at entry, released at exit. Before, it was borrowed, so the
  textbook UpperStr below upper-cased the CALLER's string too (every target,
  pin v423 included), and a callee that rebound the param leaked one block
  per call. The Makefile row also runs this under -dPXX_ALLOC_CENSUS through
  tools/assert_no_leak.sh with a loop count, so both halves are asserted.
  bug-a-a-by-value-string-param-written-by-the-callee-changes-the-callers-string }
{$mode objfpc}
uses sysutils;
type TIntArr = array of Integer;

function UpperStr(s: string): string;
var i: Integer;
begin
  for i := 1 to Length(s) do s[i] := UpCase(s[i]);
  Result := s;
end;

function Rebind(s: AnsiString): Integer;
begin
  s := s + 'xyz';
  Result := Length(s);
end;

function RebindArr(a: TIntArr): Integer;
begin
  SetLength(a, 9);
  a[8] := 1;
  Result := Length(a);
end;

procedure ElemWrite(a: TIntArr);
begin
  a[0] := 7;                { dynarrays SHARE: fpc writes the caller's too }
end;

function ConstLen(const s: AnsiString): Integer;
begin
  Result := Length(s);
end;

function OpenSum(const a: array of Integer): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(a) do Result := Result + a[i];
end;

function OpenWrite(a: array of Integer): Integer;
begin
  a[0] := 100;
  Result := a[0];
end;

function Outer(s: AnsiString): AnsiString;
  procedure Inner;
  begin
    s := s + '!';           { a nested routine rebinding the outer's param }
  end;
begin
  Inner;
  Result := s;
end;

procedure Raiser(s: AnsiString);
begin
  s := s + '-temp';
  raise Exception.Create('boom ' + s);
end;

var
  name, shout, lit: AnsiString;
  arr: TIntArr;
  i, n, code: Integer;
  sink: Int64;
begin
  n := 1;
  if ParamCount > 0 then Val(ParamStr(1), n, code);
  name := 'hello'; name := name + ' world';
  SetLength(arr, 3); arr[0] := 1; arr[1] := 2; arr[2] := 3;
  sink := 0;
  for i := 1 to n do
  begin
    shout := UpperStr(name);
    sink := sink + Rebind(name) + RebindArr(arr) + ConstLen(name)
            + OpenSum(arr) + OpenWrite(arr) + Length(Outer(name));
    try
      Raiser(name);
    except
      on E: Exception do sink := sink + Length(E.Message);
    end;
    sink := sink + Length(UpperStr('literal arg'));
  end;
  ElemWrite(arr);
  lit := 'abc';
  writeln(name, ' | ', shout);
  writeln('arr ', arr[0], ' ', arr[1], ' ', arr[2], ' len ', Length(arr));
  writeln('outer ', Outer(name), ' | ', name);
  writeln('lit ', UpperStr(lit), ' ', lit);
  writeln('sink ', sink div n);
end.
