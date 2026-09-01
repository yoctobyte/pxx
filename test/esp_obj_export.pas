{ An ESP object built by the TWO-TEXT-SECTION writer, exporting a marked global.
  bug-a-the-esp-object-writer-exports-only-app-main-so-no-cdecl-routine-or-global-is-linkable

  `iram;` is what routes an object through writeELF32RelIram rather than
  writeELF32Rel, and it is the writer an ESP program is more likely to take --
  so testing only the plain one tests the path least used. The two have
  separate symbol-index arithmetic, and the external symbols sit AFTER the
  exported ones in both, so an index short by the export count names the wrong
  callee and still links.

  `cdecl` is deliberately absent: the Pascal frontend does not mark it on
  xtensa/riscv32 (see pasparser_proc.inc and
  bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets),
  so a Pascal ESP object can export DATA and not yet routines. The C frontend
  does mark it, which is what c_obj_esp_export.c covers. }
program esp_obj_export;

var
  EspCount: Integer; cvar;

procedure fast_tick; iram;
begin
  EspCount := EspCount + 1;
end;

begin
  fast_tick;
end.
