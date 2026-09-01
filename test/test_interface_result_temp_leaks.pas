program test_interface_result_temp_leaks;
{ An interface returned by a FUNCTION is released, in a loop as well as once.

  TWO INDEPENDENT DEFECTS, and neither fix works without the other -- measured
  by building each alone:

  1. THE SRET TEMP HAD NO OWNER. An interface-returning call lands its result in
     a hidden caller-side temp. The argument path then RETAINS out of that temp
     into its own and releases that one at end of statement, so the call site
     reconciled and the factory's own reference did not. Every reference leaked.

  2. A LOOP NEVER FLUSHED. IRFlushPostCallIntf ran at AN_SEQ (per statement) and
     per `if` arm, and nowhere else. A loop is ONE statement, so a body that is
     not a BEGIN/END block never reached AN_SEQ: every by-value interface and
     managed-record argument temp the body made was finalized ONCE, after the
     loop, on the slot's LAST occupant. Every earlier occupant was overwritten
     with no release at all.

  The control that separated them is small and worth keeping: with a printing
  destructor, `for k := 1 to 3 do TakeI(MkIntf(k))` destroyed only N=3 while FPC
  destroyed all three, and wrapping the IDENTICAL body in `begin ... end` made
  pxx destroy all three. Same temp, same call, different flush boundary -- so
  defect 2 is the boundary and not the temp.

  live before -> after, 1000 trips per arm:
    TakeI(MkIntf(k))       const param   921 -> 1   frees 0 -> 920
    TakeIv(MkIntf(k))      value param   921 -> 1   frees 0 -> 920
    MkIntf(k).Id           method on it  921 -> 1   frees 0 -> 920
    g := MkIntf(k)         CONTROL       921/919 -> 921/919, unmoved
    g := MkIntf(k); TakeI(g)  CONTROL    921/919 -> 921/919, unmoved
  allocs is 921 on every row, before and after -- same traffic, so the delta is
  ownership. The two controls were ALWAYS clean, because a variable owned the
  reference; that is what says this is about the temp.

  This whole program, against a4c67a5e6cc8 (the binary immediately before the
  fix): live 2503 -> 3 against a bound of 50, allocs 4274 either way. REJECTED by
  the pre-fix binary (rc=1), which is the check that says it can fail at all.
  Identical on x86-64/i386/aarch64/arm32/riscv32, and the pre-fix binary prints
  the same `sink=1003000` on all five while leaking, so only the absolute bound
  sees it.

  FPC's heaptrc says `0 unfreed memory blocks` for the const-param program, so
  this is a divergence from the oracle and not a policy choice. pxx releases the
  temp at the end of the statement containing the call; FPC defers it to the
  next statement. Both destroy the same objects the same number of times, which
  is what the destructor-print control above checks.

  All three LOOP KINDS are here because the flush had to be added to each
  separately, and a fix present in two of three is the shape that stays broken.
  The managed-RECORD by-value arm is here for the same reason: it rides the same
  queue, so the flush change moves it too, and a wrong move there is a double
  finalize rather than a leak -- which is why this runs under -dPXX_HEAP_DEBUG.
  bug-a-an-interface-returned-by-a-function-leaks-unless-it-is-assigned }
{$mode objfpc}{$H+}
uses sysutils;

const N = 500;

type
  IThing = interface ['{11111111-2222-3333-4444-555555555555}']
    function Id: Integer;
  end;

  TThing = class(TInterfacedObject, IThing)
  public
    N: Integer;
    function Id: Integer;
  end;

  TR = record S: AnsiString; K: Integer; end;

var sink: Integer;
    g: IThing;

function TThing.Id: Integer;
begin
  Id := N;
end;

function MkIntf(n: Integer): IThing;
var t: TThing;
begin
  t := TThing.Create;
  t.N := n;
  MkIntf := t;
end;

function MkR(n: Integer): TR;
begin
  MkR.S := 'r' + IntToStr(n mod 10);
  MkR.K := n;
end;

procedure TakeI(const a: IThing);  begin Inc(sink, a.Id); end;
procedure TakeIv(a: IThing);       begin Inc(sink, a.Id); end;
procedure TakeR(a: TR);            begin Inc(sink, Length(a.S) + a.K); end;

procedure Run;
var k: Integer;
begin
  { the three consumers that never store the result — bare loop bodies }
  for k := 1 to N do TakeI(MkIntf(k));
  for k := 1 to N do TakeIv(MkIntf(k));
  for k := 1 to N do Inc(sink, MkIntf(k).Id);

  { CONTROLS: a variable owns it, and was always clean }
  for k := 1 to N do begin g := MkIntf(k); Inc(sink, g.Id); end;
  for k := 1 to N do begin g := MkIntf(k); TakeI(g); end;
  g := nil;

  { every loop kind, because the flush was added to each separately }
  k := 0;
  while k < N do begin Inc(k); TakeI(MkIntf(k)); end;
  k := 0;
  repeat Inc(k); TakeI(MkIntf(k)) until k >= N;

  { the managed-RECORD by-value temp rides the same queue — a wrong move here is
    a double finalize, not a leak }
  for k := 1 to N do TakeR(MkR(k));
end;

begin
  sink := 0;
  Run;
  WriteLn('sink=', sink);
end.
