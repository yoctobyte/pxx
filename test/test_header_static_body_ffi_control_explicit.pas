{ THE GREP-PIPELINE CONTROL for the two "no invented soname" assertions.
  Built and inspected, NEVER executed -- libhdrstatic_ffi.so does not exist.

  Its sibling test_header_static_body_ffi_control.pas used to do this job by
  reaching the same soname through a HEADER, and cannot any more: since
  e53eff428 the compiler REFUSES a soname it derived from a header's file name
  when this host cannot resolve it, which is exactly that shape. Correct refusal,
  and it took the control down with it.

  So the question splits, and this file answers only the second half:

    1. Is the derived-soname path still live and would a regression be seen?
       -> the sibling, which must now be REFUSED with a diagnostic naming
          libhdrstatic_ffi.so. Asserted at the compiler, not in the ELF.
    2. Can `readelf -d | grep lib<stem>.so` match this pattern AT ALL on this
       compiler? -> here.

  The second is not idle bookkeeping. The two assertions next door grep for a
  pattern they expect to be ABSENT, and on a fixed compiler those binaries have
  no dynamic section at all -- so "no match" is the right answer and is
  indistinguishable from a grep that could never match anything. Something has to
  produce a match.

  An EXPLICIT `external` clause is the right instrument for that half precisely
  because e53eff428 does not touch it: a soname the user WROTE is intent, and the
  refusal is scoped to names the compiler invented. So this keeps emitting the
  dangling DT_NEEDED the control needs, on the same compiler, by a route that is
  supposed to stay open -- the same route test_c_argspill.pas and
  test_c_lazycasing.pas rely on. }
program test_header_static_body_ffi_control_explicit;
function hs_ffi_declared_only(v: Integer): Integer; cdecl; external 'libhdrstatic_ffi.so';
begin
  WriteLn(hs_ffi_declared_only(1));
end.
