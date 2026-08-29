program aggret_slice;
{ Aggregate function results: the caller-owned hidden destination.

  abi.inc's RetViaHiddenDest is ONE convention covering five result shapes, so
  as many as can be reached are exercised together — a version that gets
  records right and fixed arrays wrong is the failure this slice exists to
  catch. The fixed-array row is here for a sharper reason: its kind is the
  ELEMENT's, so the kind-only oracle says "scalar" and only
  ABIRetViaHiddenDestProc sees the aggregate.

  THREE OF THE FIVE ARE NOT HERE, and not because they work. A set result
  needs set CONSTRUCTION (`value IR op 33`) and `in` against a set VARIABLE
  (`binary operator 99`), neither of which this target has; a variant result
  and a promotable-int result have their own unimplemented shapes. They travel
  by this same convention, so the convention is landing UNTESTED for them —
  said out loud here because "records work" would otherwise read as "aggregate
  results work". }
type
  TP  = record X, Y: Integer; end;
  TA  = array[0..3] of Integer;
  TR  = record Tag: Integer; Name: string[15]; end;

function MakeP(a, b: Integer): TP;
begin Result.X := a; Result.Y := b; end;

function MakeA(base: Integer): TA;
var i: Integer;
begin for i := 0 to 3 do Result[i] := base + i; end;

function MakeStr(n: Integer): string[15];
begin if n > 0 then MakeStr := 'pos' else MakeStr := 'neg'; end;

function MakeR(t: Integer): TR;
begin Result.Tag := t; Result.Name := 'rec'; end;

{ Reading a FIELD of a call result, with no intervening variable: the
  destination is a temp the lowering minted, not a named slot. Written this way
  rather than as `SumP(MakeP(...))` because a record VALUE parameter is a
  different convention this target does not implement yet, and bundling it here
  would make this slice fail for a reason that is not its subject. }

var
  p: TP; a: TA; r: TR; i, n: Integer;
begin
  p := MakeP(3, 4);
  writeln('rec   x=', p.X, ' y=', p.Y);

  a := MakeA(10);
  writeln('arr   ', a[0], ' ', a[1], ' ', a[2], ' ', a[3]);

  writeln('str   ', MakeStr(1), ' ', MakeStr(-1));

  r := MakeR(7);
  writeln('recs  tag=', r.Tag, ' name=', r.Name);

  { straight into a field read — the destination is an unnamed temp }
  writeln('temp  ', MakeP(20, 22).X + MakeP(20, 22).Y);

  { two aggregate calls in one expression, so two live destinations }
  writeln('two   ', MakeP(1, 2).Y + MakeP(30, 40).X);

  { in a loop, so the destination temp is reused every trip }
  n := 0;
  for i := 1 to 3 do n := n + MakeP(i, i * 10).Y;
  writeln('loop  ', n);
  writeln('done');
end.
