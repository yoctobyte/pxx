program TestInterruptHiddenLoop;
{ The hidden loop in lib/rtl/interrupts.pas's finalization. A program that
  registers a handler and has a LIVE SOURCE keeps being served after its main
  body ends, until the source closes.

  Here the live source is opened by hand (IntSourceOpen), which is what
  espgpio does per armed pin and espadc on start. Three events are queued
  before the end and no blocking point runs, so none is delivered in the
  main body. 'main-end' must therefore print BEFORE all three, and that
  ordering is the claim: the events were served after the program fell off
  its end. The handler closes the source on the third event and the program
  must then exit; the Makefile row runs it under `timeout`.

  -dNO_SOURCE is the control: no source is opened, so the loop must not
  engage, the three queued events are never delivered, and the program
  exits right after 'main-end'. }
uses interrupts;

procedure OnEv(const ev: TIntEvent);
begin
  writeln('served id ', ev.Id, ' live ', IntLiveSources);
  if ev.Id = 3 then
  begin
    IntSourceClose;
    writeln('closed live ', IntLiveSources);
  end;
end;

begin
  IntOnEvent(INT_SRC_TEST, @OnEv);
{$ifndef NO_SOURCE}
  IntSourceOpen;
{$endif}
  IntPush(INT_SRC_TEST, 1);
  IntPush(INT_SRC_TEST, 2);
  IntPush(INT_SRC_TEST, 3);
  writeln('main-end delivered ', IntDelivered, ' pending ', IntPending);
end.
