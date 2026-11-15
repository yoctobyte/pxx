{ --os=nt --shared: DLLs pxx wrote itself, one from Pascal
  (nt_dll_pascal_lib.pas) and one from C (nt_dll_c_lib.c), called by a pxx
  executable. test-windows builds all three and runs this under Wine.

  The thread's three pxx_bump calls must answer 1, 2, 3 whatever the main
  thread did: the threadvar is the DLL's, per thread. }
program test_nt_dll_built_by_pxx;
uses Classes;

function pxx_sum(n: Integer): Integer; cdecl; external 'nt_dll_pascal_lib.dll';
function pxx_mix(a: Int64; x: Double; b: Integer; y: Double; c, d, e, f: Int64): Double; cdecl; external 'nt_dll_pascal_lib.dll';
function pxx_len(p: PChar): Integer; cdecl; external 'nt_dll_pascal_lib.dll';
function pxx_safe_div(a, b: Integer): Integer; cdecl; external 'nt_dll_pascal_lib.dll';
function pxx_counter(k: Integer): Integer; cdecl; external 'nt_dll_pascal_lib.dll';
function pxx_bump: Integer; cdecl; external 'nt_dll_pascal_lib.dll';
function pxx_loaded: Integer; cdecl; external 'nt_dll_pascal_lib.dll';

function c_next: Integer; cdecl; external 'nt_dll_c_lib.dll';
function c_scale(x: Double; n: Integer): Double; cdecl; external 'nt_dll_c_lib.dll';
function c_dup_len(s: PChar): Integer; cdecl; external 'nt_dll_c_lib.dll';
function c_peek: Integer; cdecl; external 'nt_dll_c_lib.dll';

type
  TBumper = class(TThread)
    r: Integer;
    procedure Execute; override;
  end;

procedure TBumper.Execute;
begin
  pxx_bump; pxx_bump;
  r := pxx_bump;
end;

var t: TBumper;
begin
  WriteLn('loaded ', pxx_loaded);
  WriteLn('sum ', pxx_sum(100));
  WriteLn('mix ', pxx_mix(1, 0.5, 2, 0.25, 3, 4, 5, 6):0:2);
  WriteLn('len ', pxx_len('hello'));
  WriteLn('div ', pxx_safe_div(42, 5));
  WriteLn('div0 ', pxx_safe_div(42, 0));
  WriteLn('counter ', pxx_counter(4));
  WriteLn('bump ', pxx_bump, ' ', pxx_bump);
  t := TBumper.Create(False);
  t.WaitFor;
  WriteLn('thread bump ', t.r);
  t.Free;
  WriteLn('bump ', pxx_bump);
  WriteLn('loaded ', pxx_loaded);
  WriteLn('c ', c_next, ' ', c_next, ' ', c_peek);
  WriteLn('c scale ', c_scale(1.5, 3):0:1);
  WriteLn('c dup ', c_dup_len('abcdef'));
end.
