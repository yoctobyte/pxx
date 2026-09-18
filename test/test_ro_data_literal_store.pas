program test_ro_data_literal_store;
{ The read-only data segment IS the instrument: the string-literal pool is
  loaded R-only on x86-64 executables, so a store to a literal faults instead
  of landing. Two Makefile rows: this program must DIE of SIGSEGV by default,
  and must run to the end under --no-ro-data -- the second row is what keeps
  the first from passing on a program that crashes for some other reason.
  feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident }
var
  s: string;
  p: PChar;
begin
  s := 'literal';
  p := PChar(s);        { no UniqueString: p points INTO the pool }
  WriteLn('before: ', s);
  p[0] := 'X';
  WriteLn('after: ', s);
end.
