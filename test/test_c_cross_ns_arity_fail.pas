program test_c_cross_ns_arity_fail;
{ Must NOT compile — see test/c_cross_ns_arity_fail.c. }
uses sysutils, pxxcio, c_cross_ns_arity_fail;
begin
  WriteLn('time=', cnsf_probe_time);
end.
