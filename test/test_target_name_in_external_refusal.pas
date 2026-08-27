program test_target_name_in_external_refusal;
{ A cdecl external on a backend that emits no dynamic segment is refused — and
  the refusal must name the target the USER typed. It used to say "target
  esp32" for both xtensa and riscv32, so `--target=riscv32`, a hosted Linux
  target with its own qemu rows in the suite, was told about a chip it was not
  targeting. It also named no symbol and suggested nothing.
  bug-a-a-riscv32-diagnostic-names-the-wrong-target

  Compile-fail test: driven from the Makefile against three --target spellings,
  each grepped for its own name. }
function fabs(x: Double): Double; cdecl; external;
begin
  writeln(fabs(-1.5):0:2);
end.
