{ SPDX-License-Identifier: MPL-2.0 }
{ Phase 2 slice oracle. One source, two roles:
    - built natively (no define) it PRINTS the answers;
    - built with -dWASM_NOMAIN it has an empty main, so the wasm backend only
      has to handle the function bodies, not writeln — which is Phase 6.
  The harness calls the exported functions under node and compares. }
program Phase2Slice;

function AddMul(a, b: Integer): Integer;
begin
  AddMul := a * b + 7;
end;

function Chain(x: Integer): Integer;
var t: Integer;
begin
  t := x + 1;
  t := t * t;
  Chain := t - x;
end;

{$ifndef WASM_NOMAIN}
begin
  writeln(AddMul(3, 4));
  writeln(AddMul(-2, 5));
  writeln(Chain(6));
  writeln(Chain(0));
end.
{$else}
begin
end.
{$endif}
