program test_c_def_hijack;
{ See test/c_def_hijack.c. Four rows of the boundary table in
  bug-c-definition-of-an-intrinsic-name-overwrites-the-pascal-routine: the two
  that were already correct are the must-not-regress controls, the two that
  were wrong are the fix.

  Every value is the RTL's or the C file's, never a coincidence: the C bodies
  return sentinels (42/43/55/999) no real implementation would produce. }
uses math, './c_def_hijack.c' as cx;
begin
  { the hijacked rows: the Pascal routine must survive its C namesake }
  WriteLn('sqrt=', Sqrt(16.0):0:4);
  WriteLn('qsqrt=', math.Sqrt(16.0):0:4);
  WriteLn('exp=', Exp(0.0):0:4);
  { and the C definition must now be reachable BY NAME, which it was not
    before -- `cx.sqrt` used to be `undefined variable (sqrt)`, because no
    proc belonged to the C unit at all }
  WriteLn('cxsqrt=', cx.sqrt(16.0):0:4);
  { controls: these two rows were always correct and must stay correct }
  WriteLn('tanh=', Tanh(1.0):0:4);
  WriteLn('cxtanh=', cx.tanh(1.0):0:4);
  WriteLn('cxcube=', cx.cube(3));
  { math.pas itself was never damaged -- proves the entry was hijacked, not
    the unit }
  WriteLn('soft=', SqrtSoft(16.0):0:4);
end.
