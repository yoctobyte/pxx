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

  THE `veto` ROW USED TO BE THE ONE DIVERGENT LINE IN THIS FILE AND IS NOT ANY
  MORE -- every line is fpc 3.2.2's now. Its expected value was pxx's OWN answer
  (`veto ints cnt=2`), loudly labelled, because a `tySet` parameter at the
  bracket slot made the narrowing decline outright and fall back to
  first-declared, where fpc resolves `ve.P(2, [7, 8])` to the `set` overload.
  Fixed 2026-09-09 once the elements could be classified: an ordinal element
  list gives the set the slot, which is fpc's measured rule in both declaration
  orders, and the veto still stands for every list that cannot be classified --
  which is the case its own reasoning was about.
  bug-p-a-set-candidate-at-a-bracket-slot-vetoes-the-narrowing-instead-of-winning-it

  THAT ROW IS WHY THE FILE WAS WORTH ITS RUNTIME TWICE. It was put in as an
  inert must-not-move control, diffed against fpc out of habit, and turned out
  to be a divergence -- a control is asserted against ITSELF, so it records our
  answer where a reader expects the right one. It then sat here as a pinned
  divergence for exactly as long as it took to measure the rule, which is the
  argument for pinning one loudly rather than leaving it unwritten.

  ALSO CLOSED SINCE, and covered by its own fixture
  test_p_a_bracket_slot_is_ranked_by_what_its_elements_are rather than here: two
  NON-const arrays differing only in element type. The paragraph below was
  written when that was open, and its reasoning -- "that genuinely needs the
  probe" -- was the wrong blocker. fpc ranks by the elements' CLASS, which is
  readable from the tokens; no parse is needed. Kept as written because the
  mistake is the useful part.

  STILL OPEN when this was written: two NON-const arrays differing
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
  { A DIFFERENTLY-NAMED CONSTRUCTOR MUST NOT TAKE THE SLOT, and these two rows
    exist because the rule above took it. fpc's preference is between
    OVERLOADS -- `Create` and `CreateV` are two names -- and the routine that
    implements it scanned every constructor of the class, which was harmless
    while first-match ran and became a wrong parse the moment array-of-const
    started winning: `TCNamed.Create([10, 20, 30])` found `CreateV` and built a
    TVarRec vector the Integer body read with the wrong stride, sum 10 for
    fpc's 60. Both declaration orders, because the arrangement that broke had
    `Create` FIRST and the scan reached past it anyway. }
  TCNamed = class
    constructor Create(const A: array of Integer);
    constructor CreateV(const A: array of const);
  end;
  TCNamedVrFirst = class
    constructor CreateV(const A: array of const);
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
constructor TCNamed.Create(const A: array of Integer);    begin WriteLn('ctnamed    ints sum=', SumOf(A)); end;
constructor TCNamed.CreateV(const A: array of const);    begin WriteLn('ctnamed    vr   cnt=', Length(A)); end;
constructor TCNamedVrFirst.CreateV(const A: array of const);  begin WriteLn('ctnamedvrf vr   cnt=', Length(A)); end;
constructor TCNamedVrFirst.Create(const A: array of Integer); begin WriteLn('ctnamedvrf ints sum=', SumOf(A)); end;

var
  ai: TIntFirst; av: TVrFirst; asx: TStrFirst; ad: TDblFirst; so: TSole; ve: TVeto;
  ci: TCIntFirst; cv: TCVrFirst; cs: TCSole; cn: TCNamed; cnv: TCNamedVrFirst;
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
  cn := TCNamed.Create([10, 20, 30]);
  cnv := TCNamedVrFirst.Create([10, 20, 30]);
end.
