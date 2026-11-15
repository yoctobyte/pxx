{ --os=nt: dynlibs (LoadLibrary, GetProcedureAddress, UnloadLibrary) over
  Windows' loader. test-windows builds nt_dll_pascal_lib.dll next to this
  program first; msvcrt.dll and kernel32.dll are Windows' own: ldexp mixes a float and
  an integer argument, MulDiv is called through a stdcall procedure type. }
program test_nt_dynlibs;
uses dynlibs;
type
  TSum = function(n: Integer): Integer; cdecl;
  TMix = function(a: Int64; x: Double; b: Integer; y: Double; c, d, e, f: Int64): Double; cdecl;
  TStrLen = function(p: PChar): NativeInt; cdecl;
  TLdexp = function(x: Double; e: Integer): Double; cdecl;
  TMulDiv = function(a, b, c: Integer): Integer; stdcall;

{ the program's own stdcall routine: its address is its Microsoft-convention
  adapter, which the same procedure type calls }
function MyMulDiv(a, b, c: Integer): Integer; stdcall;
begin
  Result := a * b div c + 1;
end;

var h, c, k: TLibHandle; sum: TSum; mix: TMix; sl: TStrLen; ld: TLdexp; md: TMulDiv;
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
  ld := TLdexp(GetProcedureAddress(c, 'ldexp'));
  WriteLn('ldexp ', ld(1.5, 4):0:1);
  k := LoadLibrary('kernel32.dll');
  md := TMulDiv(GetProcedureAddress(k, 'MulDiv'));
  WriteLn('muldiv ', md(300, 7, 2));
  md := @MyMulDiv;
  WriteLn('own ', md(300, 7, 2));
  WriteLn('bad ', LoadLibrary('no_such_library.dll') = NilHandle);
end.
