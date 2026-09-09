{ Two ARRAY parameters competing for one `[...]` argument slot.

  Selection could not separate them and fell through to arity, i.e. to
  first-declared: `c.P2(2, [7, 8])` against `P2(N; A: array of Integer)` and
  `P2(N; A: array of const)` ran the Integer body where fpc runs the
  array-of-const one, and reversing the two declarations reversed pxx's answer.
  The probe cannot rank them because it cannot PARSE a bracket argument at all
  -- there is no parameter to bind against, so ParseArgExpr reads the '[' as a
  set literal and Error halts, leaving no element type to rank with.

  THE ANSWER NEEDS NO ARGUMENT TYPES, which is what makes it available without
  fixing the probe: fpc prefers `array of const` at a bracket slot
  UNCONDITIONALLY. Measured 2026-09-09 against fpc 3.2.2 in BOTH declaration
  orders against `array of Integer`, `array of string`, `array of Double` and
  `array of Byte`, with element lists of integers, strings, floats and an empty
  `[]` -- array-of-const wins every one. It wins even where the
  elements could not convert to the other candidate's element type, so this is a
  rule about the PARAMETER and not about the literal.

  EVERY FAMILY APPEARS IN BOTH ORDERS. A one-order fixture cannot fail this bug,
  because first-declared is right half the time by construction -- and that is
  visible in the control: against the PINNED pre-fix compiler exactly 5 of these
  12 rows move, and they are exactly the ones whose `array of const` arm is
  declared SECOND. The other seven read the same before and after and are here
  so a fix that simply always picked array-of-const could not pass either.

  BOTH ADDRESSES. The method door is FindUMethOverloadAhead's bracket narrowing;
  the constructor door is ClassCtorArraySigAt, which chooses how the `[...]` is
  PARSED before any overload resolution can run. Both took the first array
  candidate; both now take an `array of const` one first. A fixture covering
  only the method half would have left the ctor half silently wrong, and the two
  live in different functions.

  The `sole` rows are the guard in the other direction: with ONE array candidate
  the narrowing already had the answer and took it, and that path must not move.
  The `veto` row is the second one: a `tySet` parameter at the bracket slot
  means the `[...]` really may be a set, so the narrowing declines outright and
  the old arity behaviour stands -- the fix must not overrule that veto.

  READ THE `veto` ROW'S EXPECTED VALUE CAREFULLY: it is PXX's OWN ANSWER AND IT
  DIVERGES FROM FPC. Every other line in the .expected is fpc 3.2.2's output;
  that one is not. fpc resolves `ve.P(2, [7, 8])` to the `set` overload and pxx
  runs the array one, because pxx's veto declines to narrow at all and falls
  back to first-declared. Measured while writing this fixture, filed as
  bug-p-a-set-candidate-at-a-bracket-slot-vetoes-the-narrowing-instead-of-winning-it,
  and deliberately NOT fixed here -- guessing the other way would break a
  working call to buy this one, which is the veto's own stated reason. The row
  is here so the veto path is guarded: a later change that overruled it would
  silently start picking the array where the set is meant, and nothing else in
  the tree mixes the two.

  STILL OPEN and deliberately not covered here: two NON-const arrays differing
  only in element type. fpc ranks those by element (`[7, 8]` takes
  `array of Integer` over `array of string` in both orders) and that genuinely
  needs the probe. pxx refuses one of those two orders outright today, on the
  pinned compiler as well, so it is pre-existing and separately filed.
  bug-p-two-array-parameters-at-one-bracket-slot-are-decided-by-declaration-order }
