{ An --emit-obj object or --shared library built for another kernel
  (--os=freebsd/netbsd/openbsd/dragonfly) and linked by that system's own cc
  into a C program: tools/vm/objlink.sh runs it, and every test-<bsd> target
  compares its output with the same pair linked by gcc on Linux.

  Covers the paths a host program reaches that an executable does not: the
  init thunk (the body sets Flag before main runs), the heap and managed
  strings, a class, an exception raised and caught inside one call, and the
  translator's write path. }
program test_os_objlink;
uses SysUtils;

type
  TCounter = class
    N: Integer;
    procedure Bump(by: Integer);
  end;

var
  Flag: Integer;

procedure TCounter.Bump(by: Integer);
begin
  N := N + by;
end;

function pxx_sum(n: Integer): Integer; cdecl;
var i, s: Integer;
begin
  s := 0;
  for i := 1 to n do s := s + i;
  pxx_sum := s;
end;

function pxx_flag: Integer; cdecl;
begin
  pxx_flag := Flag;
end;

function pxx_greet(n: Integer): Integer; cdecl;
var s: AnsiString; c: TCounter;
begin
  s := 'hello from pxx, n=' + IntToStr(n);
  c := TCounter.Create;
  c.Bump(n); c.Bump(n);
  s := s + ', twice=' + IntToStr(c.N);
  c.Free;
  WriteLn(s);
  pxx_greet := Length(s);
end;

function pxx_catch(n: Integer): Integer; cdecl;
begin
  try
    if n > 0 then raise Exception.Create('boom ' + IntToStr(n));
    pxx_catch := 0;
  except
    on e: Exception do
    begin
      WriteLn('caught: ', e.Message);
      pxx_catch := Length(e.Message);
    end;
  end;
end;

begin
  Flag := 4242;
end.
