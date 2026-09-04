{ MUST NOT COMPILE — and this one is a REFUSAL, not a gap being papered over.
  `exports F name 'g'` renames the emitted symbol; pxx emits under the
  routine's own name, so accepting and ignoring the clause would write a
  library whose symbol is not the one the source asked for. Diagnosed instead. }
library library_exports_rename_fail;
function PxxLibF: Integer; cdecl;
begin
  PxxLibF := 1;
end;
exports PxxLibF name 'pxx_lib_f';
begin
end.
