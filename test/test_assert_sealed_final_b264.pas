program test_assert_sealed_final_b264;
{ Three FPC/Delphi surfaces that did not parse or exist:

  - `class sealed` / `class abstract` — Delphi class modifiers between `class` and the
    heritage list. pxx enforces neither (sealed forbids descendants, abstract forbids
    instantiation; nothing else here is enforced), so they are parse-and-ignore.
    Unconsumed, `sealed` was read as the heritage and the declaration desynced.

  - `final` on a method — seals a virtual against further override. Parse-and-ignore for
    the same reason; unconsumed it desynced the member loop.

  - System.Assert(cond[, msg]) did not exist at all. Reached through a parser soft-alias
    (bare `Assert(` -> a hidden __pxxAssert), the same discipline Move/FillChar use, so NO
    real proc named Assert exists to shadow a user's own — which is checked below,
    because getting that wrong would silently hijack their code. On failure it reports and
    halts with 227, FPC's assertion runtime error. Both arities work, via a defaulted
    message parameter. }
type
  TA = class
    procedure G; virtual;
  end;

  TB = class(TA)
    procedure G; override; final;      { `final` }
  end;

  TS = class sealed                    { `class sealed` }
    procedure H;
  end;

  TAb = class abstract (TA)            { `class abstract` }
  end;

procedure TA.G; begin writeln('A'); end;
procedure TB.G; begin writeln('B'); end;
procedure TS.H; begin writeln('S'); end;

var
  a: TA;
  s: TS;
  n: Integer;
begin
  a := TB.Create;
  a.G;                       { virtual dispatch must still be right: B }
  s := TS.Create;
  s.H;

  n := 5;
  Assert(n = 5);                          { passes, silent }
  Assert(n > 0, 'n must be positive');    { passes, silent }
  writeln('asserts-passed');
end.
