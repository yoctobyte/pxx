{ The DLL half of test_nt_dll_built_by_pxx.pas: a Pascal library built with
  --os=nt --shared --threadsafe into nt_dll_pascal_lib.dll.

  What it covers, each one a way an earlier build of the DLL writer failed:
  - the initialisers and the main body run at load (Loaded is 7, then 8),
    before the adapters are built -- the adapter generator reads a typed
    constant of its own (IntLoad) that only initialisation code sets;
  - a class: its VMT slots are code addresses, measured from the code base
    and not from DllMain;
  - an exception raised and caught inside the DLL;
  - floats and more than four arguments across the MS-ABI adapters;
  - strings and the heap;
  - a threadvar, through the TLS index the loader gives the DLL. }
library nt_dll_pascal_lib;
uses SysUtils;

type
  TCounter = class
    n: Integer;
    function Next: Integer; virtual;
  end;

const Greeting: AnsiString = 'hi from the dll';
var Loaded: Integer = 7;
    Calls: Integer;
threadvar PerThread: Integer;

function TCounter.Next: Integer;
begin
  Inc(n);
  Next := n * 10;
end;

function pxx_sum(n: Integer): Integer; cdecl;
var i, s: Integer;
begin
  s := 0;
  for i := 1 to n do s := s + i;
  Inc(Calls);
  pxx_sum := s;
end;

function pxx_mix(a: Int64; x: Double; b: Integer; y: Double; c, d, e, f: Int64): Double; cdecl;
begin
  Inc(Calls);
  pxx_mix := a + x * 2 + b + y * 3 + c + d * 10 + e * 100 + f * 1000;
end;

function pxx_len(p: PChar): Integer; cdecl;
var s: AnsiString;
begin
  s := p;
  s := s + '!' + Greeting;
  Inc(Calls);
  pxx_len := Length(s);
end;

function pxx_safe_div(a, b: Integer): Integer; cdecl;
begin
  Inc(Calls);
  try
    if b = 0 then raise Exception.Create('zero');
    pxx_safe_div := a div b;
  except
    on E: Exception do pxx_safe_div := -Length(E.Message);
  end;
end;

function pxx_counter(k: Integer): Integer; cdecl;
var c: TCounter;
    i, r: Integer;
begin
  c := TCounter.Create;
  r := 0;
  for i := 1 to k do r := c.Next;
  c.Free;
  pxx_counter := r;
end;

function pxx_bump: Integer; cdecl;
begin
  PerThread := PerThread + 1;
  pxx_bump := PerThread;
end;

function pxx_loaded: Integer; cdecl;
begin
  pxx_loaded := Loaded * 1000 + Calls;
end;

procedure helper_not_exported;
begin
end;

exports pxx_sum, pxx_mix, pxx_len, pxx_safe_div, pxx_counter, pxx_bump, pxx_loaded;

begin
  Loaded := Loaded + 1;
end.
