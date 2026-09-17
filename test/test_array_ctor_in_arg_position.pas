{ `[...]` in argument position: which overload takes it, and WHAT THE CALLEE SEES.

  THE LENGTH ASSERTIONS ARE THE TEST. Checking only which overload ran passes on
  the exact defect this file was written for: measured 2026-09-17, the call
  selected the RIGHT `array of AnsiString` candidate, returned fpc's own answer,
  and the callee read `Length(c)` = 17297991344808736 -- the set's 32-byte mask
  read as an array handle. A row that prints fpc's number while being wrong
  underneath is the expensive kind, so every array row here asserts the count and
  the elements, not the selection.

  THE SET ROWS ARE THE CONTROL AND THEY MUST NOT MOVE. fpc gives the SET the slot
  for an ordinal element list even against `array of Integer` (Q below), and a
  fix that lets the parameter type disambiguate in general regresses exactly
  that row while costing nothing today. It stays correct here structurally: the
  array reading is only ever reached on a failed match or after the match has
  already chosen an array parameter, so a matching set candidate is never
  displaced.

  THE METHOD SPELLING IS IN HERE ON PURPOSE. It already worked -- the bracket
  scoring table (BracketCandRank) is wired to the method path -- and the free
  spelling of the identical call did not. Holding both means a later change that
  re-breaks the free path cannot pass by fixing only the one everybody tests.

  Every expected value measured under fpc 3.2.2 with this same source.
  bug-p-an-array-constructor-in-argument-position-is-typed-as-a-set }
program test_array_ctor_in_arg_position;

type
  TF = set of (fA, fB);
  TCh = set of Char;

var ok, total: Integer;

procedure Chk(cond: Boolean; const what: AnsiString);
begin
  Inc(total);
  if cond then Inc(ok) else WriteLn('FAIL: ', what);
end;

var lastN: Integer; last0, last1: AnsiString;

procedure Note(const c: array of AnsiString);
begin
  lastN := Length(c);
  if lastN > 0 then last0 := c[0] else last0 := '';
  if lastN > 1 then last1 := c[1] else last1 := '';
end;

{ 1. the ticket's own repro: no set candidate anywhere }
function P(const c: AnsiString): Integer; overload;
begin P := 1; end;
function P(const c: array of AnsiString): Integer; overload;
begin Note(c); P := 2; end;

{ 2. the same pair with a trailing DEFAULT -- a different door entirely
     (TryFillTrailingDefaults), and the one that kept passing a set }
function D(const c: AnsiString; k: Integer = 0): Integer; overload;
begin D := 1; end;
function D(const c: array of AnsiString; k: Integer = 0): Integer; overload;
begin Note(c); D := 2; end;

{ 3. a SET candidate at the slot: it wins for what it can take }
function S(const c: TCh): Integer; overload;
begin S := 1; end;
function S(const c: array of AnsiString): Integer; overload;
begin Note(c); S := 2; end;

{ 4. THE MUST-NOT-MOVE ROW: ordinal elements, set beats array under fpc }
function Q(const c: TF): Integer; overload;
begin Q := 1; end;
function Q(const c: array of Integer): Integer; overload;
begin Q := 2; end;

{ 5. single candidates, both directions }
function ArrOnly(const c: array of AnsiString): Integer;
begin Note(c); ArrOnly := 2; end;
function SetOnly(const c: TCh): Integer;
begin SetOnly := 1; end;

type
  TC = class
    function M(const c: AnsiString): Integer; overload;
    function M(const c: array of AnsiString): Integer; overload;
  end;

function TC.M(const c: AnsiString): Integer; begin M := 1; end;
function TC.M(const c: array of AnsiString): Integer; begin Note(c); M := 2; end;

var o: TC;
begin
  ok := 0; total := 0;

  { --- the free path, no defaults --- }
  lastN := -1;
  Chk(P(['x']) = 2, 'free/no-default: the ARRAY overload takes a one-char literal');
  Chk(lastN = 1, 'free/no-default: the callee sees ONE element, not a set mask');
  Chk(last0 = 'x', 'free/no-default: and that element is the right string');

  lastN := -1;
  Chk(P(['x', 'yy']) = 2, 'free/no-default: mixed element widths');
  Chk(lastN = 2, 'free/no-default: two elements');
  Chk((last0 = 'x') and (last1 = 'yy'), 'free/no-default: both elements survive');

  { --- the free path THROUGH THE DEFAULT-FILL DOOR --- }
  lastN := -1;
  Chk(D(['x']) = 2, 'free/defaulted: the ARRAY overload takes it');
  Chk(lastN = 1, 'free/defaulted: the callee sees ONE element, not a set mask');
  Chk(last0 = 'x', 'free/defaulted: and that element is the right string');

  lastN := -1;
  Chk(D(['x', 'yy']) = 2, 'free/defaulted: mixed element widths');
  Chk(lastN = 2, 'free/defaulted: two elements');

  { --- a set candidate at the slot takes what it can --- }
  { `S(['xy'])` is NOT here: BOTH compilers refuse it -- fpc "Ordinal
    expression expected", pxx "set item must be one character" -- because the
    set candidate is tried against a literal it cannot hold. Parity, and it
    belongs in a refusal fixture rather than a running one. }
  Chk(S(['x']) = 1, 'a set-of-Char candidate wins a one-char literal');

  { --- THE CONTROL --- }
  Chk(Q([fA]) = 1, 'ORDINAL elements: the SET beats array of Integer (fpc''s rule)');

  { --- single candidates --- }
  lastN := -1;
  Chk(ArrOnly(['x']) = 2, 'a lone array candidate takes a SET-ABLE literal');
  Chk(lastN = 1, 'lone array candidate: one element');
  Chk(SetOnly(['x']) = 1, 'a lone set candidate still takes one');

  { --- the method spelling of the very first row --- }
  o := TC.Create;
  lastN := -1;
  Chk(o.M(['x']) = 2, 'METHOD spelling: the array overload, as it always did');
  Chk(lastN = 1, 'METHOD spelling: one element');

  WriteLn('total ok ', ok, ' / ', total);
end.
