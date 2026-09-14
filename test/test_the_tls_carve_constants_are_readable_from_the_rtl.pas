program test_the_tls_carve_constants_are_readable_from_the_rtl;
{ __pxxTlsBlockSize and __pxxSigAltStackSize -- the two sizes the clone stub
  carves off the top of a child stack, answered by the COMPILER so the RTL can
  read them instead of restating them.

  WHY THEY EXIST: palthread.pas's PAL_MIN_STACK already restates both and says
  in its own comment that it is the second copy and the stub is the first. The
  pthread route added a THIRD place that must allocate the same two regions, and
  a third copy of a number that has already moved once (TLS_BLOCK_SIZE grew when
  `threadvar` landed) is silent corruption waiting for the next change: too small
  a block means gs-relative slots write past the mapping.

  RELATIONS, NOT LITERALS. Pinning 4224 and 32768 here would make this file the
  FOURTH copy and it would have to be edited every time either number moved --
  which is the failure it exists to prevent. What is asserted instead is the
  invariant palthread states in prose: a minimum child stack must comfortably
  exceed everything carved off its top. That holds at any size and fails when
  someone grows a region past the floor. }

uses palthread;

var
  tls, alt, carve: Int64;
  ok: Boolean;

begin
  tls := __pxxTlsBlockSize;
  alt := __pxxSigAltStackSize;
  carve := tls + alt;
  ok := True;

  { Both are real sizes, not a zero falling out of an unrecognised name --
    a builtin that quietly stopped folding would answer 0 and every size
    comparison below would still pass. }
  if tls <= 0 then begin WriteLn('FAIL: tls block size is ', tls); ok := False; end;
  if alt <= 0 then begin WriteLn('FAIL: alt stack size is ', alt); ok := False; end;

  { A signal alt stack has a kernel minimum and a TLS block holds a slot map plus
    the threadvar area; neither can sanely be under a page. }
  if tls < 4096 then begin WriteLn('FAIL: tls block under a page: ', tls); ok := False; end;
  if alt < 4096 then begin WriteLn('FAIL: alt stack under a page: ', alt); ok := False; end;

  { THE INVARIANT: the carve has to fit, with room left to run in. PAL_MIN_STACK
    is palthread's floor; if a region grows past it, a thread starts with its
    stack pointer already below its own mapping. }
  if carve >= PAL_MIN_STACK then
  begin
    WriteLn('FAIL: carve ', carve, ' does not fit PAL_MIN_STACK ', PAL_MIN_STACK);
    ok := False;
  end;
  if carve * 2 >= PAL_MIN_STACK then
  begin
    WriteLn('FAIL: carve ', carve, ' leaves under half of PAL_MIN_STACK ', PAL_MIN_STACK);
    ok := False;
  end;

  if ok then WriteLn('TLS CARVE OK') else WriteLn('TLS CARVE FAIL');
end.
