program test_c_argspill;
{ SysV stack spill: >6 integer args (sum7), >8 float args (dsum10), and a
  mixed signature where an integer spills while floats stay in xmm (mix9). }
function sum7(a,b,c,d,e,f,g: Integer): Integer; cdecl; external 'libspill.so';
function dsum10(a,b,c,d,e,f,g,h,i,j: Double): Double; cdecl; external 'libspill.so';
function mix9(a: Integer; b: Double; c,d,e,f,g,h: Integer; i: Double): Integer; cdecl; external 'libspill.so';
begin
  writeln(sum7(1,2,3,4,5,6,7));
  writeln(dsum10(1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0):0:1);
  writeln(mix9(1, 2.0, 3,4,5,6,7,8, 9.0));
end.
