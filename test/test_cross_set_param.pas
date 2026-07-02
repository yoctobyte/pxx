{ SPDX-License-Identifier: MPL-2.0 }
{ By-value set parameters (32-byte sets) across a call + record-field set
  round-trip. riscv32 marshalled the set's ADDRESS as one arg word while the
  callee read its own 32-byte slot as set bytes — chess MakeMove/UnmakeMove saw
  phantom move flags and perft counted 164 instead of 20.
  See bug-riscv32-chess-perft-runtime-corruption. }
program TestCrossSetParam;
type
  TF = (fA, fB, fC, fD, fE, fF);
  TFS = set of TF;
  TR = record x: Integer; s: TFS; end;

function Mk(x: Integer; s: TFS): TR;
begin
  Mk.x := x;
  Mk.s := s;
end;

function CountIn(s: TFS): Integer;
var f: TF; n: Integer;
begin
  n := 0;
  for f := fA to fF do
    if f in s then n := n + 1;
  CountIn := n;
end;

var r: TR;
begin
  r := Mk(7, []);
  writeln('empty: ', fF in r.s, ' ', fA in r.s, ' n=', CountIn(r.s));
  r := Mk(8, [fB, fF]);
  writeln('bf: ', fB in r.s, ' ', fF in r.s, ' ', fA in r.s, ' n=', CountIn(r.s));
  r := Mk(9, [fA, fC, fE]);
  writeln('ace: ', fA in r.s, ' ', fC in r.s, ' ', fE in r.s, ' ', fB in r.s, ' n=', CountIn(r.s));
end.
