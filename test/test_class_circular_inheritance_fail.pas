{ %FAIL-style negative: a class that is its own ancestor through a CHAIN.

  This hung the compiler forever -- 100% CPU, no output, no exit, no error. The
  parent chain is stepped at ~72 sites across five files (symtab, ir, rtti_emit,
  the Pascal parser) and not one of those walks is bounded, so a cycle in
  UClsParent spins in whichever one reaches it first. The guard goes on the
  WRITE instead: only four sites assign a real parent, so refusing the link there
  means the cycle never exists and all ~72 walks terminate because the data
  cannot be cyclic -- an invariant every future walk inherits, rather than a rule
  each one has to remember.

  THREE classes, deliberately, not `TA = class(TA)`. A guard that only compared
  the base against the class being declared would pass a self-check and still
  hang here; this shape only terminates if the whole ancestor chain is walked.

  FPC rejects this spelling outright, so it is not a dialect-parity question. A
  compiler that SPINS on input it should reject is still a compiler that spins:
  the failure has no message, no exit status and no end, and it reads as a slow
  build, so the first response is to wait longer.

  The Makefile bounds this compile with `timeout`, and THAT is the assertion --
  a hang emits nothing, so there is no output to grep. Do not drop the bound.
  bug-a-four-ancestor-chain-walks-in-symtab-have-no-cycle-guard }
program test_class_circular_inheritance_fail;
type
  TC = class;
  TA = class(TC) end;
  TB = class(TA) end;
  TC = class(TB) end;
begin
end.
