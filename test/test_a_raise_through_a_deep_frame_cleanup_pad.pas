{$mode objfpc}{$H+}
program test_a_raise_through_a_deep_frame_cleanup_pad;
{ A raise that unwinds through a procedure's CLEANUP pad (it owns a managed
  local, so its prologue chains a cleanup exception frame) when the procedure
  has slots far below its frame base.

  Xtensa windowed picks a per-body frame-pointer bias for such a body and
  moves a7 at the start of the body. The cleanup frame's setjmp runs in the
  prologue, before that move, so the raise restored the prologue's a7 and the
  pad released the managed local through the wrong address: a segfault, or a
  corrupted caller. Found before the bias shipped
  (feature-xtensa-per-body-frame-pointer-bias); the pad now moves a7 again.
  Every other target prints the same lines; the test is target-neutral. }
uses sysutils;

procedure Boom(n: Integer);
begin
  if n > 0 then raise Exception.Create('boom ' + IntToStr(n));
end;

function Deep(n: Integer): Integer;
var a: array[0..80] of Integer; i, s: Integer; name: AnsiString;
begin
  for i := 0 to 80 do a[i] := i * 3;
  name := 'deep' + IntToStr(n);
  s := a[2] + a[79] + Length(name);
  Boom(n);
  Result := s + a[40];
end;

function Outer(n: Integer): Integer;
var b: array[0..40] of Integer; k: Integer; tag: AnsiString;
begin
  for k := 0 to 40 do b[k] := k;
  tag := 'outer';
  Result := Deep(n) + b[40] + Length(tag);
end;

var i, caught: Integer;
begin
  writeln(Deep(0));
  writeln(Outer(0));
  caught := 0;
  for i := 1 to 50 do
  begin
    try
      writeln(Outer(i));
    except
      on E: Exception do
      begin
        Inc(caught);
        if i = 50 then writeln('caught ', E.Message);
      end;
    end;
  end;
  writeln('caught ', caught);
  writeln('end');
end.
