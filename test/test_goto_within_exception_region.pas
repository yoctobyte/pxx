program test_goto_within_exception_region;
{ The legal half of test_goto_across_exception_region_fail.pas: every goto here
  stays in its own protected region -- inside one try body, inside one handler,
  or outside every try while jumping OVER a whole try statement. (A label inside
  a `finally` body is not here: that body is lowered twice and the second copy
  is refused as a duplicate IR label, on the pin too --
  bug-a-a-label-inside-a-finally-body-is-a-duplicate-ir-label.) All must
  compile and run, and the final raise is deliberately UNHANDLED: if any of
  these left a frame on the chain, it would longjmp into dead stack and die
  without the diagnostic, which is what the Makefile row asserts on.
  bug-a-something-in-lekkerzeilen-s-startup-still-leaves-an-exception-frame-on-the-chain }
{$mode objfpc}
uses sysutils;

function InsideTry: Integer;
label again, done;
var n: Integer;
begin
  n := 0;
  try
    again:
    Inc(n);
    if n < 5 then goto again;
    goto done;
    n := -1;
    done:
  except
    n := -2;
  end;
  Result := n;
end;

function OverATry(skip: Boolean): Integer;
label past;
begin
  Result := 1;
  if skip then goto past;
  try
    Result := 2;
  except
  end;
  past:
  Result := Result * 10;
end;

function InsideHandler: Integer;
label l;
begin
  Result := 0;
  try
    raise Exception.Create('x');
  except
    on E: Exception do
    begin
      goto l;
      Result := -1;
      l:
      Result := Result + 7;
    end;
  end;
end;

begin
  writeln('inside ', InsideTry);
  writeln('over ', OverATry(True), ' ', OverATry(False));
  writeln('handler ', InsideHandler);
  raise Exception.Create('frame chain is intact');
end.
