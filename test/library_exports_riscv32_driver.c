/* Bare riscv32 driver for library_exports_riscv32_links_from_c.pas: calls the
   Pascal export from C and exits (Linux ecall 93) with its result, so
   qemu-riscv32's exit status is f(41). No libc -- the object is linked with
   -nostdlib, and the only thing under test is the call across the boundary. */
extern int f(int x);
void _start(void) {
  register long a0 __asm__("a0") = f(41);
  register long a7 __asm__("a7") = 93;
  __asm__ volatile ("ecall" : : "r"(a0), "r"(a7));
  for (;;) {}
}
