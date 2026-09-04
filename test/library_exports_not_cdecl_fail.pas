{ MUST NOT COMPILE. `exports` naming a routine with no `cdecl` — the fork
  decide-may-exports-name-a-routine-that-is-not-cdecl answers at the reject arm.
  FPC accepts this and exports the routine under its own convention; for pxx
  that is callable and wrong from anything outside pxx, with nothing to
  diagnose it at the call. }
library library_exports_not_cdecl_fail;
function PxxLibPlain(a: Integer): Integer;
begin
  PxxLibPlain := a;
end;
exports PxxLibPlain;
begin
end.
