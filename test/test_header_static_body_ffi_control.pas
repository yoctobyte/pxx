{ REFUSED AT COMPILE TIME, ON PURPOSE, AND THAT IS THE ASSERTION -- see
  hdrstatic_ffi.h. It exists so the neighbouring "no invented soname" assertions
  have a case that proves the invention machinery is live.

  It used to be built and inspected. Since e53eff428 the compiler refuses a
  header-derived soname this host cannot resolve, so the recipe now asserts the
  REFUSAL, naming libhdrstatic_ffi.so. Its other half -- proving the readelf grep
  can match at all -- is test_header_static_body_ffi_control_explicit.pas. }
program test_header_static_body_ffi_control;
uses hdrstatic_ffi;
begin
  WriteLn(hs_ffi_declared_only(1));
end.
