/* __builtin_return_address(0) compiles for --target=esp32s3 --freestanding,
 * the way Rainyday's mm/kmalloc.c uses it (the poisoned block remembers its
 * caller). Compile-only: hosted C on xtensa runs under call0, where the
 * builtin is refused; the run-time check is test_get_pc_addr_xtensa_windowed.
 * feature-xtensa-builtin-return-address */
void poison_fill(void *p, unsigned long n, void *who);
void *tagged_alloc(void *p) {
  poison_fill(p, 64, __builtin_return_address(0));
  return p;
}
