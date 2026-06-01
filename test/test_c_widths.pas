program test_c_widths;
uses ctypes_lib;
begin
  { 5000000000 > 2^32; survives only if the C `long` param/return are 8-byte.
    Under the old int-collapse model this truncated to 705032704. }
  writeln(passthru(5000000000));
end.
