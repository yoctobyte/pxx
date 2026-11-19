/* A freestanding ESP object's .data starts with the first user variable, as
   gcc's does: the fixed low block (pxx's number buffer, '-', newline) is
   dropped when nothing references it, a `static const` array goes to
   .rodata (flash) even though it is read, and the variable after it does
   not keep a hole where the array was. Rainyday's tests/xtensa/fixed.c
   checks `counter`'s address. The row reads the object's symbols and
   section sizes, on xtensa (esp32s3) and riscv32 (esp32c3).
   bug-c-xtensa-object-data-puts-a-dead-runtime-string-and-const-arrays-ahead-of-user-data */
static const char greeting[] = "constant from flash\n";
int counter = 100;
const char *names[] = { "a", "b" };     /* an array of pointers: writable */

extern void out(const char *s, long n);    /* resolved by whoever links it */

void _start(void)
{
    out(greeting, sizeof greeting - 1);
    out(names[1], counter);
}
