program test_platform_defines;
{ Asserts the compiler's platform + capability define axis (independent of CPU).
  Compiled twice by test-core: default (posix) and --platform=esp. The platform
  is set by the compiler, not the source — this program just reports which of
  the PXX_PLATFORM_* / PXX_HAS_* defines are active. See
  docs/progress/*/feature-platform-abstraction-layer.md. }
begin
{$ifdef PXX_PLATFORM_POSIX}
  writeln('platform=posix');
{$endif}
{$ifdef PXX_PLATFORM_ESP}
  writeln('platform=esp');
{$endif}
{$ifdef PXX_HAS_FILES}
  writeln('files');
{$endif}
{$ifdef PXX_HAS_SOCKETS}
  writeln('sockets');
{$endif}
{$ifdef PXX_HAS_THREADS}
  writeln('threads');
{$endif}
{$ifdef PXX_HAS_DYNLIB}
  writeln('dynlib');
{$endif}
  writeln('end');
end.
