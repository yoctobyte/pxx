program test_generic_float_type_argument;
{ A FLOAT may be a generic type argument.

  Three copies of the "which tokens may stand as a concrete type argument" list
  named exactly Integer/Boolean/Char/String, so every float was refused:
  `specialize TBox<Double>` was "expected concrete type name" while
  `specialize TBox<Integer>` and even `<string>` worked. The builtin type names
  the lexer gives their own token kind (Real, LongWord, Single, Double,
  Extended) had simply never been added — the same token-kinds-vs-names split
  IsMethodNameTok's comment describes.

  This is NOT Track F: the mechanism is the generics substitution, the datatype
  is incidental (CLAUDE.md — rank the mechanism, never the datatype).

  The objfpc `generic`/`specialize` spelling: arithmetic and ordering inside the
  template, integer and LongWord arms beside the float arms so the substitution
  is shown to still discriminate, and the two-parameter mixed case. The
  mode-delphi spelling — which carried its OWN copy of the token list — is
  test_generic_float_type_argument_delphi.pas.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}
type
  generic TPair<_T> = class
    A, B: _T;
    procedure SetIt(x, y: _T);
    function Sum: _T;
    function Larger: _T;
  end;

  generic TMix<_K, _V> = class
    K: _K;
    V: _V;
    procedure SetIt(ak: _K; av: _V);
    function Describe: string;
  end;

  TPairD  = specialize TPair<Double>;
  TPairS  = specialize TPair<Single>;
  TPairR  = specialize TPair<Real>;
  TPairE  = specialize TPair<Extended>;
  TPairI  = specialize TPair<Integer>;
  TPairW  = specialize TPair<LongWord>;
  TMixIS  = specialize TMix<Integer, Single>;
  TMixDW  = specialize TMix<Double, LongWord>;

procedure TPair.SetIt(x, y: _T); begin A := x; B := y; end;
function TPair.Sum: _T; begin Result := A + B; end;
function TPair.Larger: _T; begin if A > B then Result := A else Result := B; end;

procedure TMix.SetIt(ak: _K; av: _V); begin K := ak; V := av; end;
function TMix.Describe: string; begin Result := 'pair'; end;

var
  pd: TPairD; ps: TPairS; pr: TPairR; pe: TPairE;
  pi: TPairI; pw: TPairW;
  mis: TMixIS; mdw: TMixDW;
begin
  pd := TPairD.Create; pd.SetIt(1.5, 2.25);
  WriteLn('double  ', pd.Sum:0:4, ' ', pd.Larger:0:4);

  ps := TPairS.Create; ps.SetIt(0.5, 0.125);
  WriteLn('single  ', ps.Sum:0:4, ' ', ps.Larger:0:4);

  pr := TPairR.Create; pr.SetIt(2.5, 0.75);
  WriteLn('real    ', pr.Sum:0:4, ' ', pr.Larger:0:4);

  pe := TPairE.Create; pe.SetIt(4.25, 8.5);
  WriteLn('extended', pe.Sum:0:4, ' ', pe.Larger:0:4);

  pi := TPairI.Create; pi.SetIt(3, 9);
  WriteLn('integer ', pi.Sum, ' ', pi.Larger);

  pw := TPairW.Create; pw.SetIt(4000000000, 7);
  WriteLn('longword ', pw.Sum, ' ', pw.Larger);


  mis := TMixIS.Create; mis.SetIt(7, 0.25);
  WriteLn('mix-is  ', mis.K, ' ', mis.V:0:4, ' ', mis.Describe);

  mdw := TMixDW.Create; mdw.SetIt(0.75, 12);
  WriteLn('mix-dw  ', mdw.K:0:4, ' ', mdw.V, ' ', mdw.Describe);

  WriteLn('sizes   ', SizeOf(pd.A), ' ', SizeOf(ps.A), ' ', SizeOf(pi.A));
end.
