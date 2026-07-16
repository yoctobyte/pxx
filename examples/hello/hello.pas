{ Smallest possible PXX program — a single writeln. Its real job is to show how
  little code the compiler emits when the managed-string (ansistring) runtime is
  left out: build it the default way and again with -uPXX_MANAGED_STRING and
  compare the two binaries' sizes. A bare string literal needs none of the
  refcount/heap machinery, so the frozen build is markedly smaller. }
program hello;
begin
  writeln('Greetings from PXX');
end.
