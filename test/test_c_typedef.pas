program test_c_typedef;
uses ctypedef_lib;
begin
  { myint = long (8 bytes): 2500000000*2 = 5000000000 survives only if the
    typedef resolves to an 8-byte type, not the truncating int. }
  writeln(twice(2500000000));
end.
