program test_open_array_field_args;
{ Three bugs found via synacode MD5/SHA1 (2026-07-12):
  1. record FIELD passed to a CONST open-array param lost its length header
     (High(Data) garbage -> MD5 stack smash);
  2. indirect calls (proc variable) never flushed the var-open-array
     copy-out, silently losing callee writes;
  3. High(rec.fieldArray) returned -1 (SHA1 buffers never zeroed). }
type
  TCtx = record
    State: array[0..3] of Integer;
    BufLong: array[0..15] of Integer;
  end;
  TTr = procedure(var Buf: array of Integer; const Data: array of Integer);
procedure Tr(var Buf: array of Integer; const Data: array of Integer);
begin
  writeln('hb=', High(Buf), ' hd=', High(Data));
  Buf[0] := Buf[0] + Data[0];
end;
var ctx: TCtx; t: TTr;
begin
  writeln(High(ctx.BufLong), ' ', High(ctx.State));
  ctx.State[0] := 10; ctx.BufLong[0] := 32;
  Tr(ctx.State, ctx.BufLong);
  writeln('direct: ', ctx.State[0]);
  t := @Tr;
  t(ctx.State, ctx.BufLong);
  writeln('indirect: ', ctx.State[0]);
  with ctx do
  begin
    t(State, BufLong);
    writeln('with: ', State[0]);
  end;
end.
