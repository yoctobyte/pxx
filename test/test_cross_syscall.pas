program test_cross_syscall;
{ __pxxrawsyscall intrinsic: getpid (1 arg) and the full 7-arg mmap form,
  plus a store/load through the mapped page (IR_STORE_MEM/IR_LOAD_MEM).
  Syscall numbers differ per target, so each arch branches on its CPU
  defines; the printed output is identical everywhere (oracle pattern). }
type PInt = ^Integer;
var pid, p: Int64; ok: Boolean;
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
{$ifdef CPUXTENSA}
  { xtensa linux has its own numbering, neither asm-generic nor i386's. Both
    values are the MEASURED ones from lib/rtl/platform/posix/platform_backend.pas
    (getpid=120, mmap2=80) -- do not recall them, that table records why.
    80 is mmap2, so the last arg is a page offset, and 0 is what every other
    mmap2 arm here passes too. The FLAGS also differ: xtensa's MAP_ANONYMOUS is
    $800, so MAP_PRIVATE|MAP_ANONYMOUS is $802 = 2050, not the 34 every arm
    above passes. With 34 the kernel sees no ANONYMOUS bit, tries to map fd -1,
    and returns EBADF -- which is what this row printed before the constant was
    fixed, and what PalBackendMmapAnon was doing for real. }
  pid := __pxxrawsyscall(120);                        { getpid }
  p := __pxxrawsyscall(80, 0, 4096, 3, 2050, -1, 0);  { mmap2 }
{$endif}
  if pid > 0 then writeln(1) else writeln(0);
  { mmap failure is -4095..-1; high addresses go negative on 32-bit, so
    accept anything outside the errno window as success }
  ok := (p < -4095) or (p > 0);
  if ok then writeln(1) else writeln(0);
  if ok then
  begin
    PInt(p)^ := 12345;
    writeln(PInt(p)^);
  end
  else
    writeln(-1);
end.
