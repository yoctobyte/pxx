{$mode objfpc}
program test_a_var_dynarray_parameter_indexes_its_own_data;
{ riscv32 once took a var/out dyn-array parameter's slot (the address of the
  caller's variable) as the data pointer: stores were lost, reads gave 0.
  Every shape from the report, plus out + SetLength and @f[i]. }
type TFrame = array of Byte;
     TIA = array of Integer;
procedure A(var f: TFrame; px: Integer; v: Integer); begin f[px*3] := v; end;
procedure B(var f: TFrame; v: Integer); begin f[6] := v; end;
procedure C(var f: TFrame; px: Integer; v: Integer); var i: Integer; begin i := px*3; f[i] := v; end;
procedure D(f: TFrame; px: Integer; v: Integer); begin f[px*3] := v; end;
procedure E(var f: TIA; px: Integer; v: Integer); begin f[px*3] := v; end;
procedure F2(var f: TFrame; px: Integer; v: Byte); begin f[px*3] := v; end;
function R(var f: TFrame; i: Integer): Integer; begin Result := f[i]; end;
procedure O(out f: TIA; n: Integer); var i: Integer; begin SetLength(f, n); for i := 0 to n - 1 do f[i] := i * i; end;
procedure V(var f: TFrame; n: Integer); begin SetLength(f, n); f[n - 1] := 99; end;
procedure P(var f: TFrame); var p: PByte; begin p := @f[0]; p[5] := 55; p := @f[10]; p^ := 66; end;
var f: TFrame; g, h: TIA; i, sum: Integer;
begin
  SetLength(f, 90); SetLength(g, 90);
  A(f, 2, 7); write('A=', f[6]);
  B(f, 8); write(' B=', f[6]);
  C(f, 2, 9); write(' C=', f[6]);
  D(f, 2, 10); write(' D=', f[6]);
  E(g, 2, 11); write(' E=', g[6]);
  F2(f, 2, 12); write(' F=', f[6]);
  f[6] := 13; writeln(' direct=', f[6]);
  f[40] := 41; writeln('R=', R(f, 40), ' R0=', R(f, 0));
  O(h, 7); sum := 0; for i := 0 to High(h) do sum := sum + h[i]; writeln('O len=', Length(h), ' sum=', sum);
  V(f, 120); writeln('V len=', Length(f), ' last=', f[119], ' kept=', f[40]);
  P(f); writeln('P=', f[5], ' ', f[10]);
end.
