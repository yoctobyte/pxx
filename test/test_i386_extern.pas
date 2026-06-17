program test_i386_extern;
{ External C calls on i386: dynamic linking against libc.so.6 (ELF32 dynamic
  symbols + GOT-slot indirect call + cdecl marshalling). atoi/strlen exercise a
  pointer arg (PChar) and a 4-byte integer return. The same program links the
  64-bit libc.so.6 on x86-64, so its output is the reference. }

function atoi(s: PChar): Integer; cdecl; external 'libc.so.6';
function strlen(s: PChar): Integer; cdecl; external 'libc.so.6';

begin
  writeln(atoi(PChar('12345')));
  writeln(atoi(PChar('-99')));
  writeln(strlen(PChar('hello')));
  writeln(strlen(PChar('')));
end.
