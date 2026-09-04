{ MUST NOT COMPILE. `exports` in a `program`, which has no export surface. }
program library_exports_in_a_program_fail;
procedure PxxLibP; cdecl;
begin
end;
exports PxxLibP;
begin
end.
