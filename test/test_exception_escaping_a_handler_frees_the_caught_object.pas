program TestExceptionEscapingAHandlerFreesTheCaughtObject;
{ An exception raised from INSIDE a handler must not drop the object that
  handler was handling.

  The free used to be emitted only on the handler's normal fall-through, so a
  handler that left through the exception path skipped it: 2001 live blocks per
  1000 trips, the object plus its message string. The handler body now has its
  own unwind pad and the free is emitted on both exits.
  bug-a-an-exception-that-escapes-its-handler-or-is-bare-re-raised-still-leaks-its-object

  THE BARE `raise;` ROW IS THE POSITIVE CONTROL AND IT IS THE WHOLE REASON THIS
  IS NOT A DOUBLE FREE. It leaves through the exception path too, and there the
  ORIGINAL object is still in flight -- the OUTER handler frees it. Freeing on
  the unwind path unconditionally would free it twice. The pad frees only when
  a DIFFERENT object is in flight than the one it holds, so this row must come
  out clean AND must not crash; a version that got the guard wrong shows up
  here as a segfault or a negative live count, not as a leak.

  THE INTEGER ROW IS THE SECOND CONTROL. `raise <Integer>` is legal in this
  dialect (FPC rejects it; we accept it, which is not a defect) and then what
  is in flight is a VALUE, not a pointer -- freeing it walks 42 as a heap block
  and segfaults. Same guard test/test_exception_object_leaks.pas exists for,
  reproduced here because the unwind path is a second site that has to pass it.

  A VALUE ASSERTION CANNOT OBSERVE THIS DEFECT. Every row below printed the
  right answer while leaking; tools/assert_no_leak.sh is the instrument that
  fails, and the Makefile runs this under -dPXX_ALLOC_CENSUS with a bound. The
  counters printed here are for a human reading a failure, not the check. }

uses SysUtils;

const TRIPS = 500;

var
  i, tookEscape, tookReraise, tookNested, tookInt, tookPlain: Integer;

{ raise a NEW exception from inside the handler — the shape that leaked }
procedure EscapeFromHandler(k: Integer);
begin
  try
    raise Exception.Create('inner-' + Chr(48 + k mod 10));
  except
    on e: Exception do raise Exception.Create('outer-' + e.Message);
  end;
end;

{ bare re-raise — the object stays in flight, the OUTER handler owns it }
procedure BareReraise(k: Integer);
begin
  try
    raise Exception.Create('bare-' + Chr(48 + k mod 10));
  except
    raise;
  end;
end;

{ a handler that raises, caught by a handler that also raises }
procedure NestedEscape(k: Integer);
begin
  try
    EscapeFromHandler(k);
  except
    on e: Exception do raise Exception.Create('third');
  end;
end;

{ what is in flight is not an object at all }
procedure IntFromHandler(k: Integer);
begin
  try
    raise Exception.Create('obj-' + Chr(48 + k mod 10));
  except
    on e: Exception do raise 42;
  end;
end;

begin
  tookEscape := 0; tookReraise := 0; tookNested := 0; tookInt := 0; tookPlain := 0;

  for i := 1 to TRIPS do
    try EscapeFromHandler(i); except on e: Exception do
      if Copy(e.Message, 1, 5) = 'outer' then Inc(tookEscape); end;

  for i := 1 to TRIPS do
    try BareReraise(i); except on e: Exception do
      if Copy(e.Message, 1, 4) = 'bare' then Inc(tookReraise); end;

  for i := 1 to TRIPS do
    try NestedEscape(i); except on e: Exception do
      if e.Message = 'third' then Inc(tookNested); end;

  for i := 1 to TRIPS do
    try IntFromHandler(i); except Inc(tookInt); end;

  { the shape that was always clean, so a fix that broke it is visible here }
  for i := 1 to TRIPS do
    try raise Exception.Create('plain'); except on e: Exception do
      if e.Message = 'plain' then Inc(tookPlain); end;

  WriteLn('escape ', tookEscape);
  WriteLn('reraise ', tookReraise);
  WriteLn('nested ', tookNested);
  WriteLn('int ', tookInt);
  WriteLn('plain ', tookPlain);
  WriteLn('EXCESCAPE OK');
end.
