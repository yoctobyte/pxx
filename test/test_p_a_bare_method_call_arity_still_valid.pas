{ The must-NOT-break direction of the bare-method-call arity check.

  A rejection test alone passes just as well if the check is far too strict, and
  three shapes here have real regression risk, each for a different reason:

    * TRAILING DEFAULTS -- `Def(1)` supplies one of two parameters and is legal,
      so an arity gate that compares counts naively deletes it.
    * THE VARIADIC `array of const` TAIL -- `Desc('a', 1)` passes MORE explicit
      arguments than the signature has parameters, ON PURPOSE
      (feature-writeln-as-library). fpc REFUSES that source, so a gate written
      from fpc's answer alone would have removed a pxx extension silently. It
      reaches this site through the very fallback the check closes, which is why
      UMethNameCanAbsorbVarRecTail exists. The bracketed spelling `Desc([...])`
      is here too because only that one runs correctly today; the elided
      spelling is separately broken at this door and is deliberately not
      exercised.
    * INHERITED and OVERLOADED methods -- the arity question is asked of the
      whole visible set walking the parent chain, not of one candidate.

  bug-p-a-bare-method-call-inside-its-own-class-ignores-arity }
program test_p_a_bare_method_call_arity_still_valid;
{$mode objfpc}
type
  TBase = class
    procedure Inh(a: Integer);
  end;
  TC = class(TBase)
    procedure Plain(x: Double);
    procedure Def(a: Integer; b: Integer = 9);
    procedure Nul;
    procedure Ovl(a: Integer); overload;
    procedure Ovl(a, b: Integer); overload;
    procedure Desc(const a: array of const);
    procedure Go;
  end;

procedure TBase.Inh(a: Integer); begin WriteLn('inh ', a); end;
procedure TC.Plain(x: Double); begin WriteLn('plain ', x:0:1); end;
procedure TC.Def(a: Integer; b: Integer = 9); begin WriteLn('def ', a, ' ', b); end;
procedure TC.Nul; begin WriteLn('nul'); end;
procedure TC.Ovl(a: Integer); begin WriteLn('ovl1 ', a); end;
procedure TC.Ovl(a, b: Integer); begin WriteLn('ovl2 ', a, ' ', b); end;
procedure TC.Desc(const a: array of const);
var i: Integer;
begin
  Write('desc n=', Length(a), ':');
  for i := 0 to High(a) do
    case a[i].VType of
      vtInteger:    Write(' int=', a[i].VInteger);
      vtChar:       Write(' chr=', a[i].VChar);
    else            Write(' ?');
    end;
  WriteLn;
end;

procedure TC.Go;
begin
  Plain(1.5);
  Def(1);
  Def(1, 2);
  Nul;
  Ovl(3);
  Ovl(3, 4);
  Inh(5);
  Desc(['a', 1]);
  Desc([]);
end;

var c: TC;
begin
  c := TC.Create;
  c.Go;
end.
