{ bug-pascal-transitive-unit-crashes-at-startup-unless-named-first:
  `uses blcksock;` alone used to segfault before main() ever ran — a unit
  reached only TRANSITIVELY (synsock -> ssfpc.inc's `PInAddr6 = ^TInAddr6;
  TInAddr6 = sockets.Tin6_addr;` forward-pointer-to-cross-unit-alias) bound
  its pointer type to the wrong record, corrupting unrelated global memory
  during unit initialization. This is the ticket's exact 3-line repro, with
  no workaround unit named first. }
program lib_synapse_transitive_unit;
uses blcksock;
begin
  WriteLn('ok');
end.