program test_p_an_array_of_const_wins_a_bracket_argument;
{$mode objfpc}
type
  TByteSet = set of Byte;   { fpc wants a NAMED set type in a parameter list }
  TIntFirst = class
    procedure P(N: Integer; A: array of Integer); overload;
    procedure P(N: Integer; A: array of const); overload;
  end;
  TVrFirst = class
    procedure P(N: Integer; A: array of const); overload;
    procedure P(N: Integer; A: array of Integer); overload;
  end;
  TStrFirst = class
    procedure P(N: Integer; A: array of string); overload;
    procedure P(N: Integer; A: array of const); overload;
  end;
  TDblFirst = class
    procedure P(N: Integer; A: array of Double); overload;
    procedure P(N: Integer; A: array of const); overload;
  end;
  TSole = class
    procedure P(N: Integer; A: array of Integer); overload;
    procedure P(N: Integer; A: Boolean); overload;
  end;
  TVeto = class
    procedure P(N: Integer; A: array of Integer); overload;
    procedure P(N: Integer; A: TByteSet); overload;
  end;

  { THE CONSTRUCTOR HALF. Same property, second address: the bracket door on the
    ctor path is ClassCtorArraySigAt, which took the FIRST constructor declaring
    an array at the slot and so decided by declaration order too. The `ints`
    bodies SUM their elements rather than counting them, deliberately: a count
    reads the same whether the bracket was parsed as an Integer vector or as a
    TVarRec one, and the sum does not. `ctsole` is the guard for the fix that
    put the two-armed question here in the first place -- one array candidate,
    `array of Integer`, must still be parsed with an Integer stride (sum 60, not
    10). }
  TCIntFirst = class
    constructor Create(const A: array of Integer); overload;
    constructor Create(const A: array of const); overload;
  end;
  TCVrFirst = class
    constructor Create(const A: array of const); overload;
    constructor Create(const A: array of Integer); overload;
  end;
  TCSole = class
    constructor Create(const A: array of Integer);
  end;

procedure TIntFirst.P(N: Integer; A: array of Integer); begin WriteLn('intfirst  ints  cnt=', Length(A)); end;
procedure TIntFirst.P(N: Integer; A: array of const);   begin WriteLn('intfirst  vr    cnt=', Length(A)); end;
procedure TVrFirst.P(N: Integer; A: array of const);    begin WriteLn('vrfirst   vr    cnt=', Length(A)); end;
procedure TVrFirst.P(N: Integer; A: array of Integer);  begin WriteLn('vrfirst   ints  cnt=', Length(A)); end;
procedure TStrFirst.P(N: Integer; A: array of string);  begin WriteLn('strfirst  strs  cnt=', Length(A)); end;
procedure TStrFirst.P(N: Integer; A: array of const);   begin WriteLn('strfirst  vr    cnt=', Length(A)); end;
procedure TDblFirst.P(N: Integer; A: array of Double);  begin WriteLn('dblfirst  dbls  cnt=', Length(A)); end;
procedure TDblFirst.P(N: Integer; A: array of const);   begin WriteLn('dblfirst  vr    cnt=', Length(A)); end;
procedure TSole.P(N: Integer; A: array of Integer);     begin WriteLn('sole      ints  cnt=', Length(A)); end;
procedure TSole.P(N: Integer; A: Boolean);              begin WriteLn('sole      bool  ', A); end;
procedure TVeto.P(N: Integer; A: array of Integer);     begin WriteLn('veto      ints  cnt=', Length(A)); end;
procedure TVeto.P(N: Integer; A: TByteSet);          begin WriteLn('veto      set'); end;

function SumOf(const A: array of Integer): Integer;
var i: Integer;
begin
  SumOf := 0;
  for i := 0 to High(A) do SumOf := SumOf + A[i];
end;

constructor TCIntFirst.Create(const A: array of Integer); begin WriteLn('ctintfirst ints sum=', SumOf(A)); end;
constructor TCIntFirst.Create(const A: array of const);   begin WriteLn('ctintfirst vr   cnt=', Length(A)); end;
constructor TCVrFirst.Create(const A: array of const);    begin WriteLn('ctvrfirst  vr   cnt=', Length(A)); end;
constructor TCVrFirst.Create(const A: array of Integer);  begin WriteLn('ctvrfirst  ints sum=', SumOf(A)); end;
constructor TCSole.Create(const A: array of Integer);     begin WriteLn('ctsole     ints sum=', SumOf(A)); end;

var
  ai: TIntFirst; av: TVrFirst; asx: TStrFirst; ad: TDblFirst; so: TSole; ve: TVeto;
  ci: TCIntFirst; cv: TCVrFirst; cs: TCSole;
begin
  ai := TIntFirst.Create; av := TVrFirst.Create; asx := TStrFirst.Create;
  ad := TDblFirst.Create; so := TSole.Create;    ve := TVeto.Create;

  ai.P(2, [7, 8]);
  av.P(2, [7, 8]);
  ai.P(2, []);
  av.P(2, []);
  asx.P(2, ['a', 'b']);
  ad.P(2, [1.5, 2.5]);
  so.P(2, [7, 8]);
  so.P(2, True);
  ve.P(2, [7, 8]);

  ci := TCIntFirst.Create([10, 20, 30]);
  cv := TCVrFirst.Create([10, 20, 30]);
  cs := TCSole.Create([10, 20, 30]);
end.
