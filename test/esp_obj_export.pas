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
  does mark it, which is what c_obj_esp_export.c covers.

  THE EXTERNAL BELOW IS DECLARED, NOT INHERITED, and that is the point of it.
  This fixture used to name no external at all, and the row asserted on `free`
  -- a symbol that reached the object only because the RTL was pulled into
  every program unconditionally. When 523833fde made that pull evidence-based,
  this fixture stopped qualifying (no string, no array, no uses -- it is an
  integer increment), the RTL correctly stopped arriving, and the object went
  41696 -> 1688 bytes with `free` gone. The assertion then failed for a reason
  that had nothing to do with the symbol-index arithmetic it exists to check.

  So the external is spelled out here. It makes the row test what its own
  message claims -- that an external relocation names the callee the source
  named -- instead of borrowing a symbol from a runtime that may or may not be
  linked. `esp_rom_delay_us` is an ESP ROM routine, never defined by us, so it
  cannot stop being external the way `free` did. }
program esp_obj_export;

{ Never called at run time by anything here -- this object is not linked. It is
  declared so the object carries one relocation against a symbol it does not
  define, which is the input the two-text-section writer's external-symbol base
  is measured on. }
procedure esp_rom_delay_us(us: Integer); external;

var
  EspCount: Integer; cvar;

procedure fast_tick; iram;
begin
  EspCount := EspCount + 1;
  esp_rom_delay_us(EspCount);
end;

begin
  fast_tick;
end.
