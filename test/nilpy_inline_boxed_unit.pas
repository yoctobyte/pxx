{ SPDX-License-Identifier: Zlib }
unit nilpy_inline_boxed_unit;
{$MODE PXX}
{ Companion unit for test/test_nilpy_inline_boxed_args.npy: one-line leaf
  functions -- exactly what the -O2 inliner expands -- over each scalar
  parameter kind, plus a two-parameter one so the boxed argument is not only
  ever FIRST. }
interface
function id64(a: Int64): Int64;
function id32(a: Integer): Integer;
function idb(a: Byte): Integer;
function idw(a: Word): Integer;
function idbool(a: Boolean): Boolean;
function idd(a: Double): Double;
function sub2(a, b: Int64): Int64;
implementation
function id64(a: Int64): Int64; begin id64 := a; end;
function id32(a: Integer): Integer; begin id32 := a; end;
function idb(a: Byte): Integer; begin idb := a; end;
function idw(a: Word): Integer; begin idw := a; end;
function idbool(a: Boolean): Boolean; begin idbool := a; end;
function idd(a: Double): Double; begin idd := a; end;
function sub2(a, b: Int64): Int64; begin sub2 := a - b; end;
end.
