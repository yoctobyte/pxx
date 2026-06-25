program test_cdecl_indirect;
{ cdecl on a proc TYPE + System V indirect call: a function pointer obtained at
  runtime (dlsym) calls with the C convention — float args/returns via xmm,
  independent int/float register classes. Without `cdecl` PXX's internal
  all-integer convention would put doubles in GP regs and miscompile. x86-64. }
type
  TSqrt  = function(x: Double): Double; cdecl;
  TPow   = function(x, y: Double): Double; cdecl;
  TLdexp = function(x: Double; e: Integer): Double; cdecl;
function dlopen(name: PChar; flag: Integer): Pointer; cdecl; external 'libc.so.6';
function dlsym(h: Pointer; s: PChar): Pointer; cdecl; external 'libc.so.6';
var
  hm: Pointer;
  fs: TSqrt;
  fp: TPow;
  fl: TLdexp;
begin
  hm := dlopen(PChar('libm.so.6'), 2);
  fs := TSqrt(dlsym(hm, PChar('sqrt')));
  fp := TPow(dlsym(hm, PChar('pow')));
  fl := TLdexp(dlsym(hm, PChar('ldexp')));
  writeln(fs(16.0):0:1);        { 4.0  - 1 float arg+return }
  writeln(fp(2.0, 10.0):0:1);   { 1024.0 - 2 float args xmm0,xmm1 }
  writeln(fl(1.5, 3):0:1);      { 12.0 - float xmm0 + int rdi }
end.
