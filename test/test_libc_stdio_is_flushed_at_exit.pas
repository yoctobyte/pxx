{ libc's printf, reached through a `varargs` external, with NO fflush in the
  program. A PXX program exits by syscall, never through libc's exit(), so
  when stdout is a pipe or a file -- which it is under every harness -- libc
  still held all of this output when the process ended, and it was dropped
  with exit code 0. The finalizer runner now calls fflush(NULL) last in any
  executable that imports from libc.

  printf ONLY, no WriteLn: pxx's own writes are unbuffered and libc's are not,
  so mixing the two makes the ORDER depend on the buffering mode, which is
  libc's business and not what this row is about.
  Old codegen: prints nothing at all. }
program test_libc_stdio_is_flushed_at_exit;

function printf(fmt: PChar): Integer; cdecl; varargs; external 'libc.so.6';

begin
  printf(PChar('flushed %d'#10), 42);
  printf(PChar('and %s'#10), PChar('the tail'));
end.
