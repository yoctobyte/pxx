program test_c_cross_ns_arity;
{ See test/c_cross_ns_arity.c. sysutils is in scope purely to put the Pascal
  `Time` in the namespace the C name would otherwise bind to. }
uses sysutils, pxxcio, c_cross_ns_arity;
begin
  WriteLn('time=', cns_probe_time);   { gcc oracle: 1 }
end.
