program test_cross_open_array_params;

type
  TKind = (kZero, kOne, kTwo);

var
  flags: array[0..2] of Boolean;
  kinds: array[0..2] of TKind;
  idxs: array[0..2] of Integer;

function Probe(const ptypes: array of TKind; const parr: array of Boolean;
  const pidx: array of Integer): Integer;
var
  j: Integer;
  r: Integer;
  ok: Boolean;
begin
  r := 0;
  j := pidx[1];
  ok := parr[j];
  if ok and (ptypes[j] = kOne) then r := 11;
  j := -1;
  if j < 0 then r := r + 1;
  Probe := r;
end;

begin
  flags[0] := False;
  flags[1] := True;
  flags[2] := False;
  kinds[0] := kZero;
  kinds[1] := kOne;
  kinds[2] := kTwo;
  idxs[0] := 0;
  idxs[1] := 1;
  idxs[2] := 2;
  writeln(Probe(kinds, flags, idxs));
end.
