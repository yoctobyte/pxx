/* A C string literal passed to a function the program does NOT define (an
 * IDF/ROM external such as esp_rom_printf) must arrive as a char* to its
 * FIRST character. The riscv32 and xtensa backends skip a Pascal literal's
 * length prefix on external calls, keyed on the IR_ARG wrapper's type -- but
 * the C frontend had already lowered the literal to const_str+prefix, so the
 * prefix was skipped TWICE: esp_rom_printf("ROM %d %d\n", 5, 77) printed "d".
 * Measured by booting on esp32c3 and esp32s3 under QEMU, 2026-09-24.
 * bug-c-a-c-call-to-an-external-variadic-function-on-esp-riscv32-reaches-it-without-its-arguments
 *
 * Both shapes, because the defect was never about variadics: a fixed-arity
 * external took the same double skip. The rows around this file count the
 * double-skip instruction pair in the object; a pointer VARIABLE (p) is the
 * control that never took it. */
extern int ext_v(const char *fmt, ...);
extern int ext_f(const char *s);

int main(void) {
  const char *p = "ABCDEFGHIJ";
  ext_v("ABCDEFGHIJ", 5);
  ext_f("KLMNOPQRST");
  ext_v(p, 1);
  return 0;
}
