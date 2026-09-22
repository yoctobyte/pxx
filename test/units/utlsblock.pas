unit utlsblock;
{ One line of Pascal so a NilPy program can read a compiler-owned slot it has no
  spelling for. It exists for test_a_nilpy_program_pays_the_full_threadvar_area.npy:
  NilPy cannot name __pxxTlsBlockSize, and the number is the only direct
  assertion of the per-thread area's size -- everything else is a bss delta,
  which moves for a dozen unrelated reasons.

  THIS HEADER WAS WRITTEN FOR THE AUTOMATIC NILPY ARM, WHICH SHIPPED AND WAS
  RETIRED ON THE SAME DAY, 2026-09-19. Corrected 2026-09-22 with the fixture's
  rename. It said "a NilPy program gets a zero-byte area whether it imports
  Pascal or not" and that the allocator would refuse at 0 bytes -- both true of
  that arm and neither true now. There is no NilPy condition in
  ApplyTlsUserBytesOption at all; a NilPy program pays the full 4224 and the
  fixture asserts exactly that.

  IMPORTING THIS STILL DOES NOT CHANGE THE ANSWER, and the reason is unchanged
  and is the part worth keeping: the size is chosen once, from the FRONTEND,
  before any import is resolved. What the import DOES do is put a real Pascal
  unit on the compilation's chain, so the guard is about a MIXED compilation
  rather than a NilPy-only one -- which is the arrangement that retired the arm
  in the first place, by way of -Fu and a C unit's __thread errno. }

interface

function TlsBlock: LongInt;

implementation

function TlsBlock: LongInt;
begin
  Result := __pxxTlsBlockSize;
end;

end.
