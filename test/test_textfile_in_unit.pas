program test_textfile_in_unit;
uses textfile_unit_dep;
begin
  writeln(RoundTrip('/tmp/pxx_textfile_unit_test.txt', 'hello from unit'));
end.
