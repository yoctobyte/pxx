program test_for_in_over_a_set_valued_call;
{$mode objfpc}{$H+}
{ `for x in F` where F is a function RETURNING A SET.

  It was refused with `for-in: not a generator, enum type, or iterable
  variable` -- the message from the container-expression DISPATCH, not from the
  set loop builder, because a call result was a third source of a set and only
  two had an arm: a symbol (ParseForInSetAST) and a record field / qualified
  lvalue (ParseForInNodeAST). The set's element identity is carried per
  CARRIER -- SymSetEnumId, UFldSetEnumId, UPropSetEnumId, ProcParamSetEnumId,
  AliasSetElemTk -- and the RETURN carrier had no copy at all. A rule spelled
  once per carrier fails by an ABSENT copy, and the copies that exist agree
  perfectly with each other, so reading them against one another finds nothing.

  ROW E IS THE ONE THAT IS NOT ABOUT PARSING. A set membership loop scans its
  domain, so a container that is a CALL must be evaluated ONCE and not once per
  candidate element -- 256 times for a set of Char, with every side effect.
  Row E counts the calls; it is the row a fix that merely stops the refusal can
  still fail.

  Rows C, D and F were GREEN before the fix and are here as the boundary: a
  dyn-array-returning call, a set reached through a record field, and the
  assign-to-a-temp workaround all worked, which is what pinned the defect to
  the set RESULT specifically rather than to `for-in` over a call.

  .expected IS fpc 3.2.2's own output on this source.
  bug-p-for-in-over-a-set-returning-function-call-is-refused }

type
  TM  = (mA, mB, mC, mD);
  TMs = set of TM;
  TCs = set of Char;
  TR  = record s: TMs; end;

var
  Calls: Integer;

function F: TMs;
begin
  Inc(Calls);
  F := [mA, mC];
end;

function FC: TCs;
begin
  FC := ['b', 'd'];
end;

function G: TMs;
begin
  G := [];
end;

type
  TBox = class
    function Members: TMs;
  end;

function TBox.Members: TMs;
begin
  Members := [mB, mD];
end;

var
  m: TM;
  ch: Char;
  r: TR;
  s: TMs;
  b: TBox;
  n: Integer;

begin
  Calls := 0;

  Write('A:');
  for m in F do Write(' ', Ord(m));
  WriteLn;

  Write('B:');
  for ch in FC do Write(' ', ch);
  WriteLn;

  r.s := [mB];
  Write('C:');
  for m in r.s do Write(' ', Ord(m));
  WriteLn;

  s := F;
  Write('D:');
  for m in s do Write(' ', Ord(m));
  WriteLn;

  { Row E: `Calls` is 2 at this point -- row A and the `s := F` of row D.
    A container evaluated per candidate element would read 5 after row A
    alone, and 256-wide for a set of Char. }
  WriteLn('E: calls=', Calls);

  b := TBox.Create;
  Write('G:');
  for m in b.Members do Write(' ', Ord(m));
  WriteLn;
  b.Free;

  { An EMPTY set result: the loop body must not run at all. The failure this
    guards against is a loop that runs once on a container it could not size. }
  n := 0;
  for m in G do Inc(n);
  WriteLn('H: empty=', n);
end.
