program test_failed_as_downcast_is_catchable;
{ A failed `as` downcast raises a catchable EInvalidCast. It used to be an
  inline Halt(1): no message, and uncatchable — the one member of the
  checked-operation family a handler could not intercept, for the one construct
  whose purpose is a downcast you are prepared to have fail.
  bug-a-a-failed-as-downcast-dies-silently-and-uncatchably }
uses SysUtils;
type
  TA = class end;
  TB = class(TA) end;
  TC = class(TA) end;
var a: TA; b: TB; n: TA; ok: Integer;

procedure Deep(x: TA);
begin
  { the raise must cross a frame and run the finally on the way out }
  try
    WriteLn('deep ', (x as TC).ClassName);
  finally
    WriteLn('finally');
  end;
end;

begin
  ok := 0;
  a := TB.Create;

  { the success path is unchanged and still yields the instance }
  b := a as TB;
  WriteLn('good ', b.ClassName);

  try
    WriteLn((a as TC).ClassName);
  except
    on E: EInvalidCast do begin WriteLn('caught ', E.ClassName, ': ', E.Message); Inc(ok); end;
  end;

  { it is an Exception, so a generic handler takes it too }
  try
    b := TB(a as TC);
  except
    on E: Exception do begin WriteLn('generic ', E.ClassName); Inc(ok); end;
  end;

  try Deep(a); except on E: EInvalidCast do begin WriteLn('outer'); Inc(ok); end; end;

  { nil passes through: `nil as T` is nil, not a failure }
  n := nil;
  if (n as TC) = nil then begin WriteLn('nil ok'); Inc(ok); end;

  a.Free;
  WriteLn('total ok ', ok, ' / 4');
end.
