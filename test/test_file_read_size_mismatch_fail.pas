{ %FAIL-style negative: the destination of a typed-file Read must be the
  file's own element type. Without this check a `file of Integer` read into a
  Byte would write four bytes into a one-byte slot — silent, and past the
  variable. FPC rejects the mismatch at compile time and so do we.
  feature-pascal-typed-and-untyped-files }
program test_file_read_size_mismatch_fail;
var f: file of Integer; b: Byte;
begin
  Assign(f, 'x'); Reset(f);
  Read(f, b);
end.
