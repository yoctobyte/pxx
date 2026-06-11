program test_cross_syscall;
{ __pxxrawsyscall intrinsic: getpid (1 arg) and the full 7-arg mmap form.
  Syscall numbers differ per target, so each arch branches on its CPU
  defines; the printed output is identical everywhere (oracle pattern). }
var pid, p: Int64;
begin
{$ifdef CPUX86_64}
  pid := __pxxrawsyscall(39);                        { getpid }
  p := __pxxrawsyscall(9, 0, 4096, 3, 34, -1, 0);    { mmap }
{$endif}
{$ifdef CPUAARCH64}
  pid := __pxxrawsyscall(172);                       { getpid }
  p := __pxxrawsyscall(222, 0, 4096, 3, 34, -1, 0);  { mmap }
{$endif}
{$ifdef CPU_ARM32}
  pid := __pxxrawsyscall(20);                        { getpid }
  p := __pxxrawsyscall(192, 0, 4096, 3, 34, -1, 0);  { mmap2 }
{$endif}
{$ifdef CPU_I386}
  pid := __pxxrawsyscall(20);                        { getpid }
  p := __pxxrawsyscall(192, 0, 4096, 3, 34, -1, 0);  { mmap2 }
{$endif}
  if pid > 0 then writeln(1) else writeln(0);
  { mmap failure is -4095..-1; high addresses go negative on 32-bit, so
    accept anything outside the errno window as success }
  if (p < -4095) or (p > 0) then writeln(1) else writeln(0);
end.
