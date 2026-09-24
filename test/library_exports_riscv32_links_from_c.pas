{ A Pascal `library` exporting a cdecl routine, linked into a C program on
  riscv32 and called from C (test-emit-obj; the driver is
  library_exports_riscv32_driver.c, which exits with f(41)).

  riscv32 has ONE calling convention and it is C's, so the parser never sets
  ProcCdecl there. Two readers asked the flag alone: ValidateExports refused
  this `exports f` outright, and once that was fixed the object writer still
  left `f` LOCAL -- `undefined reference to f` at the C link. Exit code 42
  needs the C caller's 41 to arrive in the argument register the body reads,
  so the row checks the convention and not just the symbol. }
library library_exports_riscv32_links_from_c;

function f(x: Integer): Integer; cdecl;
begin
  f := x + 1;
end;

exports f;

begin
end.
