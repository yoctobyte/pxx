program test_paramless_method_as_const_byref_arg;
{ A bare parameterless METHOD passed as an argument to a call on a QUALIFIED
  receiver, where the parameter is by-ref because its TYPE is (a record or a
  string) and `const` because it is written const.

  `FE.MC(Cur)` reported `undefined variable (Cur)` for a perfectly good method
  of the enclosing class. Every other spelling of the same call compiled:

    q := Cur              assignment
    Own(Cur)              argument to an own unqualified method
    Free1(Cur)            argument to a free routine
    Cur.Row               field of the bare result
    FE.MC(Self.Cur)       explicit Self
    FE.MC(Cur)            <- ONLY THIS ONE

  so the affected path is exactly the argument list of a call on a qualified
  receiver — the one door with no implicit-Self arm anywhere on it. The real
  instance is fcl-passrc's `Engine.CreateElement(..., CurSourcePos, ...)` in
  pparser.pp, which is why this is a corpus fixture and not a curiosity.

  SIBLING, AND THE REASON THIS IS A SEPARATE FILE:
  test_paramless_fn_as_const_variant_arg.pas is the same defect one scope out —
  a FREE function name, gated to `const Variant`. That fix put the recognition
  in ByRefArgStartsExpression and gated it on ParamBindsAnExpression, and the
  gate then enumerated const TYPES one defect at a time: `const Variant`, then
  `const array of T`, then this. The predicate now asks `const`, which is the
  rule both instances were spelling out, and the METHOD lookup sits beside the
  free-function one in the same clause. Read the two files together.

  THE PRECEDENCE ROW IS LOAD-BEARING AND LOOKS REDUNDANT. `TFar` declares its
  own `Cur` as well, so `FE.MC(Cur)` has two readings and only one is right:
  the bare name is resolved on the ENCLOSING class, never on the receiver.
  Without that row a fix that looked the name up on the receiver would pass
  every other row here and be silently wrong — 7, not 99.

  NEGATIVE CONTROL lives in test_paramless_method_as_var_arg_refused.pas: a
  genuine `var` parameter must still refuse, because `const` accepting a value
  and `var` binding a variable are the two halves of one rule and widening the
  first must not widen the second.

  bug-p-a-parameterless-method-is-undefined-as-a-by-ref-argument
  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}
{$modeswitch advancedrecords}
type
  TPos = record Row: Integer; end;
  TFar = class
    function Cur: TPos;                          { the WRONG Cur — see above }
    procedure MC(const p: TPos);
    procedure MS(const s: AnsiString);
    procedure MTwo(n: Integer; const p: TPos);
    procedure MVal(n: Integer);
  end;
  TOwn = class
    FE: TFar;
    function Cur: TPos;
    function CurI: Integer;
    function CurS: AnsiString;
    function CurA: TPos;
    function Deft(k: Integer = 4): TPos;
    procedure Own(const p: TPos);
    procedure Go;
  end;

function TFar.Cur: TPos; begin Cur.Row := 99; end;
procedure TFar.MC(const p: TPos); begin WriteLn('mc      : ', p.Row); end;
procedure TFar.MS(const s: AnsiString); begin WriteLn('ms      : ', s); end;
procedure TFar.MTwo(n: Integer; const p: TPos); begin WriteLn('mtwo    : ', n, ' ', p.Row); end;
procedure TFar.MVal(n: Integer); begin WriteLn('mval    : ', n); end;

function TOwn.Cur: TPos; begin Cur.Row := 7; end;
function TOwn.CurI: Integer; begin CurI := 5; end;
function TOwn.CurS: AnsiString; begin CurS := 'text'; end;
function TOwn.CurA: TPos; begin CurA.Row := 11; end;
function TOwn.Deft(k: Integer = 4): TPos; begin Deft.Row := k; end;
procedure TOwn.Own(const p: TPos); begin WriteLn('own     : ', p.Row); end;

procedure Free1(const p: TPos); begin WriteLn('free    : ', p.Row); end;

procedure TOwn.Go;
var q: TPos;
begin
  { the spellings that already worked — regression guards, not decoration }
  q := Cur;                 WriteLn('assign  : ', q.Row);
  Own(Cur);
  Free1(Cur);
  WriteLn('field   : ', Cur.Row);
  FE.MC(Self.Cur);          { explicit Self }

  { the defect }
  FE.MC(Cur);               { <- 7, from TOwn, NOT 99 from TFar }
  FE.MTwo(1, Cur);          { second argument position }
  FE.MS(CurS);              { const AnsiString, by-ref for a different reason }
  FE.MC(Deft);              { all-defaulted is paramless at the call site }
  FE.MC(CurA);

  { by-VALUE never reached the by-ref arm and must not start }
  FE.MVal(CurI);
end;

var o: TOwn;
begin
  o := TOwn.Create;
  o.FE := TFar.Create;
  o.Go;
end.
