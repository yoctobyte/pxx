program test_ifopt_unconditional_letters;
{ G, J and X are the third shape $IFOPT has to answer for, and the only one
  where we DIVERGE FROM FPC ON PURPOSE.

    R Q I C Z   answer from a VARIABLE -- a switch we track, both signs work
    A L O       answer False -- fpc does not track the letter either
    G J X       answer True ALWAYS -- fpc tracks them, we have nothing to track
                because the behaviour they name is unconditional here

  fpc defaults all three ON and a minus form really turns them off. pxx has no
  off state to reach, so the minus form is inert and $IFOPT keeps saying on.
  That is the rule this function already applies to C from the other direction:
  IFOPT reports THIS compiler's state, and a source asking `did my minus form
  take effect` is answered honestly with `no`.

  THE POINT OF THIS FILE IS THAT THE BEHAVIOURAL CLAIM IS ASSERTED BESIDE THE
  ANSWER. An IFOPT row on its own only pins a constant; paired with the probe
  that justifies it, the pair fails the moment someone implements one of the
  minus forms and forgets this file -- which is exactly when the answer would
  turn into a lie. Rows 1-2 are the claim, rows 3-5 are the answer.

  Deliberately NOT in test_ifopt_tracks_the_switch_it_names, whose .expected is
  byte-compared against fpc 3.2.2. Pinning a chosen divergence in an oracle file
  replaces the oracle with our own opinion.

  FPC 3.2.2 REFUSES THIS FILE, and that is the strongest evidence in it:

    test_ifopt_unconditional_letters.pas(60,3)
      Error: Can't assign values to const variable

  row 2, under the J- above. So the divergence is a real behavioural difference
  between the two compilers and not a reporting choice -- fpc's J- does
  something and ours does not, which is precisely why fpc's IFOPT answer would
  be wrong about us. Pin v404 scores 4/7 here, failing rows 3, 4 and 5, which is
  this file's positive control. }

var
  okCount: Integer;

procedure Chk(n: Integer; cond: Boolean);
begin
  if cond then begin WriteLn('ok ', n); okCount := okCount + 1; end
  else WriteLn('FAIL ', n);
end;

{ X-: fpc refuses a discarded function result under it ("Illegal expression").
  Here the call below compiles either way, which is the measurement behind
  $IFOPT X+ answering on. }
var xCalled: Boolean;
function XProbe: Integer;
begin
  xCalled := True;
  XProbe := 7;
end;

{ J-: fpc makes typed constants read-only under it. Ours stay writable. }
{$J-}
const JConst: Integer = 5;

begin
  okCount := 0;

  { 1. extended syntax, with the minus form in force above -- the result is
       discarded and the call still happens. }
{$X-}
  xCalled := False;
  XProbe;
  Chk(1, xCalled);

  { 2. a typed constant is writable with the minus form in force. }
  JConst := 9;
  Chk(2, JConst = 9);

  { 3-5. and IFOPT says so, after the minus form rather than before it. This is
     the row that differs from fpc, which answers off for all three. }
{$G-}
  {$IFOPT G+} Chk(3, True); {$ELSE} Chk(3, False); {$ENDIF}
  {$IFOPT J+} Chk(4, True); {$ELSE} Chk(4, False); {$ENDIF}
  {$IFOPT X+} Chk(5, True); {$ELSE} Chk(5, False); {$ENDIF}

  { 6. the negative that keeps rows 3-5 from being "IFOPT says yes to
     everything": A is a letter neither compiler tracks, so it must still say
     off -- with a numeric setting applied, which is the form that would fool a
     PackRecordsVal reading. }
{$A8}
  {$IFOPT A+} Chk(6, False); {$ELSE} Chk(6, True); {$ENDIF}

  { 7. and one that still TRACKS, so this file cannot pass by hardwiring True
     the way the whole directive used to pass by hardwiring False. }
{$R-}
  {$IFOPT R+} Chk(7, False); {$ELSE} Chk(7, True); {$ENDIF}

  WriteLn('total ok ', okCount, ' / 7');
end.
