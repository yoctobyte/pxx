{ Built and inspected, NEVER executed -- see hdrstatic_ffi.h. It exists so the
  neighbouring "no invented soname" assertions have a case they must reject. }
program test_header_static_body_ffi_control;
uses hdrstatic_ffi;
begin
  WriteLn(hs_ffi_declared_only(1));
end.
