{ %FAIL-style negative: every mistake in the file is reported, including the
  ones in routines PARSED AFTER the first bad one.

  Slice 5 of feature-a-error-does-not-halt-so-a-parse-can-be-speculative. Three
  separate reasons the file used to stop early, all measured against fpc 3.2.2
  on this exact source:

  1. `class method not found` and `SizeOf: unknown type or variable` HALTED. They
     are the metaclass and type-name twins of the name diagnostics slices 1-2
     already recovered — same well-formed token stream, same nothing-to-resync.

  2. Bodies are lowered AS THEY ARE PARSED, so a poisoned stand-in reached IR
     lowering long before the driver's post-parse ErrCount halt.
     `SetLength(NoSuchArr, 3)` died on the FATAL "SetLength expects a string
     variable in IR codegen", reported at the routine's `end` line, and took
     every later routine's diagnostics with it. CompileAST now returns
     immediately once ErrCount > 0 — the compile has already failed, so there is
     nothing that emission could still be for.

  3. The stand-in itself produced MISLEADING follow-ons. PoisonSym mints an
     Integer, and `Length(NoSuchStr)` then said "Length needs a string, an array
     or a PChar, not Integer" — naming the compiler's own invention on the same
     line as the real diagnostic, where fpc prints one. ASTIsPoisoned lets a
     check stay silent about a type nobody wrote.

  So: five names, three routines, one compile, five lines, no binary. }
{$mode objfpc}{$H+}
program test_errors_across_routines_all_report_fail;
type
  TC = class
    procedure M;
  end;
procedure TC.M; begin end;
var g: Integer; c: TC;

procedure First;
begin
  g := NoSuchOne;
  SetLength(NoSuchArr, 3);        { used to be FATAL in IR lowering }
  g := Length(NoSuchStr);         { must not also complain about Integer }
end;

procedure Second;
begin
  g := TC.NoSuchClassMethod;      { used to HALT }
end;

begin
  c := TC.Create;
  First; Second;
  g := SizeOf(TNoSuchType);       { used to HALT }
end.
