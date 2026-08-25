program test_generic_float_type_argument_delphi;
{ The mode-delphi half of test_generic_float_type_argument.pas: no
  `generic`/`specialize` markers, so DelphiRewriteGenericUses mints the concrete
  name from the `<...>` group itself. It carried its OWN copy of the "which
  tokens may stand as a concrete type argument" list — one of the three that all
  named exactly Integer/Boolean/Char/String — so `TBox<Double>` was silently not
  rewritten and failed later, on a different line, as an unknown type.

  A separate FILE and not a second section: FPC takes a mode directive only ahead of the
  first declaration, so the two spellings cannot share a program.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode delphi}
type
  TDBox<T> = class
    V: T;
    procedure Put(x: T);
    function Get: T;
    function Doubled: T;
  end;

  TDPair<K, V> = class
    A: K;
    B: V;
    procedure Put(x: K; y: V);
  end;

  TDBoxD = TDBox<Double>;
  TDBoxS = TDBox<Single>;
  TDBoxE = TDBox<Extended>;
  TDBoxI = TDBox<Integer>;
  TDPairDI = TDPair<Double, Integer>;

procedure TDBox<T>.Put(x: T); begin V := x; end;
function TDBox<T>.Get: T; begin Result := V; end;
function TDBox<T>.Doubled: T; begin Result := V + V; end;
procedure TDPair<K, V>.Put(x: K; y: V); begin A := x; B := y; end;

var
  bd: TDBoxD; bs: TDBoxS; be: TDBoxE; bi: TDBoxI;
  pdi: TDPairDI;
begin
  bd := TDBoxD.Create; bd.Put(3.125);
  WriteLn('double   ', bd.Get:0:4, ' ', bd.Doubled:0:4);

  bs := TDBoxS.Create; bs.Put(0.75);
  WriteLn('single   ', bs.Get:0:4, ' ', bs.Doubled:0:4);

  be := TDBoxE.Create; be.Put(6.5);
  WriteLn('extended ', be.Get:0:4, ' ', be.Doubled:0:4);

  bi := TDBoxI.Create; bi.Put(11);
  WriteLn('integer  ', bi.Get, ' ', bi.Doubled);

  pdi := TDPairDI.Create; pdi.Put(1.25, 7);
  WriteLn('pair     ', pdi.A:0:4, ' ', pdi.B);

  WriteLn('sizes    ', SizeOf(bd.V), ' ', SizeOf(bs.V), ' ', SizeOf(bi.V));
end.
