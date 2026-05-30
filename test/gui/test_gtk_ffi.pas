program test_gtk_ffi;

{ Smoke test for Pascal `external` FFI against libgtk-3.so.0.
  Calls version getters that need no GTK init and no event loop, so the
  test terminates. Proves: soname linking, external decl, return values. }

function gtk_get_major_version: Integer; cdecl; external 'libgtk-3.so.0';
function gtk_get_minor_version: Integer; cdecl; external 'libgtk-3.so.0';
function gtk_get_micro_version: Integer; cdecl; external 'libgtk-3.so.0';

begin
  writeln('GTK ', gtk_get_major_version, '.',
          gtk_get_minor_version, '.', gtk_get_micro_version);
end.
