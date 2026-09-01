program test_variadic_elision_methods;
{ Variadic bracket-elision for METHOD calls: `g.Log('x=', x)` against
  `procedure TLogger.Log(const a: array of const)`.
  The method slice of feature-writeln-as-library.

  THE LOAD-BEARING ROWS ARE THE `same-as-brackets` PAIRS, exactly as in
  test_variadic_bracket_elision.pas. Every other row could be satisfied by an
  absorb that builds a subtly different AN_VARREC_ARRAY -- a wrong element tag,
  a dropped or duplicated element, the fixed parameters shifted by one -- and
  would still print something plausible. Comparing the elided call against the
  EXPLICITLY BRACKETED call of the same method is what pins the two spellings
  to one node builder.

  WHY THE SHAPES ARE ENUMERATED. The bare-routine slice hooks ONE resolver.
  The method paths do not use it: `mpi` is bound by name on the class and the
  arguments are parsed slot by slot by SEVEN separate argument loops that share
  only their tail, ExpectCallRParen. A fix that reached one loop and not the
  others would pass a single-shape test and leave the rest reporting `wrong
  number of parameters`. So each row below is a different loop or a different
  entry into one: statement vs expression position, instance vs class method,
  virtual dispatch, a chained selector, and fixed parameters ahead of the
  vector. }

uses sysutils;

var bad: Integer;

function Desc(const a: array of const): string;
{ Element TAGS, not values -- the tag is what an absorb can silently get wrong. }
var i: Integer; s: string;
begin
  s := '';
  for i := 0 to High(a) do
  begin
    if i > 0 then s := s + ',';
    case a[i].VType of
      0:  s := s + 'i';
      1:  s := s + 'b';
      2:  s := s + 'c';
      3:  s := s + 'f';
      11: s := s + 's';
      16: s := s + 'I';
    else  s := s + '?';
    end;
  end;
  Desc := s;
end;

type
  TLogger = class
    function D(const a: array of const): string; virtual;
    function DAt(lvl: Integer; const a: array of const): string;
    class function CD(const a: array of const): string;
    function Fwd(const a: array of const): string;
    procedure P(const a: array of const);
  end;

  TSubLogger = class(TLogger)
    function D(const a: array of const): string; override;
  end;

  THolder = class
    log: TLogger;
  end;

var lastP: string;

function TLogger.D(const a: array of const): string;
begin
  Result := Desc(a);
end;

function TLogger.DAt(lvl: Integer; const a: array of const): string;
begin
  Result := IntToStr(lvl) + ':' + Desc(a);
end;

class function TLogger.CD(const a: array of const): string;
begin
  Result := 'C' + Desc(a);
end;

function TLogger.Fwd(const a: array of const): string;
begin
  Result := Self.D(a);   { forwards the SAME vector -- must not become D([a]) }
end;

procedure TLogger.P(const a: array of const);
begin
  lastP := Desc(a);
end;

function TSubLogger.D(const a: array of const): string;
begin
  Result := 'S' + Desc(a);
end;

procedure Chk(const name, got, want: string);
begin
  if got = want then WriteLn('ok   ', name, ' = ', got)
  else begin WriteLn('FAIL ', name, ' got [', got, '] want [', want, ']'); Inc(bad); end;
end;

var g: TLogger; sub: TSubLogger; base: TLogger; h: THolder; s1, s2: string;
begin
  bad := 0;
  g := TLogger.Create;

  { --- the load-bearing pairs: elided must equal bracketed, same method --- }
  Chk('expr-same-as-brackets',  g.D('aa', 1, 'c'),     g.D(['aa', 1, 'c']));
  { 'aa' boxes as vtAnsiString and 'c' as vtChar: a ONE-character literal is a
    Char in this dialect, which is not a bug and is asserted so the next reader
    does not "fix" it. Both spellings must agree on it. }
  Chk('expr-tags',              g.D('aa', 1, 'c'),     's,i,c');

  { statement position goes through a different loop than expression position }
  g.P(['aa', 1]);         s1 := lastP;
  g.P('aa', 1);           s2 := lastP;
  Chk('stmt-same-as-brackets',  s2, s1);
  Chk('stmt-tags',              s2, 's,i');

  { fixed parameters ahead of the vector must stay bound to their own slots --
    an absorb that started one slot early would fold `7` into the vector }
  Chk('fixed-same-as-brackets', g.DAt(7, 'aa', 1),     g.DAt(7, ['aa', 1]));
  Chk('fixed-tags',             g.DAt(7, 'aa', 1),     '7:s,i');

  { a class method resolves through GenMakeStaticMethodCall, a seventh loop }
  Chk('class-same-as-brackets', TLogger.CD('aa', 1),   TLogger.CD(['aa', 1]));
  Chk('class-tags',             TLogger.CD('aa', 1),   'Cs,i');

  { virtual dispatch: the override must receive the same vector }
  sub := TSubLogger.Create;
  base := sub;
  Chk('virt-same-as-brackets',  base.D('aa', 1),       base.D(['aa', 1]));
  Chk('virt-tags',              base.D('aa', 1),       'Ss,i');

  { a chained selector reaches the call through the lvalue path }
  h := THolder.Create;
  h.log := g;
  Chk('chain-same-as-brackets', h.log.D('aa', 1),      h.log.D(['aa', 1]));
  Chk('chain-tags',             h.log.D('aa', 1),      's,i');

  { THE SINGLE-ELEMENT ROW IS THE MOST VALUABLE ONE HERE. Before this slice
    `g.D('only')` compiled cleanly and SEGFAULTED at run time -- the method
    loops did not know `array of const`, so a scalar was passed where a vector
    was required with no diagnostic. Verified on the PINNED compiler, so it is
    pre-existing, not a regression this work introduced. It also carries no
    comma, which is why the absorb cannot be gated on seeing a surplus. }
  Chk('one-elem-same-as-brackets', g.D('only'),        g.D(['only']));
  Chk('one-elem-tags',          g.D('only'),           's');
  Chk('empty-still-brackets',   g.D([]),               '');

  { every element type, so a tag that survives only for strings is caught }
  Chk('all-tags',               g.D('ss', 1, True, 'c', 2.5), 's,i,b,c,f');

  { PASS-THROUGH IS THE CONTROL THAT MUST NOT CHANGE. Forwarding an existing
    vector has to stay a forward and must never be wrapped into a vector of one
    vector -- which would print `?` here rather than the elements. }
  Chk('passthrough-fwd',        g.Fwd(['aa', 1]),      's,i');
  Chk('passthrough-eq-direct',  g.Fwd(['aa', 1]),      g.D(['aa', 1]));

  h.Free; sub.Free; g.Free;
  if bad = 0 then WriteLn('METHOD ELISION OK')
  else WriteLn('METHOD ELISION FAILED ', bad);
end.
