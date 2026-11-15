{ --os=nt: dynlibs (LoadLibrary, GetProcedureAddress, UnloadLibrary) over
  Windows' loader. test-windows builds nt_dll_pascal_lib.dll next to this
  program first; msvcrt.dll is Windows' own. }
program test_nt_dynlibs;
uses dynlibs;
type
  TSum = function(n: Integer): Integer; cdecl;
  TMix = function(a: Int64; x: Double; b: Integer; y: Double; c, d, e, f: Int64): Double; cdecl;
  TStrLen = function(p: PChar): NativeInt; cdecl;
var h, c: TLibHandle; sum: TSum; mix: TMix; sl: TStrLen;
begin
  h := LoadLibrary('nt_dll_pascal_lib.dll');
  WriteLn('loaded ', h <> NilHandle);
  sum := TSum(GetProcedureAddress(h, 'pxx_sum'));
  mix := TMix(GetProcedureAddress(h, 'pxx_mix'));
  WriteLn('sum ', sum(10));
  WriteLn('mix ', mix(1, 0.5, 2, 0.25, 3, 4, 5, 6):0:2);
  WriteLn('missing ', GetProcedureAddress(h, 'nope') = nil);
  WriteLn('unload ', UnloadLibrary(h));
  c := LoadLibrary('msvcrt.dll');
  sl := TStrLen(GetProcedureAddress(c, 'strlen'));
  WriteLn('strlen ', sl('pascal'));
  WriteLn('bad ', LoadLibrary('no_such_library.dll') = NilHandle);
end.
