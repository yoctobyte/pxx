unit utlsblock;
{ One line of Pascal so a NilPy program can read a compiler-owned slot it has no
  spelling for. It exists for test_a_nilpy_program_pays_no_threadvar_area.npy:
  NilPy cannot name __pxxTlsBlockSize, and the number is the only direct
  assertion of the per-thread area's size -- everything else is a bss delta,
  which moves for a dozen unrelated reasons.

  IMPORTING THIS DOES NOT CHANGE THE ANSWER, and that is worth stating because
  it looks like it should: the size is chosen once, from the FRONTEND, before
  any import is resolved. A NilPy program gets a zero-byte area whether it
  imports Pascal or not. What the import DOES do is put a real Pascal unit on
  the compilation's chain, which is the arrangement the guard is about -- if a
  unit anywhere on that chain ever declares a threadvar, the allocator refuses
  at 0 bytes and this fixture fails to BUILD, loudly, naming the unit. }

interface

function TlsBlock: LongInt;

implementation

function TlsBlock: LongInt;
begin
  Result := __pxxTlsBlockSize;
end;

end.
