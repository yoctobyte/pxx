program test_nt_dll_callbacks;
{ A program's own routines called back by a DLL under --os=nt: Windows calls
  them with the Microsoft convention, so the compiler hands the DLL an adapter
  (winabi's PxxWinCallback) for a routine passed straight to an external
  routine, and for every address of a `stdcall` routine (one stored in a
  variable or a record field first, as a window procedure is). Integer,
  double and single parameters, two on the stack, and msvcrt's qsort. The callees are in test/win_recdll.c (win_recdll.dll, built
  by test-windows). feature-port-windows-pe }
type
  TFD = function(a: Double; k: LongInt; b: Double): Double; cdecl;
  TF6 = function(a, b, c, d, e, f: Int64): Int64; cdecl;
  TF6M = function(a: LongInt; b: Double; c: LongInt; d: Double; e: LongInt; f: Double): Double; cdecl;
  TFS = function(a, b: Single): Single; cdecl;
  TCmp = function(a, b: Pointer): LongInt; cdecl;
  TSFD = function(a: Double; k: LongInt; b: Double): Double; stdcall;
  TSF6 = function(a, b, c, d, e, f: Int64): Int64; stdcall;
  THolder = record fn: TSFD; end;
function cb_mixed(f: TFD; a, b: Double): Double; cdecl; external 'win_recdll.dll';
function cb_six(f: TF6): Int64; cdecl; external 'win_recdll.dll';
function cb_six_mixed(f: TF6M; b, d, g: Double): Double; cdecl; external 'win_recdll.dll';
function cb_single(f: TFS; a, b: Single): Double; cdecl; external 'win_recdll.dll';
procedure qsort(base: Pointer; n, sz: Int64; cmp: TCmp); cdecl; external 'msvcrt.dll' name 'qsort';
function s_mixed(f: TSFD; a, b: Double): Double; stdcall; external 'win_recdll.dll' name 'cb_mixed';
function s_six(f: TSF6): Int64; stdcall; external 'win_recdll.dll' name 'cb_six';

function Mixed(a: Double; k: LongInt; b: Double): Double; cdecl;
begin
  Result := a * k + b;
end;

function Six(a, b, c, d, e, f: Int64): Int64; cdecl;
begin
  Result := a + b * 10 + c * 100 + d * 1000 + e * 10000 + f * 100000;
end;

function SixMixed(a: LongInt; b: Double; c: LongInt; d: Double; e: LongInt; f: Double): Double; cdecl;
begin
  Result := a * 100 + b + c * 10 + d + e + f;
end;

function Sing(a, b: Single): Single; cdecl;
begin
  Result := a * b;
end;

function Cmp(a, b: Pointer): LongInt; cdecl;
begin
  Result := PLongInt(a)^ - PLongInt(b)^;
end;

function SMixed(a: Double; k: LongInt; b: Double): Double; stdcall;
begin
  Result := a * k + b;
end;

function SSix(a, b, c, d, e, f: Int64): Int64; stdcall;
begin
  Result := a + b * 10 + c * 100 + d * 1000 + e * 10000 + f * 100000;
end;

var v: array[0..5] of LongInt; i: Integer; s: Int64; sv: TSF6; h: THolder;
begin
  WriteLn('mixed ', cb_mixed(@Mixed, 1.5, 0.25):0:3);           { (1.5*3 + 0.25) * 2 = 9.5 }
  WriteLn('six ', cb_six(@Six));                           { 654321 }
  WriteLn('six mixed ', cb_six_mixed(@SixMixed, 0.5, 0.25, 0.125):0:3);     { 100 + 0.5 + 20 + 0.25 + 3 + 0.125 = 123.875 }
  WriteLn('single ', cb_single(@Sing, 1.5, 2.0):0:3);               { 3 }
  s := 0;
  for i := 1 to 300 do s := s + cb_six(@Six);              { one adapter, not 300 }
  WriteLn('repeated ', s);
  v[0] := 5; v[1] := 3; v[2] := 9; v[3] := 1; v[4] := 7; v[5] := -2;
  qsort(@v[0], 6, 4, @Cmp);
  for i := 0 to 5 do Write(v[i], ' ');
  WriteLn;
  WriteLn('direct ', Six(1, 2, 3, 4, 5, 6));               { Pascal's own call: SysV, unchanged }
  sv := @SSix;
  WriteLn('stdcall variable ', s_six(sv));                 { 654321 }
  h.fn := @SMixed;
  WriteLn('stdcall field ', s_mixed(h.fn, 1.5, 0.25):0:3); { 9.5 }
  WriteLn('stdcall direct ', s_six(@SSix), ' ', s_mixed(@SMixed, 2, 0.5):0:3);   { not wrapped twice: 654321 13 }
  WriteLn('stdcall own call ', SSix(1, 2, 3, 4, 5, 6));
end.
