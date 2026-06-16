program CoSwitchPingPong;
{ Phase-1 proof for the stackful-coroutine machinery: a two-context ping-pong
  driven purely by the low-level __pxxcoswitch intrinsic, with the generator's
  initial stack frame built by hand in Pascal.

  A TCoroCtx is just a saved stack pointer; here each context's sp lives in a
  plain Int64 slot (mainSp / genSp). __pxxcoswitch(@from, @to) stores the
  current rsp into [from] and loads rsp from [to].

  Expected output:
    main: 1
    gen: 1
    main: 2
    gen: 2
    main: 3
    gen: 3
    main: 4
    gen: 4
    main: 5
    gen: 5
    done }

type
  PWord = ^NativeInt;   { pointer-sized machine-word access at an address }

var
  mainSp : Int64;       { TCoroCtx.sp for the main context }
  genSp  : Int64;       { TCoroCtx.sp for the generator context }
  stackBuf : array[0..16383] of Byte;
  counter  : Integer;

procedure GenEntry;
{ Runs on the generator's heap stack. Yields back to main after each step. }
begin
  while True do
  begin
    Inc(counter);
    writeln('gen: ', counter);
    __pxxcoswitch(@genSp, @mainSp);   { yield to main }
  end;
end;

procedure SetupGen;
{ Build the initial saved-state frame the first CoSwitch-in will pop:
    [sp+0]  exc_top (0 -> fresh exception chain on this stack)
    [sp+8]  r15  [sp+16] r14  [sp+24] r13  [sp+32] r12  [sp+40] rbx  [sp+48] rbp
    [sp+56] return address -> GenEntry
  rsp at GenEntry entry must be == 8 (mod 16), so align the 16-byte top, then
  back off 8, then reserve the 8 saved qwords (64 bytes). }
var top: Int64;
begin
  top := Int64(@stackBuf[0]) + 16384;   { one past the buffer end }
  top := top - (top mod 16);            { 16-align down }
  top := top - 8;                       { entry rsp == 8 (mod 16) }
  top := top - 64;                      { room for 8 saved qwords }
  PWord(top + 0)^  := 0;                { exc_top }
  PWord(top + 8)^  := 0;                { r15 }
  PWord(top + 16)^ := 0;                { r14 }
  PWord(top + 24)^ := 0;                { r13 }
  PWord(top + 32)^ := 0;                { r12 }
  PWord(top + 40)^ := 0;                { rbx }
  PWord(top + 48)^ := 0;                { rbp }
  PWord(top + 56)^ := Int64(@GenEntry); { resume address }
  genSp := top;
end;

var i: Integer;
begin
  counter := 0;
  SetupGen;
  for i := 1 to 5 do
  begin
    writeln('main: ', i);
    __pxxcoswitch(@mainSp, @genSp);     { resume the generator }
  end;
  writeln('done');
end.
